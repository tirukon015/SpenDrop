// The model route for questions the deterministic planner can't handle. The model is treated as untrusted: it can
// only call registered read-only tools (validated, timed out, capped per question) that run under the
// authenticated AiContext, it only sees compact tool results, and its final text must pass the grounding check —
// otherwise SpenDrop shows its own deterministic answer built from the same tool results.
import { formatMoney } from "@/lib/domain/money";
import { composeTool } from "./compose";
import { AI_LIMITS } from "./config";
import { answerFrom } from "./core";
import { toPlainText, verifyGrounding } from "./grounding";
import { understand, understoodAs } from "./normalize";
import { systemPrompt } from "./prompts/system";
import type { ChatMessage, ChatProvider } from "./providers/types";
import { ProviderError } from "./providers/types";
import { executeTool, toolSpecs, type ExecutedTool } from "./registry";
import type { FinanceRepository } from "./repository";
import { weekdayName } from "./tools";
import type { AiContext, AnswerBlock, AskAnswer, Evidence, Focus, FocusFilters } from "./types";

export interface HistoryTurn { role: "user" | "assistant"; content: string }

/**
 * The question plus SpenDrop's normalised English reading (informal / misspelt / Malay / Banglish questions).
 * Kept for the model benchmark (NORMALIZE=1); not used in production until a model shows a real gain from it.
 */
export function modelUserMessage(message: string, names: string[]): string {
  const reading = understoodAs(understand(message, names));
  return reading ? `${message}\n\n(SpenDrop's English reading of this question: "${reading}")` : message;
}

/** Tool results for the model: compact JSON with ready-formatted money so it never has to do maths. */
export function forModel(result: ExecutedTool["result"]): string {
  if (!result.ok) return JSON.stringify({ ok: false, error: result.error.message });
  const walk = (value: unknown, currency: string): unknown => {
    if (Array.isArray(value)) return value.map((v) => walk(v, currency));
    if (!value || typeof value !== "object") return value;
    const obj = value as Record<string, unknown>;
    const cur = typeof obj.currency === "string" ? obj.currency : currency;
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
      if (k === "date" && typeof v === "string" && "localDate" in obj) continue; // the local date/time is enough
      out[k] = walk(v, cur);
      if (/Minor$/.test(k) && typeof v === "number") out[`${k.replace(/Minor$/, "")}Formatted`] = formatMoney(v, cur);
    }
    return out;
  };
  return JSON.stringify({ ok: true, data: walk(result.data, "RM"), basedOnTransactions: result.evidence.transactionCount, period: result.evidence.period });
}

export async function answerWithModel(p: {
  message: string; ctx: AiContext; repo: FinanceRepository; provider: ChatProvider; history: HistoryTurn[]; focus: Focus | null;
}): Promise<AskAnswer> {
  const started = Date.now();
  const { ctx, provider } = p;
  const messages: ChatMessage[] = [
    { role: "system", content: systemPrompt({ today: ctx.today, weekday: weekdayName(ctx.today), timeZone: ctx.timeZone }) },
    ...p.history.slice(-AI_LIMITS.historyMessages).map((h) => ({ role: h.role, content: h.content.slice(0, 1000) }) as ChatMessage),
    // Benchmarked: adding modelUserMessage()'s English reading didn't measurably help qwen2.5:3b (tool choice 37% → 40%,
    // args 32% → 30%, safety 15 → 14 of 18), so the user's own words are sent as they are.
    { role: "user", content: p.message },
  ];
  const executed: ExecutedTool[] = [];
  const specs = toolSpecs();
  let finalText = "";
  let tokens = { input: 0, output: 0 };

  const meta = (extra: Partial<AskAnswer["meta"]> = {}) => ({
    requestId: ctx.requestId, intent: "UNKNOWN" as const, route: "model" as const, provider: provider.name, model: provider.model,
    tools: executed.map((e) => ({ name: e.name, ok: e.result.ok, ms: e.ms })), totalMs: Date.now() - started, ...extra,
  });

  try {
    for (let round = 0; round <= AI_LIMITS.maxToolCalls; round++) {
      const canUseTools = executed.length < AI_LIMITS.maxToolCalls;
      const response = await provider.chat({ messages, tools: canUseTools ? specs : [] });
      tokens = { input: tokens.input + (response.usage?.inputTokens ?? 0), output: tokens.output + (response.usage?.outputTokens ?? 0) };
      if (!response.toolCalls.length || !canUseTools) { finalText = response.content; break; }
      messages.push({ role: "assistant", content: response.content, toolCalls: response.toolCalls });
      for (const call of response.toolCalls) {
        if (executed.length >= AI_LIMITS.maxToolCalls) {
          messages.push({ role: "tool", toolCallId: call.id, name: call.name, content: JSON.stringify({ ok: false, error: "Tool call limit reached. Answer with what you have." }) });
          continue;
        }
        const done = await executeTool(call.name, call.arguments, ctx, p.repo);
        executed.push(done);
        messages.push({ role: "tool", toolCallId: call.id, name: call.name, content: forModel(done.result) });
      }
    }
  } catch (error) {
    const kind = error instanceof ProviderError ? error.kind : "unavailable";
    console.error(`[ai] provider ${provider.name} failed (request ${ctx.requestId}): ${error instanceof Error ? error.message : "error"}`);
    // If tools already produced a verified result, show it; otherwise a calm, honest error.
    const fallback = deterministicFrom(executed, ctx, started, meta({ groundingFallback: true }));
    if (fallback) return fallback;
    return withMeta(answerFrom({
      status: "error",
      text: kind === "timeout" ? "The AI took too long to answer. Your financial data is safe — please try a simpler question." : "I'm having trouble processing that right now. Your financial data is still safe.",
      blocks: [], followUps: ["How much did I spend this week?"],
    }, ctx, "UNKNOWN", p.focus, [], executed, started), meta());
  }

  const text = toPlainText(finalText);
  const vocabulary = await p.repo.vocabulary().catch(() => null);
  const grounding = verifyGrounding(text, executed, vocabulary ? [...vocabulary.merchants, ...vocabulary.fundingAccounts] : []);
  if (!text || !grounding.ok) {
    if (!grounding.ok) console.warn(`[ai] ungrounded model answer replaced (request ${ctx.requestId}): ${grounding.problems.slice(0, 3).join("; ")}`);
    const fallback = deterministicFrom(executed, ctx, started, meta({ groundingFallback: true }));
    if (fallback) return fallback;
    return withMeta(answerFrom({ status: "clarify", text: "I couldn't answer that from your records. Try asking about a period, a category, a merchant or an amount.", blocks: [], followUps: ["How much did I spend this week?"] }, ctx, "UNKNOWN", p.focus, [], executed, started), meta({ groundingFallback: true }));
  }

  const { blocks, evidence, transactionIds } = evidenceFrom(executed);
  const last = [...executed].reverse().find((e) => e.result.ok);
  return {
    status: "answered", text, blocks, evidence, followUps: [], focus: focusFrom(last, p.focus, transactionIds),
    meta: { ...meta(), ...(tokens.input || tokens.output ? { tokens } : {}) },
  };
}

const withMeta = (a: AskAnswer, meta: AskAnswer["meta"]): AskAnswer => ({ ...a, meta });

function evidenceFrom(executed: ExecutedTool[]) {
  const blocks: AnswerBlock[] = [];
  const evidence: Evidence[] = [];
  const transactionIds: string[] = [];
  for (const e of executed) {
    if (!e.result.ok) continue;
    const c = composeTool(e.name, e.result, { intent: e.name === "compare_periods" ? "COMPARE" : "UNKNOWN" });
    blocks.push(...c.blocks);
    evidence.push(e.result.evidence);
    transactionIds.push(...(c.transactionIds ?? []));
  }
  return { blocks: blocks.slice(0, 6), evidence, transactionIds };
}

/** SpenDrop's own answer from the last successful tool result (used when the model's text can't be trusted). */
function deterministicFrom(executed: ExecutedTool[], ctx: AiContext, started: number, meta: AskAnswer["meta"]): AskAnswer | null {
  const last = [...executed].reverse().find((e) => e.result.ok);
  if (!last || !last.result.ok) return null;
  const c = composeTool(last.name, last.result, { intent: last.name === "compare_periods" ? "COMPARE" : "UNKNOWN" });
  const answer = answerFrom(c, ctx, "UNKNOWN", null, [last.result.evidence], executed, started);
  return { ...answer, meta };
}

function focusFrom(last: ExecutedTool | undefined, previous: Focus | null, transactionIds: string[]): Focus | null {
  if (!last) return previous;
  // The args already passed the tool's strict schema, so these fields have the right types.
  const args = (last.args ?? {}) as FocusFilters & { period?: { from?: string; to?: string } };
  const period = args.period;
  return {
    intent: "UNKNOWN",
    filters: { category: args.category, merchant: args.merchant, fundingAccount: args.fundingAccount, paymentChannel: args.paymentChannel, currency: args.currency },
    span: period?.from && period.to ? { from: period.from, to: period.to } : previous?.span ?? null,
    transactionIds: transactionIds.slice(0, 10),
  };
}

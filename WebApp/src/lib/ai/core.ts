// The deterministic SpenDrop AI pipeline: QUESTION → UNDERSTAND (planner) → TOOL (registry, validated, user-scoped)
// → VERIFIED RESULT → EXPLAIN (composer). Used by the server for every question it can understand without a model,
// and by the browser demo. It has no access to secrets, providers or the network.
import { composeTool, failure, totalInsight, type Composed } from "./compose";
import type { InsightsData } from "./insights";
import { CAPABILITIES_TEXT, periodWordsOf, plan, type Plan } from "./planner";
import { executeTool, type ExecutedTool } from "./registry";
import { MemoryNotSetUpError, type FinanceRepository, type MemoryStore, type Vocabulary } from "./repository";
import { presetSpan } from "./time";
import type { TransactionDetail } from "./tools";
import type { AiContext, AskAnswer, Evidence, Focus, Intent } from "./types";

export type DeterministicOutcome =
  | { kind: "answer"; answer: AskAnswer }
  | { kind: "unknown"; general: boolean; vocabulary: Vocabulary };

export function answerFrom(composed: Composed, ctx: AiContext, intent: Intent, focus: Focus | null, evidence: Evidence[], executed: ExecutedTool[], started: number): AskAnswer {
  return {
    status: composed.status,
    text: composed.text,
    blocks: composed.blocks,
    evidence,
    followUps: composed.followUps.slice(0, 4),
    confidence: composed.confidence,
    ...(composed.insight ? { insight: composed.insight } : {}),
    ...(composed.suggestion ? { suggestion: composed.suggestion } : {}),
    focus: focus ? { ...focus, ...(composed.transactionIds ? { transactionIds: composed.transactionIds.slice(0, 10) } : {}) } : null,
    meta: {
      requestId: ctx.requestId, intent, route: "deterministic", provider: "spendrop", tools: executed.map((e) => ({ name: e.name, ok: e.result.ok, ms: e.ms })),
      totalMs: Date.now() - started,
    },
  };
}

const unavailable = (ctx: AiContext, started: number): AskAnswer => answerFrom(
  { status: "error", text: "I couldn't access your transaction data right now. Please try again in a moment.", blocks: [], followUps: [] },
  ctx, "UNKNOWN", null, [], [], started);

/** Answers the question with deterministic tools, or reports that it needs a model (`unknown`). */
export async function answerDeterministic(message: string, ctx: AiContext, repo: FinanceRepository, focus: Focus | null, memory: MemoryStore | null = null): Promise<DeterministicOutcome> {
  const outcome = await answerInner(message, ctx, repo, focus, memory);
  return outcome.kind === "answer" && outcome.understoodAs ? { kind: "answer", answer: { ...outcome.answer, understoodAs: outcome.understoodAs } } : outcome;
}

async function answerInner(message: string, ctx: AiContext, repo: FinanceRepository, focus: Focus | null, memory: MemoryStore | null): Promise<DeterministicOutcome & { understoodAs?: string }> {
  const started = Date.now();
  let vocabulary: Vocabulary;
  try {
    vocabulary = await repo.vocabulary();
  } catch {
    return { kind: "answer", answer: unavailable(ctx, started) };
  }
  const p: Plan = plan({ message, today: ctx.today, vocabulary, focus });
  if (p.kind === "unknown") return { kind: "unknown", general: p.general, vocabulary };
  if (p.kind === "reply") return { kind: "answer", understoodAs: p.understoodAs, answer: answerFrom({ status: p.status, text: p.text, blocks: [], followUps: p.followUps }, ctx, p.intent, focus, [], [], started) };
  if (p.kind === "memory") return { kind: "answer", answer: await memoryAnswer(p, memory, vocabulary, ctx, focus, started) };

  // First-time user: say so instead of "no match".
  if (vocabulary.expenseCount === 0)
    return { kind: "answer", answer: answerFrom({ status: "no_data", text: "I don't have any transaction data for you yet. Add a transaction (or import a backup) and ask me again.", blocks: [], followUps: [] }, ctx, p.intent, null, [], [], started) };

  const executed: ExecutedTool[] = [];
  const notes = [...p.notes];
  let periodWords = periodWordsOf(message, ctx.today);
  let main: ExecutedTool | null = null;
  for (const step of p.steps) {
    main = await executeTool(step.tool, step.args, ctx, repo);
    executed.push(main);
    if (!main.result.ok) break;
  }
  if (!main) return { kind: "unknown", general: false, vocabulary };

  // Controlled search expansion: only when nothing matched, one step at a time, and always mentioned.
  if (main.result.ok && main.name === "search_transactions" && (main.result.data as { total: number }).total === 0) {
    for (const expansion of p.expansions ?? []) {
      const next = await executeTool("search_transactions", expansion.args, ctx, repo);
      executed.push(next);
      if (!next.result.ok) { main = next; break; }
      if ((next.result.data as { total: number }).total > 0) { main = next; notes.unshift(expansion.note); periodWords = undefined; break; }
    }
  }

  // One strong match for a lookup → also fetch its details (note, split, receipt).
  let detail: ExecutedTool | undefined;
  if (main.result.ok && main.name === "search_transactions" && p.style?.detailIfSingle) {
    const data = main.result.data as { total: number; transactions: { id: string }[] };
    if (data.total === 1) {
      detail = await executeTool("get_transaction", { transactionId: data.transactions[0].id }, ctx, repo);
      executed.push(detail);
    }
  }

  const hints = { intent: p.intent, notes, topN: p.style?.topN, smallest: p.style?.smallest, restaurants: p.style?.restaurants, judgement: p.style?.judgement, periodWords };
  const composed = main.result.ok
    ? composeTool(main.name, main.result, hints, detail?.result.ok ? (detail.result.data as TransactionDetail) : undefined)
    : failure(main.result);
  // Evidence of what is shown (not of empty attempts before a search expansion).
  const evidence = [main, detail].flatMap((e) => (e?.result.ok ? [e.result.evidence] : []));

  // A total for this week / this month also gets one line of context against the user's own normal — only when
  // the difference is meaningful (the insight tool's thresholds), never as filler.
  if (main.result.ok && main.name === "calculate_spending" && p.intent === "CALCULATE" && !composed.insight) {
    const args = (p.steps[0]?.args ?? {}) as Record<string, unknown> & { period?: { from: string; to: string }; operation?: string };
    const unit = ["this_week", "this_month"].find((u) => { const s = presetSpan(u as "this_week", ctx.today)!; return args.period?.from === s.from && args.period?.to === s.to; });
    const results = (main.result.data as { results: unknown[] }).results;
    if (unit && args.operation === "sum" && results.length === 1 && args.amountMin === undefined) {
      const { period: _p, operation: _o, groupBy: _g, ...filters } = args; // eslint-disable-line @typescript-eslint/no-unused-vars
      const extra = await executeTool("get_spending_insights", { period: unit, ...filters }, ctx, repo);
      executed.push(extra);
      const line = extra.result.ok ? totalInsight(extra.result.data as InsightsData) : undefined;
      if (line && extra.result.ok) { composed.insight = line; evidence.push(extra.result.evidence); }
    }
  }
  return { kind: "answer", understoodAs: p.understoodAs, answer: answerFrom(composed, ctx, p.intent, p.focus, evidence, executed, started) };
}

export const capabilitiesAnswer = (ctx: AiContext, general: boolean): AskAnswer =>
  answerFrom({
    status: "clarify",
    text: general
      ? "I'm SpenDrop's assistant for your own spending data, so I can't answer general questions yet. " + CAPABILITIES_TEXT
      : "I'm not sure what you mean. " + CAPABILITIES_TEXT,
    blocks: [], followUps: ["How much did I spend this week?", "Where did my money go this week?", "Did I spend more this month?"],
  }, ctx, general ? "GENERAL" : "UNKNOWN", null, [], [], Date.now());

/** Personal memory: store / list / forget the user's own rules. Only explicit statements reach this point. */
async function memoryAnswer(p: Extract<Plan, { kind: "memory" }>, memory: MemoryStore | null, vocabulary: Vocabulary, ctx: AiContext, focus: Focus | null, started: number): Promise<AskAnswer> {
  const reply = (status: AskAnswer["status"], text: string, followUps: string[] = []) => answerFrom({ status, text, blocks: [], followUps }, ctx, p.action === "set" ? "PERSONAL_RULE" : "MEMORY", focus, [], [], started);
  if (!memory) return reply("clarify", "I can't save personal preferences here yet.");
  try {
    if (p.action === "list") {
      const rules = await memory.list();
      return rules.length
        ? reply("answered", `Here's what I remember for you: ${rules.map((r) => `${r.merchant} counts as ${r.category}`).join("; ")}. Say “forget ${rules[0].merchant}” to remove one.`)
        : reply("answered", "I haven't saved any personal rules for you yet. You can say things like “Grab is Transport for me”.");
    }
    if (p.action === "forget") {
      const removed = await memory.forget(p.subject);
      return removed
        ? reply("answered", p.subject ? `Done — I've forgotten your rule for ${p.subject}.` : `Done — I've forgotten all ${removed} of your personal rules.`)
        : reply("answered", p.subject ? `I didn't have a rule for ${p.subject}.` : "There was nothing to forget.");
    }
    await memory.setMerchantCategory(p.merchant, p.category);
    const known = vocabulary.merchants.some((m) => ` ${m.toLowerCase()} `.includes(` ${p.merchant.toLowerCase()} `));
    return reply("answered",
      `Got it — I'll treat ${p.merchant} as ${p.category} for you. ${known ? "Your transaction records aren't changed; this only affects how I group your spending in answers." : `I don't see ${p.merchant} in your records yet, but I'll use this when it appears.`} Say “forget ${p.merchant}” to undo.`,
      [`How much did I spend on ${p.category} this month?`, "What do you remember about me?"]);
  } catch (e) {
    if (e instanceof MemoryNotSetUpError) return reply("error", "Personal rules aren't set up on this database yet (migration 20261010000000_spendrop_ai_memory.sql).");
    return reply("error", "I couldn't save that right now. Please try again in a moment.");
  }
}

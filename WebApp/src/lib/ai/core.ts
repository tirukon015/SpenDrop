// The deterministic SpenDrop AI pipeline: QUESTION → UNDERSTAND (planner) → TOOL (registry, validated, user-scoped)
// → VERIFIED RESULT → EXPLAIN (composer). Used by the server for every question it can understand without a model,
// and by the browser demo. It has no access to secrets, providers or the network.
import { composeTool, failure, totalInsight, type Composed } from "./compose";
import type { InsightsData } from "./insights";
import { CAPABILITIES_TEXT, periodWordsOf, plan, type Plan } from "./planner";
import { executeTool, type ExecutedTool } from "./registry";
import { MemoryNotSetUpError, merchantKey, type FinanceRepository, type MemoryStore, type Vocabulary } from "./repository";
import { channelInfo } from "@/lib/domain/constants";
import { formatMoney } from "@/lib/domain/money";
import type { PaymentChannelId } from "@/lib/domain/types";
import { detectLanguage } from "./conversation";
import { say } from "./i18n";
import { presetSpan } from "./time";
import { toMinor } from "./tools";
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
  if (outcome.kind !== "answer") return outcome;
  const extra = { ...(outcome.understoodAs ? { understoodAs: outcome.understoodAs } : {}), ...(outcome.preface ? { preface: outcome.preface } : {}) };
  return { kind: "answer", answer: { ...outcome.answer, ...extra } };
}

async function answerInner(message: string, ctx: AiContext, repo: FinanceRepository, focus: Focus | null, memory: MemoryStore | null): Promise<DeterministicOutcome & { understoodAs?: string; preface?: string }> {
  const started = Date.now();
  let vocabulary: Vocabulary;
  try {
    // Warm the per-request caches in one round trip (accounts and personal rules are needed by most tools).
    [vocabulary] = await Promise.all([repo.vocabulary(), repo.accounts().catch(() => []), repo.personalRules().catch(() => [])]);
  } catch {
    return { kind: "answer", answer: unavailable(ctx, started) };
  }
  const p: Plan = plan({ message, today: ctx.today, vocabulary, focus });
  if (p.kind === "unknown") return { kind: "unknown", general: p.general, vocabulary };
  if (p.kind === "reply") return { kind: "answer", understoodAs: p.understoodAs, preface: p.preface, answer: answerFrom({ status: p.status, text: p.text, blocks: [], followUps: p.followUps }, ctx, p.intent, p.focus !== undefined ? p.focus : focus, [], [], started) };
  if (p.kind === "memory") return { kind: "answer", answer: await memoryAnswer(p, memory, vocabulary, ctx, focus, started) };
  const preface = p.preface;

  // First-time user: say so instead of "no match".
  if (vocabulary.expenseCount === 0)
    return { kind: "answer", answer: answerFrom({ status: "no_data", text: "I don't have any transaction data for you yet. Add a transaction (or import a backup) and ask me again.", blocks: [], followUps: [] }, ctx, p.intent, null, [], [], started) };

  const executed: ExecutedTool[] = [];
  const notes = [...p.notes];
  let periodWords = periodWordsOf(message, ctx.today);
  // A total for this week / this month also gets one line against the user's normal: that read is independent of
  // the main calculation, so it runs at the same time (used only when the main result is a single-currency total).
  const insightArgs = (() => {
    const args = (p.steps[0]?.args ?? {}) as Record<string, unknown> & { period?: { from: string; to: string }; operation?: string };
    if (p.intent !== "CALCULATE" || p.steps[0]?.tool !== "calculate_spending" || args.operation !== "sum" || args.amountMin !== undefined) return null;
    const unit = ["this_week", "this_month"].find((u) => { const sp = presetSpan(u as "this_week", ctx.today)!; return args.period?.from === sp.from && args.period?.to === sp.to; });
    if (!unit) return null;
    const { period: _p, operation: _o, groupBy: _g, ...filters } = args; // eslint-disable-line @typescript-eslint/no-unused-vars
    return { period: unit, ...filters };
  })();
  const insightRun = insightArgs ? executeTool("get_spending_insights", insightArgs, ctx, repo) : null;

  const step0 = p.steps[0];
  const synonymRun = p.style?.fallbackKeyword && step0 && (step0.tool === "calculate_spending" || step0.tool === "search_transactions") && (step0.args as { category?: string }).category
    ? (() => { const { category: _c, ...rest } = step0.args as Record<string, unknown>; return executeTool(step0.tool, { ...rest, remark: p.style!.fallbackKeyword }, ctx, repo); })() // eslint-disable-line @typescript-eslint/no-unused-vars
    : null;

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

  // A narrower word than its category ("rent", "internet", "tuition" → Bills / Education): when the user's remarks
  // mention it, those transactions answer the question (the category is broader). Ran alongside the main query.
  if (synonymRun) {
    const alt = await synonymRun;
    const empty = (e: ExecutedTool) => e.result.ok && (e.name === "calculate_spending" ? (e.result.data as { results: unknown[] }).results.length === 0 : (e.result.data as { total: number }).total === 0);
    if (alt.result.ok && !empty(alt)) {
      executed.push(alt);
      const category = (main.args as { category?: string }).category;
      main = alt;
      notes.unshift(`I used the transactions whose remarks mention “${p.style!.fallbackKeyword}”${category ? ` (your ${category} category is broader)` : ""}.`);
    }
  }

  // A precise amount ("RM103.88") with no exact match in the default window: an exact match anywhere in the user's
  // records is the transaction they mean (said plainly). Round amounts stay approximate.
  if (main.result.ok && main.name === "search_transactions") {
    const args = main.args as { targetAmount?: number; period?: unknown; currency?: string };
    const data = main.result.data as { transactions: { matchReason?: string }[] };
    const precise = typeof args.targetAmount === "number" && Math.round(args.targetAmount * 100) % 100 !== 0;
    if (precise && args.period && !data.transactions.some((c) => c.matchReason === "exact amount")) {
      const exact = await executeTool("search_transactions", { amountMin: args.targetAmount, amountMax: args.targetAmount, targetAmount: args.targetAmount, ...(args.currency ? { currency: args.currency } : {}), sort: "date_desc", limit: 10 }, ctx, repo);
      executed.push(exact);
      if (exact.result.ok && (exact.result.data as { total: number }).total > 0) {
        main = exact;
        notes.unshift("It's older than the last 30 days, so I searched all your records for that exact amount.");
        periodWords = undefined;
      }
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

  // Still nothing for a remembered amount: don't end the conversation — offer the all-records search ("yes" runs it).
  const searchData = main.result.ok && main.name === "search_transactions" ? (main.result.data as { total: number; period: unknown }) : null;
  const offer = searchData && searchData.total === 0 && searchData.period && p.offer ? p.offer : undefined;

  // The answer is worded in the user's language; the verified figures and stored names are the same in every language.
  const lang = detectLanguage(message);
  const a0 = (p.steps[0]?.args ?? {}) as { category?: string; merchant?: string; fundingAccount?: string; paymentChannel?: PaymentChannelId; paymentChannels?: PaymentChannelId[] };
  const subjectParts = {
    category: a0.category, merchant: a0.merchant, fundingAccount: a0.fundingAccount,
    channels: a0.paymentChannel ? channelInfo(a0.paymentChannel).label : a0.paymentChannels?.length ? [...new Set(a0.paymentChannels.map((c) => channelInfo(c).label))].join(" / ") : undefined,
  };
  const hints = {
    intent: p.intent, notes, topN: p.style?.topN, smallest: p.style?.smallest, restaurants: p.style?.restaurants, judgement: p.style?.judgement, periodWords,
    lang, subjectParts, frequency: p.style?.frequency, channelFamilies: p.style?.channelFamilies, askedDirection: p.style?.askedDirection, explain: p.style?.explain,
  };
  const composed = main.result.ok
    ? composeTool(main.name, main.result, hints, detail?.result.ok ? (detail.result.data as TransactionDetail) : undefined)
    : failure(main.result);
  // Evidence of what is shown (not of empty attempts before a search expansion).
  const evidence = [main, detail].flatMap((e) => (e?.result.ok ? [e.result.evidence] : []));

  // A total for this week / this month also gets one line of context against the user's own normal — only when
  // the difference is meaningful (the insight tool's thresholds), never as filler.
  if (insightRun && main.result.ok && main.name === "calculate_spending" && !composed.insight) {
    const results = (main.result.data as { results: unknown[] }).results;
    const extra = await insightRun;
    if (results.length === 1) {
      executed.push(extra);
      const line = extra.result.ok ? totalInsight(extra.result.data as InsightsData) : undefined;
      if (line && extra.result.ok) { composed.insight = line; evidence.push(extra.result.evidence); }
    }
  }
  if (offer) {
    const target = (offer.args.targetAmount as number | undefined) ?? null;
    const amount = target !== null ? formatMoney(toMinor(target), (offer.args.currency as string | undefined) ?? "RM") : null;
    composed.text += " " + ((amount && say.lookupOffer(lang, { target: amount })) ?? `Want me to search all your transactions for ${amount ? `an amount around ${amount}` : "it"}?`);
    composed.followUps = [offer.label, ...composed.followUps.filter((f) => !/search all/i.test(f))];
  }
  const nextFocus = p.focus ? { ...p.focus, offer } : p.focus;
  return { kind: "answer", understoodAs: p.understoodAs, preface, answer: answerFrom(composed, ctx, p.intent, nextFocus, evidence, executed, started) };
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
    if (p.action === "lookup") {
      // Personal interpretation vs stored truth: the rule (if any) is reported separately from what the records say.
      const rule = (await memory.list()).find((r) => r.merchantKey === merchantKey(p.subject) || ` ${merchantKey(p.subject)} `.includes(` ${r.merchantKey} `));
      return rule
        ? reply("answered", `You told me to treat ${rule.merchant} as ${rule.category}. That's only how I group your spending — each transaction still keeps the category it was saved with.`, [`How much did I spend on ${rule.category} this month?`, `Forget ${rule.merchant}`])
        : reply("answered", `You haven't given me a rule for ${p.subject}, so I use the category saved on each transaction. Say “${p.subject} is Transport for me” (or another category) to set one.`, [`Show my ${p.subject} transactions`]);
    }
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

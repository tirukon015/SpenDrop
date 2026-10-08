// Deterministic answers from verified tool results: a short direct answer first, then the evidence (structured
// blocks the UI renders) and useful follow-ups. Every figure in the text comes from a tool result — nothing is
// calculated or invented here beyond picking and formatting what the tools returned. Wording distinguishes
// "I found" (confirmed), "possible matches" (ambiguous) and "I couldn't find" (no data).
import { channelInfo } from "@/lib/domain/constants";
import { formatMoney } from "@/lib/domain/money";
import { formatSpan } from "./time";
import type { InsightsData } from "./insights";
import type {
  AppliedRule, CalculateData, CompareData, SearchData, TransactionDetail, UnusualData, UnusualFinding, WeeklySummaryData,
} from "./tools";
import { weekdayName } from "./tools";
import type { Lang } from "./conversation";
import { periodText, say, type SubjectParts } from "./i18n";
import type { AnswerBlock, AnswerStatus, Confidence, Intent, PeriodInfo, ToolResult, TxnCard } from "./types";

export interface Composed {
  status: AnswerStatus;
  text: string;
  blocks: AnswerBlock[];
  followUps: string[];
  confidence?: Confidence;
  transactionIds?: string[];
  /** A data-based observation after the direct answer. */
  insight?: string;
  /** An optional, evidence-based suggestion (clearly not financial advice). */
  suggestion?: string;
}

export interface ComposeHints {
  intent: Intent;
  notes?: string[];
  topN?: number;
  smallest?: boolean;
  restaurants?: boolean;
  judgement?: boolean;
  /** How the user named the main period ("this week"), shown before the exact dates. */
  periodWords?: string;
  /** The language the user wrote in (the figures are identical in every language). */
  lang?: Lang;
  /** The question's subject (category / merchant / account / channel names exactly as stored), for other languages. */
  subjectParts?: SubjectParts;
  /** "How often…": a count of transactions on distinct days — never "visits". */
  frequency?: boolean;
  /** "Card or QR?": the families compared. */
  channelFamilies?: string[];
  /** "Is it increasing?" = up, "is it going down?" = down: yes / no follows the question asked. */
  askedDirection?: "up" | "down";
}

const money = formatMoney;
const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
const signed = (minor: number, currency: string) => `${minor >= 0 ? "+" : "−"}${money(Math.abs(minor), currency)}`;
const pct = (p: number | null) => (p === null ? "" : ` (${p >= 0 ? "+" : "−"}${Math.abs(p)}%)`);
/** "this week (5–11 Oct 2026)", "on 7 Oct 2026", "in 1–7 Sep 2026" or "across all your records". */
const when = (p: PeriodInfo | null, words?: string) =>
  !p ? "across all your records" : words ? `${words} (${p.label})` : p.from === p.to ? `on ${p.label}` : `in ${p.label}`;
const onDay = (c: TxnCard) => `${formatSpan({ from: c.localDate, to: c.localDate })}, ${c.localTime}`;
const how = (c: TxnCard) => {
  const from = c.fundingAccount && c.fundingAccount !== "Unknown" ? `from ${c.fundingAccount}` : "account unknown";
  const via = c.paymentChannel !== "UNKNOWN" ? `via ${channelInfo(c.paymentChannel).label}` : "payment channel unknown";
  return `${from}, ${via}`;
};
const cardLine = (c: TxnCard) => `${money(c.amountMinor, c.currency)} at ${c.merchant} on ${onDay(c)} (${c.category}, ${how(c)})`;

export function failure(result: ToolResult & { ok: false }): Composed {
  const { kind, message } = result.error;
  if (kind === "unavailable" || kind === "timeout") return { status: "error", text: "I couldn't access your transaction data right now. Please try again in a moment.", blocks: [], followUps: [] };
  if (kind === "not_found") return { status: "no_match", text: "I couldn't find that transaction in your records. It may have been deleted.", blocks: [], followUps: [] };
  return { status: "clarify", text: message, blocks: [], followUps: [] };
}

const withNotes = (c: Composed, notes: string[] | undefined): Composed => (notes?.length ? { ...c, text: `${c.text}\n\n${notes.join(" ")}` } : c);

/** Personal rules are always disclosed: the user should see when their own rule changed an answer. */
/** A merchant name that matched several merchants is disclosed ("Shopee" → Shopee, Shopee Food). */
export const merchantNote = (names: string[] | undefined): string[] =>
  names && names.length > 1 ? [`This includes ${names.length} merchant names: ${names.slice(0, 5).join(", ")}${names.length > 5 ? "…" : ""}.`] : [];

export function ruleNote(rules: AppliedRule[] | undefined): string[] {
  if (!rules?.length) return [];
  return [`Using your personal rule${rules.length > 1 ? "s" : ""}: ${rules.map((r) => `${r.merchant} counts as ${r.category} (${plural(r.count, "transaction")})`).join("; ")}. Your records themselves aren't changed.`];
}

// ---------------------------------------------------------------------------------------------------------------

export function composeSearch(d: SearchData, hints: ComposeHints, detail?: TransactionDetail): Composed {
  const h = { ...hints, notes: [...(hints.notes ?? []), ...ruleNote(d.personalRules), ...merchantNote(d.merchantsMatched)] };
  const cards = d.transactions;
  const ids = cards.map((c) => c.id);
  const target = d.target.amountMinor !== null ? ` close to ${money(d.target.amountMinor, d.transactions[0]?.currency ?? "RM")}` : "";
  const scope = `${d.subject}${target} ${when(d.period, h.periodWords)}`;
  if (d.total === 0)
    return withNotes({
      status: "no_match", confidence: "NO_MATCH",
      text: target ? `I couldn't find a transaction${d.subject}${target} ${d.period ? (h.periodWords ? when(d.period, h.periodWords) : `in that period (${d.period.label})`) : "in any of your records"}.` : `I couldn't find a transaction matching that${scope}.`,
      blocks: [], followUps: d.period ? ["Search all my records", "Show my recent transactions"] : ["Show my recent transactions"],
    }, h.notes);

  // Biggest / smallest
  if (h.topN) {
    const top = cards[0];
    const text = h.topN === 1
      ? `Your ${h.smallest ? "smallest" : "biggest"} purchase${d.subject} ${when(d.period, h.periodWords)} was ${cardLine(top)}.`
      : `Here are your ${Math.min(h.topN, cards.length)} ${h.smallest ? "smallest" : "biggest"} purchases${d.subject} ${when(d.period, h.periodWords)}.`;
    return withNotes({ status: "answered", text, blocks: [{ type: "transactions", title: "Transactions", items: cards.slice(0, h.topN) }], followUps: ["Tell me more about the first one", "Which category costs me the most?"], transactionIds: ids }, h.notes);
  }

  // Lookups ("where did my RM15 go?")
  if (d.confidence) {
    if (d.total === 1) {
      const c = cards[0];
      let text = `I found it: ${cardLine(c)}.`;
      if (c.isShared) text += ` Your share was ${money(c.spendMinor, c.currency)}.`;
      if (detail) {
        if (detail.notes) text += ` Your note says: “${detail.notes}”.`;
        text += detail.receipt.available
          ? " A receipt image is attached — open the transaction to see it. I can't read the receipt's items, so I can't confirm exactly what was bought."
          : "";
      }
      return withNotes({ status: "answered", confidence: "HIGH", text, blocks: [{ type: "transactions", title: "Match", items: [c] }], followUps: ["Show other transactions there", "How much did I spend there this month?"], transactionIds: ids }, h.notes);
    }
    const shown = cards.slice(0, 5);
    const text = d.total <= 5
      ? `I found ${d.total} possible matches${scope}. Which one are you looking for?`
      : `I found ${d.total} transactions that could match${scope}. Do you remember the merchant or the day? Here are the closest ${shown.length}.`;
    return withNotes({
      status: "clarify", confidence: d.total <= 5 ? "MEDIUM" : "LOW", text,
      blocks: [{ type: "transactions", title: "Possible matches", items: shown, more: Math.max(0, d.total - shown.length) }],
      followUps: ["Tell me more about the first one"], transactionIds: shown.map((c) => c.id),
    }, h.notes);
  }

  // Lists ("show my Shopee purchases")
  const text = d.total > cards.length
    ? `I found ${plural(d.total, "transaction")}${scope}. Here are the ${cards.length} most recent.`
    : `I found ${plural(d.total, "transaction")}${scope}.`;
  return withNotes({ status: "answered", text, blocks: [{ type: "transactions", title: "Transactions", items: cards, more: Math.max(0, d.total - d.offset - cards.length) }], followUps: ["How much is that in total?", "Tell me more about the first one"], transactionIds: ids }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------

const DIMENSION: Record<string, { noun: string; block: "category" | "merchant" | "account" | "channel" | "day" }> = {
  category: { noun: "category", block: "category" },
  merchant: { noun: "merchant", block: "merchant" },
  funding_account: { noun: "funding account", block: "account" },
  payment_channel: { noun: "payment channel", block: "channel" },
  channel_family: { noun: "payment channel", block: "channel" },
  day: { noun: "day", block: "day" },
};

export function composeCalculate(d: CalculateData, hints: ComposeHints): Composed {
  const h = { ...hints, notes: [...(hints.notes ?? []), ...ruleNote(d.personalRules), ...merchantNote(d.merchantsMatched)] };
  const subject = d.subject;
  const period = when(d.period, h.periodWords);
  const lang = h.lang ?? "en";
  const periodL = periodText(lang, d.period, h.periodWords);
  const parts0 = h.subjectParts ?? {};
  if (d.results.length === 0)
    return withNotes({ status: "no_match", text: say.nothing(lang, { subject: parts0, period: periodL }) ?? `Your records show no spending${subject} ${period}.`, blocks: [], followUps: ["Show my recent transactions"] }, h.notes);

  const blocks: AnswerBlock[] = [];
  const multi = d.results.length > 1;
  const parts = d.results.map((r) => money(r.valueMinor ?? 0, r.currency));
  let text: string;
  const followUps: string[] = [];

  if (d.groupBy !== "none") {
    const dim = DIMENSION[d.groupBy];
    const lines = d.results.map((r) => {
      const groups = r.groups ?? [];
      const top = groups[0];
      blocks.push({ type: "breakdown", title: h.restaurants ? "Food merchants" : `By ${dim.noun}${multi ? ` · ${r.currency}` : ""}`, currency: r.currency, kind: dim.block, items: groups.map((g) => ({ key: g.key, label: g.label, valueMinor: g.valueMinor, count: g.count })) });
      if (!top) return "";
      const mostUsed = [...groups].sort((a, b) => b.count - a.count)[0];
      const others = groups.slice(1, 3).map((g) => `${g.label} (${money(g.valueMinor, r.currency)})`);
      let line = h.restaurants
        ? `Your Food spending ${period} was at ${groups.slice(0, 3).map((g) => `${g.label} (${money(g.valueMinor, r.currency)})`).join(", ")}${groups.length > 3 ? ` and ${groups.length - 3} more` : ""}.`
        : `${h.intent === "CATEGORY_ANALYSIS" && d.groupBy === "category" ? "Most of your money" : `Your top ${dim.noun}`}${subject} ${period} ${h.intent === "CATEGORY_ANALYSIS" && d.groupBy === "category" ? "went to" : "is"} ${top.label}: ${money(top.valueMinor, r.currency)} (${top.sharePct}% of ${money(r.valueMinor ?? 0, r.currency)}, ${plural(top.count, "transaction")}).${others.length ? ` Then ${others.join(" and ")}.` : ""}`;
      if (!h.restaurants && mostUsed && mostUsed.key !== top.key && (d.groupBy === "funding_account" || d.groupBy === "payment_channel" || d.groupBy === "channel_family"))
        line += ` By number of payments it's ${mostUsed.label} (${mostUsed.count}).`;
      // "Card or QR?": answer the comparison that was asked, from the same verified groups.
      if (h.channelFamilies?.length && d.groupBy === "channel_family") {
        const asked = h.channelFamilies.length >= 2 ? groups.filter((g) => h.channelFamilies!.includes(g.label)) : groups;
        const rest = asked.filter((g) => g.key !== asked[0]?.key);
        const missing = h.channelFamilies.filter((f) => !groups.some((g) => g.label === f));
        const w = asked[0];
        if (w) {
          const localized = say.channels(lang, { winner: w.label, wAmount: money(w.valueMinor, r.currency), wCount: w.count, rest: rest.map((g) => ({ label: g.label, amount: money(g.valueMinor, r.currency), count: g.count })), period: periodL });
          line = localized ?? `You paid more by ${w.label}${subject} ${period}: ${money(w.valueMinor, r.currency)} across ${plural(w.count, "transaction")}${rest.length ? `, vs ${rest.map((g) => `${g.label} ${money(g.valueMinor, r.currency)} (${plural(g.count, "transaction")})`).join(", ")}` : ""}.${missing.length ? ` No ${missing.join(" or ")} payments were recorded.` : ""}`;
          const byCount = [...asked].sort((a, b) => b.count - a.count)[0];
          if (!localized && byCount && byCount.key !== w.key) line += ` By number of payments it's ${byCount.label} (${byCount.count}).`;
          return line;
        }
      }
      return say.top(lang, { label: top.label, amount: money(top.valueMinor, r.currency), pct: top.sharePct, count: top.count, period: periodL, others }) ?? line;
    }).filter(Boolean);
    text = lines.join(" ");
    followUps.push(d.groupBy === "category" ? "Why did I spend more this month?" : "Show the transactions", "Compare with last month");
  } else if (d.operation === "count") {
    const r0 = d.results[0];
    const localized = !multi ? say.count(lang, { count: r0.transactionCount, days: h.frequency && r0.distinctDays !== r0.transactionCount ? r0.distinctDays : undefined, subject: parts0, period: periodL }) : null;
    text = localized ?? (h.frequency && !multi && r0.distinctDays !== undefined
      ? `You had ${plural(r0.transactionCount, "transaction")}${subject} ${period}${r0.distinctDays !== r0.transactionCount ? `, on ${plural(r0.distinctDays, "different day")}` : ""}.`
      : `You made ${d.results.map((r) => `${plural(r.transactionCount, "transaction")}${multi ? ` in ${r.currency}` : ""}`).join(" and ")}${subject} ${period}.`);
    for (const r of d.results) if (r.transactions?.length) blocks.push({ type: "transactions", title: "Transactions", items: r.transactions, more: Math.max(0, r.transactionCount - r.transactions.length) });
    followUps.push("How much was that in total?");
  } else if (d.operation === "average") {
    text = `Your average transaction${subject} ${period} was ${d.results.map((r) => `${money(r.valueMinor ?? 0, r.currency)} (over ${plural(r.transactionCount, "transaction")})`).join(" and ")}.`;
  } else if (d.operation === "min" || d.operation === "max") {
    text = d.results.map((r) => `Your ${d.operation === "max" ? "largest" : "smallest"} transaction${subject} ${period} was ${r.transaction ? cardLine(r.transaction) : money(r.valueMinor ?? 0, r.currency)}.`).join(" ");
    for (const r of d.results) if (r.transaction) blocks.push({ type: "transactions", title: "Transaction", items: [r.transaction] });
  } else {
    const count = d.results.reduce((t, r) => t + r.transactionCount, 0);
    text = multi
      ? `You spent ${parts.join(" and ")}${subject} ${period}. I keep currencies separate and don't convert between them.`
      : `You spent ${parts[0]}${subject} ${period}.`;
    text += ` Based on ${plural(count, "transaction")}.`;
    text = say.spent(lang, { amounts: parts.join(" + "), count, subject: parts0, period: periodL, multiCurrency: multi }) ?? text;
    for (const r of d.results) blocks.push({ type: "metric", label: `${d.filters === "All spending" ? "Spending" : d.filters}${multi ? ` · ${r.currency}` : ""}`, valueMinor: r.valueMinor ?? 0, currency: r.currency, caption: `${d.period?.label ?? "All time"} · ${plural(r.transactionCount, "transaction")}` });
    // Evidence: the transactions that make up each total.
    for (const r of d.results) if (r.transactions?.length) blocks.push({ type: "transactions", title: `The ${plural(r.transactionCount, "transaction")}${multi ? ` · ${r.currency}` : ""}`, items: r.transactions, more: Math.max(0, r.transactionCount - r.transactions.length) });
    followUps.push("Why?", "Show the transactions", "Compare with last month");
  }
  if (d.refunds.length)
    text += ` You also received ${d.refunds.map((r) => money(r.totalMinor, r.currency)).join(" and ")} in refunds in this period (shown separately, not deducted).`;
  return withNotes({ status: "answered", text, blocks, followUps }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------

export function composeCompare(d: CompareData, hints: ComposeHints): Composed {
  const h = { ...hints, notes: [...(hints.notes ?? []), ...ruleNote(d.personalRules)] };
  const subject = `spending${d.subject}`;
  if (d.results.length === 0)
    return withNotes({ status: "no_match", text: `There's no ${subject} recorded in ${d.a.label} or ${d.b.label}.`, blocks: [], followUps: [] }, h.notes);
  const blocks: AnswerBlock[] = [];
  const sentences: string[] = [];
  for (const r of d.results) {
    const c = r.currency;
    blocks.push({ type: "comparison", currency: c, a: { label: d.a.label, valueMinor: r.aMinor, count: r.aCount }, b: { label: d.b.label, valueMinor: r.bMinor, count: r.bCount }, diffMinor: r.diffMinor, pct: r.pctChange });
    const up = r.contributions.filter((x) => x.diffMinor > 0), down = r.contributions.filter((x) => x.diffMinor < 0);
    if (h.intent === "INVESTIGATE") {
      let s = `Your ${subject} in ${d.a.label} was ${money(r.aMinor, c)} across ${plural(r.aCount, "transaction")}`;
      if (r.bMinor === 0 && r.bCount === 0) s += `; nothing was recorded in ${d.b.label} to compare with.`;
      else if (r.diffMinor === 0) s += `, the same as ${d.b.label}.`;
      else s += `, ${money(Math.abs(r.diffMinor), c)} ${r.diffMinor > 0 ? "more" : "less"} than ${d.b.label} (${money(r.bMinor, c)}).`;
      const drivers = r.diffMinor >= 0 ? up : down;
      // "Biggest contributors" (verified per-group differences) — never "because of".
      if (drivers.length && r.diffMinor !== 0)
        s += ` The biggest contributor${drivers.length > 1 ? "s were" : " was"} ${drivers.slice(0, 3).map((x) => `${x.label} (${signed(x.diffMinor, c)})`).join(", ")}.`;
      const offset = r.diffMinor >= 0 ? down : up;
      if (offset.length && r.diffMinor !== 0) s += ` Partly offset by ${offset.slice(0, 2).map((x) => `${x.label} (${signed(x.diffMinor, c)})`).join(", ")}.`;
      if (r.largestInA[0]) s += ` Your largest was ${cardLine(r.largestInA[0])}.`;
      sentences.push(s);
    } else {
      let s: string;
      if (r.bMinor === 0 && r.bCount === 0) s = `You spent ${money(r.aMinor, c)}${d.subject} in ${d.a.label}; nothing was recorded in ${d.b.label}.`;
      else if (r.diffMinor === 0) s = `You spent the same in ${d.a.label} as in ${d.b.label}: ${money(r.aMinor, c)}.`;
      else if (h.askedDirection || (h.lang && h.lang !== "en")) {
        const more = r.diffMinor > 0;
        const yes = h.askedDirection ? (h.askedDirection === "up") === more : more;
        s = say.compared(h.lang ?? "en", { yes, more, diff: money(Math.abs(r.diffMinor), c), a: money(r.aMinor, c), aLabel: d.a.label, b: money(r.bMinor, c), bLabel: d.b.label, pct: r.pctChange, subject: h.subjectParts ?? {} })
          ?? `${yes ? "Yes" : "No"} — your spending${d.subject} ${more ? "went up" : "went down"}: ${money(r.aMinor, c)} in ${d.a.label} vs ${money(r.bMinor, c)} in ${d.b.label} (${signed(r.diffMinor, c)}${r.pctChange === null ? "" : `, ${more ? "up" : "down"} ${Math.abs(r.pctChange)}%`}).`;
      }
      else s = `${r.diffMinor > 0 ? "Yes — you" : "No — you"} spent ${money(Math.abs(r.diffMinor), c)} ${r.diffMinor > 0 ? "more" : "less"}${d.subject} in ${d.a.label} (${money(r.aMinor, c)}) than in ${d.b.label} (${money(r.bMinor, c)})${r.pctChange === null ? "" : `, ${r.pctChange >= 0 ? "up" : "down"} ${Math.abs(r.pctChange)}%`}.`;
      sentences.push(s);
    }
    if (r.contributions.length)
      blocks.push({ type: "breakdown", title: `What changed${d.results.length > 1 ? ` · ${c}` : ""}`, currency: c, kind: DIMENSION[d.breakdownBy].block, items: r.contributions.map((x) => ({ key: x.key, label: x.label, valueMinor: x.aMinor, count: 0, diffMinor: x.diffMinor })) });
    if (h.intent === "INVESTIGATE" && r.largestInA.length) blocks.push({ type: "transactions", title: `Largest in ${d.a.label}`, items: r.largestInA });
  }
  if (d.results.length > 1) sentences.push("Each currency is compared separately.");
  if (h.judgement) sentences.push("Whether that's too much depends on your own goals — this is what your records show, not financial advice.");
  return withNotes({
    status: "answered", text: sentences.join(" "), blocks,
    followUps: h.intent === "INVESTIGATE" ? ["Which merchants?", "Show my biggest purchases this month"] : ["Why?", "Which category costs me the most?"],
    transactionIds: h.intent === "INVESTIGATE" ? d.results.flatMap((r) => r.largestInA.map((c) => c.id)) : undefined,
  }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------

export function composeWeekly(d: WeeklySummaryData, h: ComposeHints): Composed {
  const c = d.currency;
  const inProgress = d.elapsed.to !== d.week.to;
  const label = inProgress ? `This week so far (${d.elapsed.label})` : `In the week of ${d.week.label}`;
  if (d.count === 0 && d.otherCurrencies.length === 0)
    return withNotes({ status: "no_match", text: `${label} you haven't recorded any spending.`, blocks: [], followUps: ["How much did I spend last week?"] }, h.notes);
  const s: string[] = [];
  s.push(`${label} you spent ${money(d.totalMinor, c)} across ${plural(d.count, "transaction")}.`);
  if (d.previousWeek.totalMinor > 0 || d.previousWeek.diffMinor !== 0) {
    s.push(d.previousWeek.diffMinor === 0 ? `That's the same as the same days last week.`
      : `That's ${money(Math.abs(d.previousWeek.diffMinor), c)} ${d.previousWeek.diffMinor > 0 ? "more" : "less"} than the same days last week (${money(d.previousWeek.totalMinor, c)}).`);
  }
  // The direct answer stays short; the rest is context (insight), each figure straight from the summary.
  const more: string[] = [];
  if (d.fourWeekAverage.averageMinor !== null && d.fourWeekAverage.pctChange !== null)
    more.push(`Your 4-week average for the same days is ${money(d.fourWeekAverage.averageMinor, c)}, so this week is ${Math.abs(d.fourWeekAverage.pctChange)}% ${d.fourWeekAverage.pctChange >= 0 ? "higher" : "lower"}.`);
  else more.push("I don't have enough history yet for a 4-week average.");
  if (d.categories[0]) more.push(`Biggest category: ${d.categories[0].label} (${money(d.categories[0].valueMinor, c)}).`);
  if (d.largestTransaction) more.push(`Largest transaction: ${money(d.largestTransaction.amountMinor, d.largestTransaction.currency)} at ${d.largestTransaction.merchant}.`);
  const topDay = [...d.byDay].sort((a, b) => b.valueMinor - a.valueMinor)[0];
  if (topDay && topDay.valueMinor > 0 && d.byDay.length > 1) more.push(`Most expensive day: ${weekdayName(topDay.date)} (${money(topDay.valueMinor, c)}).`);
  if (d.refunds.length) s.push(`Refunds received: ${d.refunds.map((r) => money(r.totalMinor, r.currency)).join(", ")} (not deducted).`);
  if (d.otherCurrencies.length) s.push(`You also spent ${d.otherCurrencies.map((o) => money(o.totalMinor, o.currency)).join(" and ")} in other currencies (kept separate).`);
  const blocks: AnswerBlock[] = [
    { type: "metric", label: inProgress ? "This week so far" : "Week total", valueMinor: d.totalMinor, currency: c, caption: `${d.elapsed.label} · ${plural(d.count, "transaction")}` },
    { type: "breakdown", title: "By category", currency: c, kind: "category", items: d.categories.map((g) => ({ key: g.key, label: g.label, valueMinor: g.valueMinor, count: g.count })) },
    { type: "breakdown", title: "By day", currency: c, kind: "day", items: d.byDay.map((x) => ({ key: x.date, label: `${weekdayName(x.date).slice(0, 3)} · ${x.label}`, valueMinor: x.valueMinor, count: 0 })) },
  ];
  if (d.topAccounts.length) blocks.push({ type: "breakdown", title: "By funding account", currency: c, kind: "account", items: d.topAccounts.map((g) => ({ key: g.key, label: g.label, valueMinor: g.valueMinor, count: g.count })) });
  if (d.topChannels.length) blocks.push({ type: "breakdown", title: "By payment channel", currency: c, kind: "channel", items: d.topChannels.map((g) => ({ key: g.key, label: g.label, valueMinor: g.valueMinor, count: g.count })) });
  // Evidence: every transaction behind the total (so "N transactions" opens exactly N that add up to the figure).
  if (d.transactions.length) blocks.push({ type: "transactions", title: d.transactions.length === d.count ? "This week's transactions" : `Latest ${d.transactions.length} of ${d.count} transactions`, items: d.transactions, more: Math.max(0, d.count - d.transactions.length) });
  return withNotes({ status: "answered", text: s.join(" "), insight: more.join(" "), blocks, followUps: ["What unusual spending happened this week?", "Compare with last week", "Which merchants?"], transactionIds: d.largestTransaction ? [d.largestTransaction.id] : [] }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------

function finding(f: UnusualFinding, c: string): { title: string; detail: string } {
  switch (f.kind) {
    case "total_above_average": return { title: "Spending is higher than your usual pattern", detail: `${money(f.periodMinor, c)} vs about ${money(f.expectedMinor, c)} expected from your previous weeks${pct(f.pctChange)}.` };
    case "category_spike": return { title: `${f.category} is higher than usual`, detail: `${money(f.periodMinor, c)} vs about ${money(f.expectedMinor, c)} normally for this many days (${signed(f.diffMinor, c)}).` };
    case "large_transaction": return { title: `Larger than usual: ${money(f.transaction.amountMinor, f.transaction.currency)} at ${f.transaction.merchant}`, detail: `Your typical ${f.transaction.category} transaction is about ${money(f.categoryMedianMinor, c)}. ${onDay(f.transaction)}.` };
    case "new_merchant": return { title: `First time at ${f.transaction.merchant}`, detail: `${money(f.transaction.amountMinor, f.transaction.currency)} on ${onDay(f.transaction)}.` };
  }
}

export function composeUnusual(d: UnusualData, h: ComposeHints): Composed {
  const c = d.currency;
  if (!d.enoughHistory)
    return withNotes({
      status: "answered",
      text: `I don't have enough history yet to know what's normal for you — I need at least a few weeks of spending before ${d.period.label}. So far in this period you've spent ${money(d.periodMinor, c)} across ${plural(d.periodCount, "transaction")}.`,
      blocks: [], followUps: ["Give me my weekly summary"],
    }, h.notes);
  if (d.findings.length === 0)
    return withNotes({ status: "answered", text: `Nothing stands out in ${d.period.label}. Your ${c} spending (${money(d.periodMinor, c)}) is in line with your previous weeks.`, blocks: [], followUps: ["Give me my weekly summary"] }, h.notes);
  const items = d.findings.map((f) => finding(f, c));
  const cards = d.findings.flatMap((f) => ("transaction" in f ? [f.transaction] : []));
  const blocks: AnswerBlock[] = [{ type: "findings", title: "Worth reviewing", items }];
  if (cards.length) blocks.push({ type: "transactions", title: "Transactions", items: cards });
  return withNotes({
    status: "answered",
    text: `I noticed ${plural(d.findings.length, "thing")} worth reviewing in ${d.period.label}, compared with your own previous weeks: ${items.map((i) => i.title.charAt(0).toLowerCase() + i.title.slice(1)).join("; ")}.`,
    blocks, followUps: ["Why?", "Give me my weekly summary"], transactionIds: cards.map((x) => x.id),
  }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------

export function composeTransaction(d: TransactionDetail, h: ComposeHints): Composed {
  const t = d.transaction;
  const category = t.recordedCategory ? `${t.recordedCategory} (your rule counts it as ${t.category})` : t.category;
  const s = [`${money(t.amountMinor, t.currency)} at ${t.merchant} on ${onDay(t)}. Category: ${category}. Funding account: ${t.fundingAccount}. Payment channel: ${channelInfo(t.paymentChannel).label}.`];
  if (d.split.isShared) s.push(`It was split between ${d.split.people} people; your share was ${money(d.split.myShareMinor, t.currency)}${d.split.paidByMe ? "" : `, and ${d.split.payer ?? "someone else"} paid`}.`);
  else if (!d.split.paidByMe) s.push(`${d.split.payer ?? "Someone else"} paid for it.`);
  if (d.reference) s.push(`Reference: ${d.reference}.`);
  if (d.notes) s.push(`Your note: “${d.notes}”.`);
  s.push(d.receipt.available ? "A receipt image is attached — open the transaction to see it. I can't read its items, so I can't confirm exactly what was bought." : "There's no receipt attached.");
  return withNotes({ status: "answered", confidence: "HIGH", text: s.join(" "), blocks: [{ type: "transactions", title: "Transaction", items: [t] }], followUps: [`How much did I spend at ${t.merchant} this month?`], transactionIds: [t.id] }, h.notes);
}

// ---------------------------------------------------------------------------------------------------------------
// Personal insights ("why am I spending so much lately?")

const unitWord = (d: InsightsData) => (d.unit === "week" ? "week" : "month");

export function composeInsights(d: InsightsData, hints: ComposeHints): Composed {
  const h = { ...hints, notes: [...(hints.notes ?? []), ...ruleNote(d.personalRules)] };
  const c = d.currency;
  const so = `this ${unitWord(d)} so far (${d.period.label})`;
  const subject = d.filters !== "All spending" ? ` (${d.filters})` : "";
  const lang = h.lang ?? "en";
  const soL = periodText(lang, d.period, `this ${unitWord(d)}`);
  if (!d.enoughHistory || d.normalMinor === null || d.diffMinor === null)
    return withNotes({
      status: "answered",
      text: say.insight(lang, { kind: "unknown", current: money(d.currentMinor, c), period: soL, count: d.currentCount }) ?? `I don't have enough history yet to know your normal ${unitWord(d)} — I need records from at least two earlier ${unitWord(d)}s. So far this ${unitWord(d)} (${d.period.label}) you've spent ${money(d.currentMinor, c)}${subject} across ${plural(d.currentCount, "transaction")}.`,
      blocks: [], followUps: ["Give me my weekly summary"],
    }, h.notes);

  const blocks: AnswerBlock[] = [{
    type: "comparison", currency: c, a: { label: `This ${unitWord(d)} so far`, valueMinor: d.currentMinor, count: d.currentCount },
    b: { label: `Your normal (avg of ${d.periodsUsed} ${unitWord(d)}s)`, valueMinor: d.normalMinor, count: 0 }, diffMinor: d.diffMinor, pct: d.pctChange,
  }];
  const ups = d.categoryChanges.filter((x) => x.diffMinor > 0);
  const downs = d.categoryChanges.filter((x) => x.diffMinor < 0);
  if (d.categoryChanges.length) blocks.push({ type: "breakdown", title: "Biggest changes vs your normal", currency: c, kind: "category", items: d.categoryChanges.map((x) => ({ key: x.key, label: x.label, valueMinor: x.currentMinor, count: 0, diffMinor: x.diffMinor })) });
  if (d.largePurchases.length) blocks.push({ type: "transactions", title: "Larger than usual", items: d.largePurchases });

  let text: string;
  if (d.significant && d.diffMinor > 0) {
    text = `You've spent ${money(d.diffMinor, c)} more${subject} ${so} than your normal for the same days (${money(d.normalMinor, c)}, ${d.normalLabel})${d.pctChange !== null ? ` — up ${d.pctChange}%` : ""}.`;
    if (ups.length) text += ` The biggest increases: ${ups.slice(0, 3).map((x) => `${x.label} ${signed(x.diffMinor, c)}`).join(", ")}.`;
  } else if (d.significant && d.diffMinor < 0) {
    text = `You've spent ${money(-d.diffMinor, c)} less${subject} ${so} than your normal for the same days (${money(d.normalMinor, c)}), down ${Math.abs(d.pctChange ?? 0)}%.`;
  } else {
    text = `Your spending${subject} ${so} is ${money(d.currentMinor, c)} — in line with your normal for the same days (${money(d.normalMinor, c)}, ${d.normalLabel}).`;
  }

  text = say.insight(lang, {
    kind: !d.significant ? "same" : d.diffMinor > 0 ? "more" : "less", diff: money(Math.abs(d.diffMinor), c), current: money(d.currentMinor, c),
    normal: money(d.normalMinor, c), period: soL, count: d.currentCount, pct: d.pctChange,
  }) ?? text;

  const extra: string[] = [];
  if (!(d.significant && d.diffMinor > 0) && ups.length) extra.push(`${ups[0].label} is higher than usual (${signed(ups[0].diffMinor, c)}).`);
  if (d.significant && d.diffMinor > 0 && downs.length) extra.push(`${downs[0].label} is lower than usual (${signed(downs[0].diffMinor, c)}).`);
  const merchantUp = d.merchantChanges.find((x) => x.diffMinor > 0);
  if (merchantUp) extra.push(`At ${merchantUp.label} you've spent ${money(merchantUp.currentMinor, c)}, ${money(merchantUp.diffMinor, c)} more than usual.`);
  if (d.largePurchases.length) extra.push(`You made ${plural(d.largePurchases.length, "larger-than-usual purchase")}${d.largePurchases.length === 1 ? `: ${money(d.largePurchases[0].amountMinor, d.largePurchases[0].currency)} at ${d.largePurchases[0].merchant}` : ""}.`);
  for (const s of d.smallAddUps) extra.push(`${s.count} small payments at ${s.label} add up to ${money(s.totalMinor, c)}.`);
  if (d.weekend) extra.push(`Over the last ${d.weekend.weeks} weeks you spent about ${money(d.weekend.weekendDayMinor, c)} per weekend day vs ${money(d.weekend.weekdayDayMinor, c)} per weekday.`);

  const suggestion = d.significant && d.diffMinor > 0 && ups.length
    ? `If you're trying to reduce spending, ${ups[0].label} is the category I'd review first — it contributed the most to the increase.`
    : undefined;
  return withNotes({
    status: "answered", text, blocks, insight: extra.length ? extra.join(" ") : undefined, suggestion,
    followUps: ups.length ? [`Show my ${ups[0].label} transactions this ${unitWord(d)}`, "Compare with last month"] : ["Give me my weekly summary"],
    transactionIds: d.largePurchases.map((x) => x.id),
  }, h.notes);
}

/** One-line insight for a total ("That's RM96 more than your usual week for Food"), only when it's meaningful. */
export function totalInsight(d: InsightsData): string | undefined {
  if (!d.significant || d.diffMinor === null || d.normalMinor === null) return undefined;
  const subject = d.filters !== "All spending" ? ` for ${d.filters}` : "";
  return `That's ${money(Math.abs(d.diffMinor), d.currency)} ${d.diffMinor > 0 ? "more" : "less"} than your usual ${unitWord(d)} so far${subject} (${money(d.normalMinor, d.currency)}, ${d.normalLabel}).`;
}

/** "I noticed…" cards for the Ask screen: only meaningful, data-backed changes (none is a valid answer). */
export function proactiveNotices(d: InsightsData): { title: string; detail: string; ask: string }[] {
  if (!d.enoughHistory || d.normalMinor === null || d.diffMinor === null) return [];
  const c = d.currency;
  const out: { title: string; detail: string; ask: string }[] = [];
  const u = unitWord(d);
  if (d.significant)
    out.push({
      title: `You've spent ${d.diffMinor > 0 ? "more" : "less"} than usual this ${u}`,
      detail: `${money(d.currentMinor, c)} so far vs ${money(d.normalMinor, c)} normally for these days${d.pctChange !== null ? ` (${d.pctChange > 0 ? "+" : "−"}${Math.abs(d.pctChange)}%)` : ""}.`,
      ask: d.unit === "week" ? "How am I doing this week?" : "Why am I spending so much lately?",
    });
  const up = d.categoryChanges.find((x) => x.diffMinor > 0);
  if (up) out.push({ title: `${up.label} is higher than usual`, detail: `${money(up.currentMinor, c)} this ${u} so far vs about ${money(up.normalMinor, c)} normally (${signed(up.diffMinor, c)}).`, ask: `How much did I spend on ${up.label} this ${u}?` });
  return out.slice(0, 2);
}

/** Compose by tool name (used for the evidence blocks of model answers too). */
export function composeTool(tool: string, result: ToolResult, h: ComposeHints, detail?: TransactionDetail): Composed {
  if (!result.ok) return failure(result);
  switch (tool) {
    case "search_transactions": return composeSearch(result.data as SearchData, h, detail);
    case "calculate_spending": return composeCalculate(result.data as CalculateData, h);
    case "compare_periods": return composeCompare(result.data as CompareData, h);
    case "get_weekly_summary": return composeWeekly(result.data as WeeklySummaryData, h);
    case "find_unusual_spending": return composeUnusual(result.data as UnusualData, h);
    case "get_transaction": return composeTransaction(result.data as TransactionDetail, h);
    case "get_spending_insights": return composeInsights(result.data as InsightsData, h);
    default: return { status: "error", text: "I couldn't answer that.", blocks: [], followUps: [] };
  }
}

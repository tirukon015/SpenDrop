// The SpenDrop AI financial tools. Read-only, deterministic and user-scoped: each one receives the authenticated
// AiContext (never a user id from its input) and a repository already bound to that user. All money maths happens
// here in integer minor units with the same spending rule as the rest of the app (lib/domain/ledger.ts:
// full amount if I paid, my share if someone else paid). Currencies are never added together.
import { channelInfo } from "@/lib/domain/constants";
import { sharesByExpense, spendingMinor } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";
import type { CategoryId, Expense, ExpenseShare, PaymentChannelId } from "@/lib/domain/types";
import { averageMinor, maxBy, medianMinor, minBy, percentChange, roundHalfAway, scaleMinor, sharePercent, totalMinor } from "./calc";
import { AI_LIMITS, UNUSUAL } from "./config";
import { candidatesFor, decide, withSpellings } from "./merchant-resolver";
import { TooMuchDataError, type FinanceRepository, type PersonalRule } from "./repository";
import type { FiltersInput, PeriodInput } from "./schemas";
import {
  addDays, daysBetween, elapsedSpan, formatSpan, localDateOf, presetSpan, previousComparable, spanDays, spanInstants, startOfWeek,
  weekdayIndex, type DateSpan, type LocalDate,
} from "./time";
import type { AiContext, Confidence, Evidence, PeriodInfo, ToolResult, TxnCard } from "./types";

// ---------------------------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------------------------

export const normalizeText = (s: string) => s.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
/** "MYR" and "RM" are the same currency in SpenDrop (stored as "RM"). */
export const currencyKey = (c: string) => { const u = c.trim().toUpperCase(); return u === "MYR" ? "RM" : u; };
/** Major units → minor units without float drift (1.005 → 101, 10.5 → 1050). */
export const toMinor = (major: number) => roundHalfAway(Number((major * 100).toPrecision(12)));
/** Percentage change rounded to one decimal, or null when there is nothing to compare with. */
/** Percentage change — defined once, in calc.ts. */
export const pctChange = percentChange;

export class ToolInputError extends Error {}

export function resolvePeriod(period: PeriodInput | undefined, today: LocalDate): DateSpan | null {
  if (!period) return null;
  const span = "preset" in period ? presetSpan(period.preset, today) : { from: period.from, to: period.to };
  if (span && spanDays(span) > AI_LIMITS.maxSpanDays) throw new ToolInputError("That period is too long. Please ask about at most three years at a time.");
  return span;
}

export const periodInfo = (span: DateSpan | null): PeriodInfo | null => (span ? { ...span, label: formatSpan(span) } : null);

/** Human description of the filters ("Food · Maybank · Apple Pay · RM 10.00–RM 20.00"). */
export function describeFilters(f: Omit<FiltersInput, "period">): string {
  const parts: string[] = [];
  if (f.category) parts.push(f.category);
  if (f.merchants?.length) parts.push(f.merchants.length === 1 ? f.merchants[0] : `${f.merchants.length} merchants like “${f.merchants[0]}”`);
  else if (f.merchant) parts.push(`merchant “${f.merchant}”`);
  if (f.fundingAccount) parts.push(`from ${f.fundingAccount}`);
  if (f.paymentChannel) parts.push(`via ${channelInfo(f.paymentChannel).label}`);
  if (f.paymentChannels) parts.push(`via ${f.paymentChannels.map((c) => channelInfo(c).label).join(" / ")}`);
  const cur = f.currency ? currencyKey(f.currency) : "RM";
  const amounts = f.amountMin !== undefined || f.amountMax !== undefined;
  if (f.amountMin !== undefined && f.amountMax !== undefined) parts.push(`${formatMoney(toMinor(f.amountMin), cur)}–${formatMoney(toMinor(f.amountMax), cur)}`);
  else if (f.amountMin !== undefined) parts.push(`from ${formatMoney(toMinor(f.amountMin), cur)}`);
  else if (f.amountMax !== undefined) parts.push(`up to ${formatMoney(toMinor(f.amountMax), cur)}`);
  if (f.currency && !amounts) parts.push(currencyKey(f.currency));
  if (f.keyword) parts.push(`“${f.keyword}”`);
  if (f.remark) parts.push(`remarks: “${f.remark}”`);
  if (f.hasReceipt !== undefined) parts.push(f.hasReceipt ? "with receipt" : "without receipt");
  return parts.join(" · ") || "All spending";
}

/** Words for a sentence: " on Food at Starbucks from Maybank using Apple Pay" (empty for all spending). */
export function describeSubject(f: Omit<FiltersInput, "period">): string {
  const parts: string[] = [];
  if (f.category) parts.push(`on ${f.category}`);
  if (f.merchants?.length) parts.push(`at ${f.merchants.length <= 3 ? f.merchants.join(" or ") : `${f.merchants.slice(0, 3).join(", ")} and ${f.merchants.length - 3} similar names`}`);
  else if (f.merchant) parts.push(`at ${f.merchant}`);
  if (f.fundingAccount) parts.push(`from ${f.fundingAccount}`);
  if (f.paymentChannel) parts.push(`using ${channelInfo(f.paymentChannel).label}`);
  if (f.paymentChannels) parts.push(`using ${f.paymentChannels.length === 3 && f.paymentChannels.includes("QR_PAYMENT") ? "QR" : f.paymentChannels.map((c) => channelInfo(c).label).join(" or ")}`);
  if (f.currency && f.amountMin === undefined && f.amountMax === undefined) parts.push(`in ${currencyKey(f.currency)}`);
  if (f.keyword) parts.push(`mentioning “${f.keyword}”`);
  if (f.remark) parts.push(`whose remarks mention “${f.remark}”`);
  if (f.hasReceipt !== undefined) parts.push(f.hasReceipt ? "with a receipt" : "without a receipt");
  return parts.length ? ` ${parts.join(" ")}` : "";
}

function searchSubject(input: SearchInput, target: number | null) {
  const hasAmount = input.amountMin !== undefined || input.amountMax !== undefined;
  const base = describeSubject({ ...input, amountMin: undefined, amountMax: undefined, currency: hasAmount ? undefined : input.currency });
  if (target !== null || !hasAmount) return base;
  const cur = input.currency ? currencyKey(input.currency) : "RM";
  const lo = input.amountMin ?? 0, hi = input.amountMax;
  const range = hi === undefined || hi >= 1_000_000_000 ? ` over ${formatMoney(toMinor(lo), cur)}` : lo === 0 ? ` under ${formatMoney(toMinor(hi), cur)}` : ` between ${formatMoney(toMinor(lo), cur)} and ${formatMoney(toMinor(hi), cur)}`;
  return base + range;
}

export const evidence = (tool: string, count: number, span: DateSpan | null, filters: string): Evidence => ({
  tool, transactionCount: count, period: formatSpan(span), filters, generatedAt: new Date().toISOString(),
});

/**
 * One expense as the tools see it. `category` is the user's EFFECTIVE category: their own personal rule ("Grab is
 * Transport for me") wins over the stored category for grouping and filtering. The stored record is never changed.
 */
export interface Row { expense: Expense; shares: ExpenseShare[] | undefined; spend: number; localDate: LocalDate; category: CategoryId; rule?: PersonalRule }

/** Personal rules that changed a category in this result (always disclosed in the answer). */
export interface AppliedRule { merchant: string; category: CategoryId; count: number }

export const merchantNames = (rows: Row[]) => [...new Map(rows.map((r) => [normalizeText(r.expense.merchant), r.expense.merchant.trim()])).values()].sort();

export function appliedRules(rows: Row[]): AppliedRule[] {
  const map = new Map<string, AppliedRule>();
  for (const r of rows) {
    if (!r.rule) continue;
    const g = map.get(r.rule.merchantKey) ?? { merchant: r.rule.merchant, category: r.rule.category, count: 0 };
    g.count += 1;
    map.set(r.rule.merchantKey, g);
  }
  return [...map.values()];
}

/** The rule for a merchant, if the user made one (whole-word match on the normalised name). */
export function ruleFor(merchant: string, rules: PersonalRule[]): PersonalRule | undefined {
  const name = ` ${normalizeText(merchant)} `;
  return rules.filter((r) => name.includes(` ${r.merchantKey} `)).sort((a, b) => b.merchantKey.length - a.merchantKey.length)[0];
}

export function toCard(r: Row, ctx: AiContext): TxnCard {
  const e = r.expense;
  const time = new Intl.DateTimeFormat("en-MY", { timeZone: ctx.timeZone, hour: "numeric", minute: "2-digit" }).format(new Date(e.date));
  return {
    id: e.id, merchant: e.merchant || "Unknown", amountMinor: e.amountMinor, spendMinor: r.spend, currency: currencyKey(e.currency),
    date: e.date, localDate: r.localDate, localTime: time, category: r.category, ...(r.category !== e.category ? { recordedCategory: e.category } : {}), fundingAccount: e.fundingAccount || "Unknown",
    paymentChannel: e.paymentChannel, hasReceipt: Boolean(e.receiptPath), isShared: (r.shares?.length ?? 0) > 0, source: e.sourceType || "manual",
    // The user's own remark: context only, shown as the user's words — never a source of amounts or other facts.
    ...(e.notes?.trim() ? { remark: e.notes.trim().slice(0, 140) } : {}),
  };
}

// Remarks / keywords -------------------------------------------------------------------------------------------
const KEYWORD_STOP = new Set(("a an the my our your his her their with and or of for to on in at by from about related relating regarding " +
  "mention mentions mentioning mentioned stuff things thing expense expenses transaction transactions payment payments spending spent").split(" "));
/** Light plural stemming so "lunches" finds "lunch" and "friends" finds "friend". */
export const stem = (w: string) =>
  w.length > 4 && w.endsWith("ies") ? `${w.slice(0, -3)}y` : w.length > 4 && /(ches|shes|sses|xes)$/.test(w) ? w.slice(0, -2) : w.length > 3 && w.endsWith("s") && !w.endsWith("ss") ? w.slice(0, -1) : w;
/** The meaningful words of a keyword / remark search ("lunches with friends" → lunch, friend). */
export const keywordTerms = (k: string) => normalizeText(k).split(" ").filter((w) => w.length >= 2 && !KEYWORD_STOP.has(w)).map(stem);
/** Every term appears (as a word, or the start of one) in the merchant, remark or reference. */
export function mentions(texts: (string | null | undefined)[], terms: string[]): boolean {
  if (!terms.length) return false;
  const words = texts.flatMap((t) => normalizeText(t ?? "").split(" ")).filter(Boolean).map(stem);
  return terms.every((t) => words.some((w) => w === t || (t.length >= 4 && w.startsWith(t)) || (w.length >= 4 && t.startsWith(w))));
}

export async function loadRows(repo: FinanceRepository, ctx: AiContext, span: DateSpan | null): Promise<Row[]> {
  const range = span ? spanInstants(span, ctx.timeZone) : { start: null, end: null };
  const [set, rules] = await Promise.all([repo.expenses(range, AI_LIMITS.maxRowsPerTool), repo.personalRules()]);
  const shares = sharesByExpense(set.shares);
  return set.expenses.map((expense) => {
    const rule = ruleFor(expense.merchant, rules);
    const changes = rule && rule.category !== expense.category;
    return {
      expense, shares: shares.get(expense.id), spend: spendingMinor(expense, shares.get(expense.id)), localDate: localDateOf(expense.date, ctx.timeZone),
      category: changes ? rule.category : expense.category, ...(changes ? { rule } : {}),
    };
  });
}

function accountMatches(e: Expense, wanted: string, accountNames: Map<string, string>) {
  const w = normalizeText(wanted);
  const names = [e.fundingAccount, e.accountId ? accountNames.get(e.accountId) : undefined];
  return names.some((n) => n && (normalizeText(n) === w || ` ${normalizeText(n)} `.includes(` ${w} `)));
}

/**
 * Which of these rows' merchant names a merchant filter means (normalised), or null for no merchant filter.
 * Exact names (`merchants`) are used as given. A `merchant` reference first matches whole words ("Shopee" → Shopee,
 * Shopee Food; never ShopeePay); if that finds nothing, the merchant resolver matches partial names and small typos
 * ("bijoy" → BIJOYSHARIARALAMIN) among the user's own merchants. Answers disclose the names that matched.
 */
export function merchantSet(rows: Row[], f: Pick<FiltersInput, "merchant" | "merchants">): Set<string> | null {
  const names = [...new Set(rows.map((r) => r.expense.merchant))];
  if (f.merchants?.length) return new Set(withSpellings(f.merchants, names).map(normalizeText));
  if (!f.merchant) return null;
  const wanted = normalizeText(f.merchant);
  const whole = names.filter((n) => ` ${normalizeText(n)} `.includes(` ${wanted} `));
  if (whole.length) return new Set(withSpellings(whole, names).map(normalizeText));
  const resolved = decide(f.merchant, candidatesFor(f.merchant, names), true);
  return new Set((resolved?.names ?? []).map(normalizeText));
}

/**
 * The merchant reference when it matches none of the user's merchants at all (in any period) — so an empty answer can
 * say "I couldn't find a merchant matching …" instead of a bare "no records". Only checked when nothing matched.
 */
async function unknownMerchant(f: Pick<FiltersInput, "merchant" | "merchants">, repo: FinanceRepository): Promise<string | undefined> {
  if (!f.merchant || f.merchants?.length) return undefined;
  const all = (await repo.vocabulary()).merchants;
  const wanted = normalizeText(f.merchant);
  if (all.some((n) => ` ${normalizeText(n)} `.includes(` ${wanted} `)) || candidatesFor(f.merchant, all).length) return undefined;
  return f.merchant;
}

/**
 * A name that is no merchant of the user's but appears in their remarks ("university", "birthday", "Ahmed") is
 * searched in the remarks instead — and the answer says so. Returns the input to use and what happened.
 */
async function withRemarkFallback<T extends Pick<FiltersInput, "merchant" | "merchants" | "keyword">>(input: T, repo: FinanceRepository): Promise<{ input: T; remarks?: string }> {
  if (!input.merchant || input.merchants?.length || input.keyword || !(await unknownMerchant(input, repo))) return { input };
  return { input: { ...input, merchant: undefined, keyword: input.merchant }, remarks: input.merchant };
}

export function applyFilters(rows: Row[], f: Omit<FiltersInput, "period">, accountNames: Map<string, string>): Row[] {
  const merchants = merchantSet(rows, f);
  const terms = f.keyword ? keywordTerms(f.keyword) : null;
  const remarkTerms = f.remark ? keywordTerms(f.remark) : null;
  const minMinor = f.amountMin !== undefined ? toMinor(f.amountMin) : null;
  const maxMinor = f.amountMax !== undefined ? toMinor(f.amountMax) : null;
  const currency = f.currency ? currencyKey(f.currency) : null;
  return rows.filter(({ expense: e, category }) => {
    if (f.category && category !== f.category) return false;
    if (f.paymentChannel && e.paymentChannel !== f.paymentChannel) return false;
    if (f.paymentChannels && !f.paymentChannels.includes(e.paymentChannel)) return false;
    if (currency && currencyKey(e.currency) !== currency) return false;
    if (minMinor !== null && e.amountMinor < minMinor) return false;
    if (maxMinor !== null && e.amountMinor > maxMinor) return false;
    if (f.hasReceipt !== undefined && Boolean(e.receiptPath) !== f.hasReceipt) return false;
    // Whole words: "Shopee" matches "Shopee" and "Shopee Food", never "ShopeePay" (answers list which names matched).
    if (merchants && !merchants.has(normalizeText(e.merchant))) return false;
    if (terms && !mentions([e.merchant, e.notes, e.transactionReference], terms)) return false;
    if (remarkTerms && !mentions([e.notes], remarkTerms)) return false;
    if (f.fundingAccount && !accountMatches(e, f.fundingAccount, accountNames)) return false;
    return true;
  });
}

export async function accountNameMap(repo: FinanceRepository) {
  return new Map((await repo.accounts()).map((a) => [a.id, a.name]));
}

export function byCurrency(rows: Row[]) {
  const map = new Map<string, Row[]>();
  for (const r of rows) {
    const c = currencyKey(r.expense.currency);
    map.set(c, [...(map.get(c) ?? []), r]);
  }
  // Largest spending first; RM first on ties.
  return [...map.entries()].sort((a, b) => sum(b[1]) - sum(a[1]) || (a[0] === "RM" ? -1 : 1));
}

/** Spending total of rows (exact, integer sen) — via calc.ts. */
export const sum = (rows: Row[]) => totalMinor(rows.map((r) => r.spend));

export type GroupKey = "category" | "merchant" | "funding_account" | "payment_channel" | "channel_family" | "day";

/** Payment channels grouped the way people talk about them ("QR" = QR Payment, DuitNow QR, Touch 'n Go QR). */
export const CHANNEL_FAMILY: Record<PaymentChannelId, string> = {
  CARD: "Card", APPLE_PAY: "Apple Pay", QR_PAYMENT: "QR", DUITNOW_QR: "QR", TNG_QR: "QR", BANK_TRANSFER: "Bank transfer",
  ONLINE_BANKING: "Bank transfer", E_WALLET: "E-wallet", CASH: "Cash", OTHER: "Other", UNKNOWN: "Not recorded",
};
export interface GroupRow { key: string; label: string; valueMinor: number; count: number; sharePct: number }

function groupKeyOf(r: Row, by: GroupKey, accountNames: Map<string, string>): [string, string] {
  const e = r.expense;
  switch (by) {
    case "category": return [r.category, r.category];
    case "merchant": return [normalizeText(e.merchant) || "unknown", e.merchant.trim() || "Unknown"];
    case "funding_account": {
      const name = (e.fundingAccount && e.fundingAccount !== "Unknown" ? e.fundingAccount : e.accountId ? accountNames.get(e.accountId) : null) ?? null;
      return name ? [normalizeText(name), name] : ["unknown", "Account not recorded"];
    }
    case "payment_channel": return [e.paymentChannel, channelInfo(e.paymentChannel).label];
    case "channel_family": return [CHANNEL_FAMILY[e.paymentChannel], CHANNEL_FAMILY[e.paymentChannel]];
    case "day": return [r.localDate, formatSpan({ from: r.localDate, to: r.localDate })];
  }
}

export function groupRows(rows: Row[], by: GroupKey, accountNames: Map<string, string>): GroupRow[] {
  const total = sum(rows);
  const map = new Map<string, GroupRow>();
  for (const r of rows) {
    const [key, label] = groupKeyOf(r, by, accountNames);
    const g = map.get(key) ?? { key, label, valueMinor: 0, count: 0, sharePct: 0 };
    g.valueMinor += r.spend;
    g.count += 1;
    map.set(key, g);
  }
  return [...map.values()]
    .map((g) => ({ ...g, sharePct: sharePercent(g.valueMinor, total) }))
    .sort((a, b) => (by === "day" ? a.key.localeCompare(b.key) : b.valueMinor - a.valueMinor || b.count - a.count));
}

export const run = async <T>(fn: () => Promise<ToolResult<T>>): Promise<ToolResult<T>> => {
  try {
    return await fn();
  } catch (error) {
    if (error instanceof ToolInputError) return { ok: false, error: { kind: "validation", message: error.message } };
    if (error instanceof TooMuchDataError)
      return { ok: false, error: { kind: "too_large", message: "That covers too many transactions to answer at once. Try a shorter period." } };
    throw error;
  }
};

// ---------------------------------------------------------------------------------------------------------------
// search_transactions
// ---------------------------------------------------------------------------------------------------------------
export interface SearchInput extends FiltersInput {
  targetAmount?: number; targetDate?: LocalDate; sort?: "relevance" | "date_desc" | "date_asc" | "amount_desc" | "amount_asc"; limit?: number; offset?: number;
}
export interface SearchData {
  period: PeriodInfo | null;
  filters: string;
  subject: string;
  /** The remembered amount / day, for lookups. */
  target: { amountMinor: number | null; date: LocalDate | null };
  total: number;
  offset: number;
  transactions: (TxnCard & { matchReason?: string })[];
  confidence: Confidence | null;
  personalRules: AppliedRule[];
  /** Distinct merchant names a merchant filter matched (disclosed when more than one). */
  merchantsMatched: string[];
  /** Set when the merchant named matches none of the user's merchants at all. */
  unknownMerchant?: string;
  /** Set when a name matched no merchant and the user's remarks were searched for it instead. */
  searchedRemarks?: string;
}

export async function searchTransactions(original: SearchInput, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<SearchData>> {
  return run(async () => {
    const span = resolvePeriod(original.period, ctx.today);
    const [names, all, fallback] = await Promise.all([accountNameMap(repo), loadRows(repo, ctx, span), withRemarkFallback(original, repo)]);
    const input = fallback.input;
    let rows = applyFilters(all, input, names);
    const target = input.targetAmount !== undefined ? toMinor(input.targetAmount) : null;
    // A precise amount (with cents, "RM54.49") identifies a transaction: an exact match wins over nearby amounts.
    // Round amounts ("RM15") stay approximate — people round them.
    if (target !== null && target % 100 !== 0) {
      const exact = rows.filter((r) => r.expense.amountMinor === target || r.spend === target);
      if (exact.length) rows = exact;
    }
    const sort = input.sort ?? (target !== null || input.targetDate ? "relevance" : "date_desc");
    const score = (r: Row) => {
      let s = 0;
      if (target !== null) s += Math.abs(r.expense.amountMinor - target) / Math.max(100, target * 0.1);
      if (input.targetDate) s += Math.abs(daysBetween(input.targetDate, r.localDate)) / 2;
      return s;
    };
    const sorted = [...rows].sort((a, b) => {
      switch (sort) {
        case "relevance": return score(a) - score(b) || b.expense.date.localeCompare(a.expense.date);
        case "date_asc": return a.expense.date.localeCompare(b.expense.date);
        case "amount_desc": return b.expense.amountMinor - a.expense.amountMinor || b.expense.date.localeCompare(a.expense.date);
        case "amount_asc": return a.expense.amountMinor - b.expense.amountMinor || b.expense.date.localeCompare(a.expense.date);
        default: return b.expense.date.localeCompare(a.expense.date);
      }
    });
    const offset = input.offset ?? 0;
    const page = sorted.slice(offset, offset + (input.limit ?? AI_LIMITS.searchDefaultLimit));
    const transactions = page.map((r) => {
      const card = toCard(r, ctx);
      if (target === null) return card;
      const diff = r.expense.amountMinor - target;
      return { ...card, matchReason: diff === 0 ? "exact amount" : `${formatMoney(Math.abs(diff), card.currency)} ${diff > 0 ? "more" : "less"} than ${formatMoney(target, card.currency)}` };
    });
    const isLookup = target !== null || Boolean(input.targetDate);
    const confidence: Confidence | null = rows.length === 0 ? "NO_MATCH" : !isLookup ? null : rows.length === 1 ? "HIGH" : rows.length <= 5 ? "MEDIUM" : "LOW";
    const filters = describeFilters(input);
    const data: SearchData = {
      period: periodInfo(span), filters, subject: searchSubject(input, target), target: { amountMinor: target, date: input.targetDate ?? null },
      total: rows.length, offset, transactions, confidence, personalRules: appliedRules(rows), merchantsMatched: input.merchant || input.merchants ? merchantNames(rows) : [], unknownMerchant: rows.length ? undefined : fallback.remarks ?? await unknownMerchant(input, repo), ...(fallback.remarks && rows.length ? { searchedRemarks: fallback.remarks } : {}),
    };
    return { ok: true, data, evidence: evidence("search_transactions", rows.length, span, filters) };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// calculate_spending
// ---------------------------------------------------------------------------------------------------------------
export interface CalculateInput extends FiltersInput { operation: "sum" | "count" | "average" | "min" | "max"; groupBy?: GroupKey | "none" }
export interface CurrencyCalc {
  currency: string; transactionCount: number; valueMinor: number | null; transaction?: TxnCard;
  groups?: GroupRow[];
  /** True when `groups` lists every group (nothing cut off), so they must add up to the total. */
  groupsComplete?: boolean;
  /** For counts: on how many different days those transactions happened (frequency answers). */
  distinctDays?: number;
  /** The transactions behind the figure (most recent first, up to EVIDENCE_ROWS) — the evidence the user can open. */
  transactions?: TxnCard[];
}

/** How many transactions an answer carries as evidence. */
export const EVIDENCE_ROWS = 100;
export interface CalculateData {
  operation: CalculateInput["operation"];
  groupBy: GroupKey | "none";
  period: PeriodInfo | null;
  filters: string;
  subject: string;
  results: CurrencyCalc[];
  refunds: { currency: string; totalMinor: number; count: number }[];
  personalRules: AppliedRule[];
  merchantsMatched: string[];
  /** Set when the merchant named matches none of the user's merchants at all. */
  unknownMerchant?: string;
  /** Set when a name matched no merchant and the user's remarks were searched for it instead. */
  searchedRemarks?: string;
}

export async function calculateSpending(original: CalculateInput, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<CalculateData>> {
  return run(async () => {
    const span = resolvePeriod(original.period, ctx.today);
    const [names, all, fallback] = await Promise.all([accountNameMap(repo), loadRows(repo, ctx, span), withRemarkFallback(original, repo)]);
    const input = fallback.input;
    const rows = applyFilters(all, input, names);
    const groupBy = input.groupBy ?? "none";
    const results: CurrencyCalc[] = byCurrency(rows).map(([currency, list]) => {
      const total = sum(list);
      const base: CurrencyCalc = { currency, transactionCount: list.length, valueMinor: null };
      switch (input.operation) {
        case "sum": base.valueMinor = total; break;
        case "count": base.valueMinor = null; base.distinctDays = new Set(list.map((r) => r.localDate)).size; break;
        case "average": base.valueMinor = averageMinor(list.map((r) => r.spend)) ?? 0; break;
        case "min": case "max": {
          // MAX / MIN over the exact filtered rows (ties: the most recent one first).
          const byDate = [...list].sort((a, b) => b.expense.date.localeCompare(a.expense.date));
          const pick = (input.operation === "max" ? maxBy(byDate, (r) => r.spend) : minBy(byDate, (r) => r.spend))!;
          base.valueMinor = pick.spend;
          base.transaction = toCard(pick, ctx);
        }
      }
      if (groupBy !== "none") {
        const all = groupRows(list, groupBy, names);
        base.groups = all.slice(0, groupBy === "day" ? 400 : 12);
        base.groupsComplete = base.groups.length === all.length;
      }
      base.transactions = [...list].sort((a, b) => b.expense.date.localeCompare(a.expense.date)).slice(0, EVIDENCE_ROWS).map((r) => toCard(r, ctx));
      return base;
    });
    // Refunds are reported next to spending (never silently netted), only when no row-level filter would make them misleading.
    const plain = !input.category && !input.merchant && !input.paymentChannel && !input.paymentChannels && !input.fundingAccount && !input.keyword && input.amountMin === undefined && input.amountMax === undefined;
    const refunds = plain ? refundTotals(await repo.refunds(span ? spanInstants(span, ctx.timeZone) : { start: null, end: null }), input.currency) : [];
    const filters = describeFilters(input);
    return { ok: true, data: { operation: input.operation, groupBy, period: periodInfo(span), filters, subject: describeSubject(input), results, refunds, personalRules: appliedRules(rows), merchantsMatched: input.merchant || input.merchants ? merchantNames(rows) : [], unknownMerchant: rows.length ? undefined : fallback.remarks ?? await unknownMerchant(input, repo), ...(fallback.remarks && rows.length ? { searchedRemarks: fallback.remarks } : {}) }, evidence: evidence("calculate_spending", rows.length, span, filters) };
  });
}

function refundTotals(list: { currency: string; amountMinor: number }[], currency?: string) {
  const map = new Map<string, { currency: string; totalMinor: number; count: number }>();
  for (const m of list) {
    const c = currencyKey(m.currency);
    if (currency && c !== currencyKey(currency)) continue;
    const g = map.get(c) ?? { currency: c, totalMinor: 0, count: 0 };
    g.totalMinor += m.amountMinor;
    g.count += 1;
    map.set(c, g);
  }
  return [...map.values()];
}

// ---------------------------------------------------------------------------------------------------------------
// compare_periods
// ---------------------------------------------------------------------------------------------------------------
export interface CompareInput {
  periodA: PeriodInput; periodB?: PeriodInput;
  merchant?: string; merchants?: string[]; category?: CategoryId; fundingAccount?: string; paymentChannel?: PaymentChannelId; paymentChannels?: PaymentChannelId[]; currency?: string;
  breakdownBy?: Exclude<GroupKey, "day">;
}
export interface CurrencyCompare {
  currency: string; aMinor: number; bMinor: number; diffMinor: number; pctChange: number | null; aCount: number; bCount: number;
  contributions: { key: string; label: string; aMinor: number; bMinor: number; diffMinor: number }[];
  largestInA: TxnCard[];
}
export interface CompareData { a: PeriodInfo; b: PeriodInfo; filters: string; subject: string; breakdownBy: Exclude<GroupKey, "day">; results: CurrencyCompare[]; personalRules: AppliedRule[] }

export async function comparePeriods(input: CompareInput, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<CompareData>> {
  return run(async () => {
    const rawA = resolvePeriod(input.periodA, ctx.today);
    if (!rawA) throw new ToolInputError("Please choose a specific period to compare (not all time).");
    // An in-progress period is compared up to today only.
    const a = elapsedSpan(rawA, ctx.today);
    const b = input.periodB ? resolvePeriod(input.periodB, ctx.today) : previousComparable(rawA, ctx.today);
    if (!b) throw new ToolInputError("Please choose a specific period to compare with (not all time).");
    const names = await accountNameMap(repo);
    const filters = { merchant: input.merchant, merchants: input.merchants, category: input.category, fundingAccount: input.fundingAccount, paymentChannel: input.paymentChannel, paymentChannels: input.paymentChannels, currency: input.currency };
    const rowsA = applyFilters(await loadRows(repo, ctx, a), filters, names);
    const rowsB = applyFilters(await loadRows(repo, ctx, b), filters, names);
    const breakdownBy = input.breakdownBy ?? (input.category ? "merchant" : "category");
    const currencies = new Set([...rowsA, ...rowsB].map((r) => currencyKey(r.expense.currency)));
    const results: CurrencyCompare[] = [...currencies].map((currency) => {
      const ca = rowsA.filter((r) => currencyKey(r.expense.currency) === currency);
      const cb = rowsB.filter((r) => currencyKey(r.expense.currency) === currency);
      const ga = new Map(groupRows(ca, breakdownBy, names).map((g) => [g.key, g]));
      const gb = new Map(groupRows(cb, breakdownBy, names).map((g) => [g.key, g]));
      const contributions = [...new Set([...ga.keys(), ...gb.keys()])].map((key) => {
        const aMinor = ga.get(key)?.valueMinor ?? 0, bMinor = gb.get(key)?.valueMinor ?? 0;
        return { key, label: ga.get(key)?.label ?? gb.get(key)?.label ?? key, aMinor, bMinor, diffMinor: aMinor - bMinor };
      }).filter((c) => c.diffMinor !== 0).sort((x, y) => Math.abs(y.diffMinor) - Math.abs(x.diffMinor)).slice(0, 8);
      const aMinor = sum(ca), bMinor = sum(cb);
      const largestInA = [...ca].sort((x, y) => y.spend - x.spend).slice(0, 3).map((r) => toCard(r, ctx));
      return { currency, aMinor, bMinor, diffMinor: aMinor - bMinor, pctChange: pctChange(aMinor, bMinor), aCount: ca.length, bCount: cb.length, contributions, largestInA };
    }).sort((x, y) => y.aMinor + y.bMinor - (x.aMinor + x.bMinor));
    const label = describeFilters(filters);
    return {
      ok: true,
      data: { a: periodInfo(a)!, b: periodInfo(b)!, filters: label, subject: describeSubject(filters), breakdownBy, results, personalRules: appliedRules([...rowsA, ...rowsB]) },
      // Both periods' transactions, and both periods named, so "Based on N" matches what is compared.
      evidence: { ...evidence("compare_periods", rowsA.length + rowsB.length, a, label), period: `${formatSpan(a)} vs ${formatSpan(b)}` },
    };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// get_transaction
// ---------------------------------------------------------------------------------------------------------------
export interface TransactionDetail {
  transaction: TxnCard;
  /** The user's own note (untrusted text: shown as data, never followed as instructions). */
  notes: string | null;
  reference: string | null;
  split: { isShared: boolean; paidByMe: boolean; payer: string | null; myShareMinor: number; people: number };
  receipt: { available: boolean; textAvailable: false };
}

export async function getTransaction(input: { transactionId: string }, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<TransactionDetail>> {
  return run(async () => {
    const set = await repo.expense(input.transactionId);
    const expense = set?.expenses[0];
    // Another user's id looks exactly like a missing one: nothing about it is revealed.
    if (!set || !expense) return { ok: false, error: { kind: "not_found", message: "No transaction with that id in your records." } };
    const shares = set.shares.filter((s) => !s.deletedAt);
    const rule = ruleFor(expense.merchant, await repo.personalRules());
    const changes = rule && rule.category !== expense.category;
    const row: Row = {
      expense, shares, spend: spendingMinor(expense, shares.length ? shares : undefined), localDate: localDateOf(expense.date, ctx.timeZone),
      category: changes ? rule.category : expense.category, ...(changes ? { rule } : {}),
    };
    const data: TransactionDetail = {
      transaction: toCard(row, ctx),
      notes: expense.notes ? expense.notes.slice(0, 300) : null,
      reference: expense.transactionReference,
      split: { isShared: shares.length > 0, paidByMe: expense.paidByMe, payer: expense.paidByMe ? null : expense.payerNameSnapshot, myShareMinor: row.spend, people: shares.length },
      receipt: { available: Boolean(expense.receiptPath), textAvailable: false },
    };
    return { ok: true, data, evidence: evidence("get_transaction", 1, { from: row.localDate, to: row.localDate }, expense.merchant) };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// get_weekly_summary
// ---------------------------------------------------------------------------------------------------------------
export interface WeeklySummaryData {
  week: PeriodInfo;
  /** Days of the week that have happened (the whole week once it is over). */
  elapsed: PeriodInfo;
  currency: string;
  totalMinor: number;
  count: number;
  otherCurrencies: { currency: string; totalMinor: number; count: number }[];
  previousWeek: { period: PeriodInfo; totalMinor: number; diffMinor: number; pctChange: number | null };
  fourWeekAverage: { weeksWithData: number; averageMinor: number | null; diffMinor: number | null; pctChange: number | null };
  categories: GroupRow[];
  largestTransaction: TxnCard | null;
  /** The week's transactions behind the total (most recent first, up to EVIDENCE_ROWS). */
  transactions: TxnCard[];
  byDay: { date: LocalDate; label: string; valueMinor: number }[];
  topMerchants: GroupRow[];
  topAccounts: GroupRow[];
  topChannels: GroupRow[];
  refunds: { currency: string; totalMinor: number; count: number }[];
}

export async function getWeeklySummary(input: { weekOf?: LocalDate }, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<WeeklySummaryData>> {
  return run(async () => {
    const start = startOfWeek(input.weekOf ?? ctx.today);
    const week: DateSpan = { from: start, to: addDays(start, 6) };
    const elapsed = elapsedSpan(week, ctx.today);
    if (elapsed.from > ctx.today) throw new ToolInputError("That week hasn't started yet.");
    const days = daysBetween(elapsed.from, elapsed.to);
    const names = await accountNameMap(repo);
    // One load covering this week and the four before it.
    const all = await loadRows(repo, ctx, { from: addDays(start, -28), to: elapsed.to });
    const inWeek = all.filter((r) => r.localDate >= elapsed.from && r.localDate <= elapsed.to);
    const groups = byCurrency(inWeek);
    const currency = groups[0]?.[0] ?? "RM";
    const rows = inWeek.filter((r) => currencyKey(r.expense.currency) === currency);
    const totalMinor = sum(rows);
    const sameDays = (weeksBack: number) => {
      const from = addDays(start, -7 * weeksBack), to = addDays(from, days);
      return all.filter((r) => currencyKey(r.expense.currency) === currency && r.localDate >= from && r.localDate <= to);
    };
    const prev = sameDays(1);
    const prevTotal = sum(prev);
    // Average of the same weekdays over the previous four weeks — only weeks since the user started recording
    // (an empty week before the first record isn't "zero spending"). At least two weeks are needed.
    const history = [1, 2, 3, 4].map(sameDays);
    const withData = history.filter((h) => h.length > 0);
    const weeksKnown = history.reduce((k, h, i) => (h.length > 0 ? i + 1 : k), 0);
    const average = weeksKnown >= 2 ? averageMinor(history.slice(0, weeksKnown).map(sum)) : null;
    const byDay: WeeklySummaryData["byDay"] = [];
    for (let d = elapsed.from; d <= elapsed.to; d = addDays(d, 1)) {
      byDay.push({ date: d, label: formatSpan({ from: d, to: d }), valueMinor: sum(rows.filter((r) => r.localDate === d)) });
    }
    const largest = maxBy([...rows].sort((a, b) => b.expense.date.localeCompare(a.expense.date)), (r) => r.spend);
    const data: WeeklySummaryData = {
      week: periodInfo(week)!, elapsed: periodInfo(elapsed)!, currency, totalMinor, count: rows.length,
      otherCurrencies: groups.slice(1).map(([c, list]) => ({ currency: c, totalMinor: sum(list), count: list.length })),
      previousWeek: { period: periodInfo({ from: addDays(start, -7), to: addDays(start, -7 + days) })!, totalMinor: prevTotal, diffMinor: totalMinor - prevTotal, pctChange: pctChange(totalMinor, prevTotal) },
      fourWeekAverage: { weeksWithData: withData.length, averageMinor: average, diffMinor: average === null ? null : totalMinor - average, pctChange: average === null ? null : pctChange(totalMinor, average) },
      categories: groupRows(rows, "category", names),
      largestTransaction: largest ? toCard(largest, ctx) : null,
      transactions: [...rows].sort((a, b) => b.expense.date.localeCompare(a.expense.date)).slice(0, EVIDENCE_ROWS).map((r) => toCard(r, ctx)),
      byDay,
      topMerchants: groupRows(rows, "merchant", names).slice(0, 5),
      topAccounts: groupRows(rows, "funding_account", names).slice(0, 5),
      topChannels: groupRows(rows, "payment_channel", names).slice(0, 5),
      refunds: refundTotals(await repo.refunds(spanInstants(elapsed, ctx.timeZone)), currency),
    };
    return { ok: true, data, evidence: evidence("get_weekly_summary", rows.length, elapsed, `${currency} spending`) };
  });
}

// ---------------------------------------------------------------------------------------------------------------
// find_unusual_spending
// ---------------------------------------------------------------------------------------------------------------
export type UnusualFinding =
  | { kind: "total_above_average"; periodMinor: number; expectedMinor: number; diffMinor: number; pctChange: number | null }
  | { kind: "category_spike"; category: CategoryId; periodMinor: number; expectedMinor: number; diffMinor: number }
  | { kind: "large_transaction"; transaction: TxnCard; categoryMedianMinor: number }
  | { kind: "new_merchant"; transaction: TxnCard };

export interface UnusualData {
  period: PeriodInfo;
  currency: string;
  enoughHistory: boolean;
  historyWeeks: number;
  periodMinor: number;
  periodCount: number;
  expectedMinor: number | null;
  findings: UnusualFinding[];
}

export const median = medianMinor;

export async function findUnusualSpending(input: { period?: PeriodInput }, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<UnusualData>> {
  return run(async () => {
    const raw = resolvePeriod(input.period ?? { preset: "this_week" }, ctx.today);
    if (!raw) throw new ToolInputError("Please choose a period to check (not all time).");
    const period = elapsedSpan(raw, ctx.today);
    const baseline: DateSpan = { from: addDays(period.from, -7 * UNUSUAL.baselineWeeks), to: addDays(period.from, -1) };
    const all = await loadRows(repo, ctx, { from: baseline.from, to: period.to });
    const currentAll = all.filter((r) => r.localDate >= period.from);
    const currency = byCurrency(currentAll)[0]?.[0] ?? "RM";
    const mine = (r: Row) => currencyKey(r.expense.currency) === currency;
    const current = currentAll.filter(mine);
    const history = all.filter((r) => r.localDate < period.from && mine(r));
    const historyWeeks = new Set(history.map((r) => startOfWeek(r.localDate))).size;
    const periodMinor = sum(current);
    const base: UnusualData = { period: periodInfo(period)!, currency, enoughHistory: false, historyWeeks, periodMinor, periodCount: current.length, expectedMinor: null, findings: [] };
    const ev = evidence("find_unusual_spending", current.length + history.length, period, `${currency} spending vs your previous ${UNUSUAL.baselineWeeks} weeks`);
    if (historyWeeks < UNUSUAL.minHistoryWeeks) return { ok: true, data: base, evidence: ev };

    // Baseline: the user's own average per day over the weeks that have data, scaled to the period length.
    const firstHistoryDay = history.reduce((m, r) => (r.localDate < m ? r.localDate : m), baseline.to);
    const baselineDays = Math.max(1, daysBetween(startOfWeek(firstHistoryDay), baseline.to) + 1);
    const periodDays = spanDays(period);
    const expected = (rows: Row[]) => scaleMinor(sum(rows), baselineDays, periodDays);
    const findings: UnusualFinding[] = [];

    const expectedTotal = expected(history);
    if (periodMinor > expectedTotal * UNUSUAL.spikeRatio && periodMinor - expectedTotal >= UNUSUAL.minSpikeMinor)
      findings.push({ kind: "total_above_average", periodMinor, expectedMinor: expectedTotal, diffMinor: periodMinor - expectedTotal, pctChange: pctChange(periodMinor, expectedTotal) });

    const categories = new Set(current.map((r) => r.category));
    for (const category of categories) {
      const now = current.filter((r) => r.category === category);
      const exp = expected(history.filter((r) => r.category === category));
      const value = sum(now);
      if (value >= exp * UNUSUAL.spikeRatio && value - exp >= UNUSUAL.minSpikeMinor)
        findings.push({ kind: "category_spike", category, periodMinor: value, expectedMinor: exp, diffMinor: value - exp });
    }

    for (const r of current) {
      const peers = history.filter((h) => h.category === r.category).map((h) => h.spend);
      if (peers.length < UNUSUAL.minCategorySamples) continue;
      const m = median(peers);
      if (r.spend >= Math.max(m * UNUSUAL.largeRatio, UNUSUAL.minLargeMinor) && r.spend > Math.max(...peers))
        findings.push({ kind: "large_transaction", transaction: toCard(r, ctx), categoryMedianMinor: m });
    }

    if (historyWeeks >= 4) {
      const known = new Set(history.map((h) => normalizeText(h.expense.merchant)));
      const seen = new Set(findings.flatMap((f) => (f.kind === "large_transaction" ? [normalizeText(f.transaction.merchant)] : [])));
      let added = 0;
      for (const r of [...current].sort((a, b) => b.spend - a.spend)) {
        const key = normalizeText(r.expense.merchant);
        if (added >= UNUSUAL.maxNewMerchants || !key || key === "unknown" || known.has(key) || seen.has(key) || r.spend < UNUSUAL.minNewMerchantMinor) continue;
        added += 1;
        seen.add(key);
        findings.push({ kind: "new_merchant", transaction: toCard(r, ctx) });
      }
    }

    const order = { total_above_average: 0, category_spike: 1, large_transaction: 2, new_merchant: 3 } as const;
    findings.sort((x, y) => order[x.kind] - order[y.kind]);
    return { ok: true, data: { ...base, enoughHistory: true, expectedMinor: expectedTotal, findings: findings.slice(0, 8) }, evidence: ev };
  });
}

/** Weekday name for a local date ("Saturday"). */
export const weekdayName = (date: LocalDate) => ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][weekdayIndex(date)];

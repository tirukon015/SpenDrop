// Deterministic question understanding (no model, no cost): intent + entities (amount, period, merchant, category,
// funding account, payment channel, currency) → a plan of tool calls. It handles the common questions on its own,
// so simple questions never need an LLM; anything it can't confidently understand is returned as `unknown` and
// goes to the configured model (if any). The planner only chooses tool ARGUMENTS — it never touches data, and the
// user scope is added later by executeTool() from the authenticated context.
import { COMMON_FUNDING_ACCOUNTS } from "@/lib/domain/constants";
import type { CategoryId, PaymentChannelId } from "@/lib/domain/types";
import { AMOUNT_TOLERANCE } from "./config";
import { understand, understoodAs, type Understanding } from "./normalize";
import type { Vocabulary } from "./repository";
import {
  addDays, addMonths, daysInMonth, endOfMonth, formatSpan, isLocalDate, presetSpan, previousComparable, startOfMonth, startOfWeek,
  weekdayIndex, type DateSpan, type LocalDate,
} from "./time";
import { currencyKey, normalizeText } from "./tools";
import type { AnswerStatus, Focus, FocusFilters, Intent } from "./types";

export interface PlanStep { tool: "search_transactions" | "calculate_spending" | "compare_periods" | "get_transaction" | "get_weekly_summary" | "find_unusual_spending" | "get_spending_insights"; args: Record<string, unknown> }

export type Plan = (
  | {
      kind: "tools";
      intent: Intent;
      steps: PlanStep[];
      focus: Focus;
      /** Notes the answer must mention (e.g. "SpenDrop doesn't store locations"). */
      notes: string[];
      /** For lookups: wider searches to try, in order, if nothing matches (each is mentioned in the answer). */
      expansions?: { args: Record<string, unknown>; note: string }[];
      /** Shape hints for the composer. */
      style?: { topN?: number; smallest?: boolean; restaurants?: boolean; detailIfSingle?: boolean; judgement?: boolean };
    }
  | { kind: "reply"; intent: Intent; status: AnswerStatus; text: string; followUps: string[] }
  | { kind: "memory"; action: "set"; merchant: string; category: CategoryId }
  | { kind: "memory"; action: "list" }
  | { kind: "memory"; action: "forget"; subject: string | null }
  | { kind: "unknown"; general: boolean }
) & { understoodAs?: string };

// ---------------------------------------------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------------------------------------------

const CUR = String.raw`(rm|myr|usd|us\$|sgd|s\$|gbp|eur|bdt|tk|\$|£|€|৳)`;
const NUM = String.raw`(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)`;
const CUR_WORD = String.raw`(ringgit|rm|myr|usd|dollars?|sgd|gbp|pounds?|eur|euros?|taka|tk|bdt)`;
const APPROX = /\b(around|about|roughly|approx(?:imately)?|almost|nearly|something like|close to|sekitar|lebih kurang|kira[- ]kira|prai|pray)\b|~/;

const CURRENCY_OF: Record<string, string> = {
  rm: "RM", myr: "RM", ringgit: "RM", usd: "USD", "us$": "USD", $: "USD", dollar: "USD", dollars: "USD", sgd: "SGD", "s$": "SGD",
  gbp: "GBP", "£": "GBP", pound: "GBP", pounds: "GBP", eur: "EUR", "€": "EUR", euro: "EUR", euros: "EUR", bdt: "BDT", tk: "BDT", taka: "BDT", "৳": "BDT",
};
const num = (s: string) => Number(s.replace(/,/g, ""));

export interface AmountEntity { min: number; max: number; target: number | null; currency: string | null; approximate: boolean; text: string }

export function extractAmount(text: string): AmountEntity | null {
  const t = text.toLowerCase();
  const approximate = APPROX.test(t);
  // "RM20–30", "RM20 to RM30", "between RM20 and RM30", "20-30 ringgit"
  const prefixed = new RegExp(String.raw`${CUR}\s?${NUM}\s?(?:-|–|—|to|and)\s?(?:${CUR}\s?)?${NUM}`).exec(t);
  const suffixed = prefixed ? null : new RegExp(String.raw`\b${NUM}\s?(?:-|–|—|to)\s?${NUM}\s?${CUR_WORD}\b`).exec(t);
  const range = prefixed ? { lo: prefixed[2], hi: prefixed[4], cur: prefixed[1], text: prefixed[0] } : suffixed ? { lo: suffixed[1], hi: suffixed[2], cur: suffixed[3], text: suffixed[0] } : null;
  if (range && num(range.hi) >= num(range.lo)) {
    const lo = num(range.lo), hi = num(range.hi);
    return { min: lo, max: hi, target: null, currency: CURRENCY_OF[range.cur] ?? null, approximate: true, text: range.text };
  }
  const single = new RegExp(String.raw`${CUR}\s?${NUM}`).exec(t) ?? new RegExp(String.raw`\b${NUM}\s?${CUR_WORD}\b`).exec(t);
  if (!single) return null;
  const [value, cur] = /^\d/.test(single[1]) ? [num(single[1]), single[2]] : [num(single[2]), single[1]];
  if (!(value > 0)) return null;
  const currency = CURRENCY_OF[cur] ?? null;
  const before = t.slice(0, single.index);
  if (/(over|above|more than|greater than|at least|bigger than|>)\s*$/.test(before)) return { min: value, max: 1_000_000_000, target: null, currency, approximate: false, text: single[0] };
  if (/(under|below|less than|at most|cheaper than|smaller than|<)\s*$/.test(before)) return { min: 0, max: value, target: null, currency, approximate: false, text: single[0] };
  const tol = approximate ? AMOUNT_TOLERANCE.approximate : AMOUNT_TOLERANCE.exact;
  const minor = Math.round(value * 100);
  const delta = Math.max(tol.minMinor, Math.round(minor * tol.ratio));
  return { min: Math.max(0, minor - delta) / 100, max: (minor + delta) / 100, target: value, currency, approximate, text: single[0] };
}

const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];
const MONTH_RE = String.raw`(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)`;
const monthIndex = (s: string) => MONTHS.findIndex((m) => m.startsWith(s.slice(0, 3)));
const WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
const pad = (n: number) => String(n).padStart(2, "0");

export interface PeriodEntity { span: DateSpan; exactDay: boolean; label: string }

function day(y: number, m: number, d: number, today: LocalDate, yearGiven: boolean): LocalDate | null {
  if (m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  const date = `${y}-${pad(m)}-${pad(d)}`;
  return !yearGiven && date > today ? `${y - 1}-${pad(m)}-${pad(d)}` : date;
}

export function extractPeriod(text: string, today: LocalDate): PeriodEntity | null {
  const t = text.toLowerCase().replace(/['’]/g, "");
  const single = (d: LocalDate, label?: string): PeriodEntity => ({ span: { from: d, to: d }, exactDay: true, label: label ?? formatSpan({ from: d, to: d }) });
  const span = (s: DateSpan | null, label: string): PeriodEntity | null => (s ? { span: s, exactDay: s.from === s.to, label } : null);
  const year = Number(today.slice(0, 4));

  let m = /\b(\d{4})-(\d{2})-(\d{2})\b/.exec(t);
  if (m && isLocalDate(m[0])) return single(m[0]);
  m = new RegExp(String.raw`\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?${MONTH_RE}\.?(?:,?\s+(\d{4}))?\b`).exec(t);
  if (m) { const d = day(m[3] ? Number(m[3]) : year, monthIndex(m[2]) + 1, Number(m[1]), today, Boolean(m[3])); if (d) return single(d); }
  m = new RegExp(String.raw`\b${MONTH_RE}\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b`).exec(t);
  if (m) { const d = day(m[3] ? Number(m[3]) : year, monthIndex(m[1]) + 1, Number(m[2]), today, Boolean(m[3])); if (d) return single(d); }
  m = /(?:^|[^\d.$])(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/.exec(t);
  if (m) { const y = m[3] ? (m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])) : year; const d = day(y, Number(m[2]), Number(m[1]), today, Boolean(m[3])); if (d) return single(d); }

  if (/\bday before yesterday\b/.test(t)) return single(addDays(today, -2));
  if (/\b(today|tonight|hari ini|aaj|ajke)\b|আজ/.test(t)) return single(today, "Today");
  if (/\b(yesterday|semalam|kalke|gotokal)\b|গতকাল/.test(t)) return single(addDays(today, -1), "Yesterday");

  m = /\b(?:last|past|previous)\s+(\d{1,3})\s+(days?|weeks?|months?)\b/.exec(t);
  if (m) {
    const n = Number(m[1]);
    const from = m[2].startsWith("day") ? addDays(today, -(n - 1)) : m[2].startsWith("week") ? addDays(today, -(7 * n - 1)) : addDays(addMonths(today, -n), 1);
    return span({ from, to: today }, `Last ${n} ${m[2]}`);
  }
  if (/\b(this|current)\s+weekend\b/.test(t)) { const s = addDays(startOfWeek(today), 5); return span({ from: s, to: addDays(s, 1) }, "This weekend"); }
  if (/\blast\s+weekend\b/.test(t)) { const s = addDays(startOfWeek(today), -2); return span({ from: s, to: addDays(s, 1) }, "Last weekend"); }
  if (/\b(this|current|ei)\s+week\b|minggu ini|এই সপ্তাহ/.test(t)) return span(presetSpan("this_week", today), "This week");
  if (/\b(last|previous)\s+week\b|minggu lepas|\bgoto\s+(week|shoptah)/.test(t)) return span(presetSpan("last_week", today), "Last week");
  if (/\bpast\s+week\b/.test(t)) return span(presetSpan("last_7_days", today), "Last 7 days");
  if (/\b(this|current|ei)\s+(month|mash|mas)\b|bulan ini|এই মাস/.test(t)) return span(presetSpan("this_month", today), "This month");
  if (/\b(last|previous)\s+month\b|bulan lepas|\bgoto\s+mash/.test(t)) return span(presetSpan("last_month", today), "Last month");
  if (/\b(this|current)\s+year\b|tahun ini/.test(t)) return span(presetSpan("this_year", today), "This year");
  if (/\b(last|previous)\s+year\b|tahun lepas/.test(t)) return span(presetSpan("last_year", today), "Last year");

  m = new RegExp(String.raw`\b(last|this|on|past)?\s*(${WEEKDAYS.join("|")}|mon|tues?|wed|thur?s?|fri|sat|sun)\b`).exec(t);
  if (m && !/\b(every|each)\s+$/.test(t.slice(0, m.index))) {
    const target = WEEKDAYS.findIndex((w) => w.startsWith(m![2].slice(0, 3)));
    const todayIdx = weekdayIndex(today);
    let back = (todayIdx - target + 7) % 7;
    if (m[1] === "last" && back === 0) back = 7;
    const d = addDays(today, -back);
    return single(d, `${m[1] === "last" ? "Last " : ""}${WEEKDAYS[target][0].toUpperCase()}${WEEKDAYS[target].slice(1)} (${formatSpan({ from: d, to: d })})`);
  }

  // A month on its own ("in September", "October 2025"). "may" only with a preposition or a year.
  m = new RegExp(String.raw`\b(in|during|for|of|on)?\s*(january|february|march|april|may|june|july|august|september|october|november|december)\b(?:\s+(\d{4}))?`).exec(t);
  if (m && (m[2] !== "may" || m[1] || m[3])) {
    const mi = MONTHS.indexOf(m[2]) + 1;
    let y = m[3] ? Number(m[3]) : year;
    if (!m[3] && `${y}-${pad(mi)}-01` > today) y -= 1;
    const from = `${y}-${pad(mi)}-01`;
    return span({ from, to: endOfMonth(from) }, `${m[2][0].toUpperCase()}${m[2].slice(1)} ${y}`);
  }
  return null;
}

const CATEGORY_WORDS: [CategoryId, RegExp][] = [
  ["Groceries", /\b(grocer(y|ies)|supermarkets?|barang dapur|bazar)\b/],
  ["Food", /\b(food|foods|eat|eating|ate|meals?|restaurants?|restoran|cafes?|café|coffee|lunch|dinner|breakfast|brunch|makan(an)?|snacks?|drinks?|mamak|khabar|khawa)\b/],
  ["Transport", /\b(transport(ation)?|rides?|taxi|e-?hailing|fuel|petrol|parking|tolls?|train|lrt|mrt|bus|commut(e|ing))\b/],
  ["Shopping", /\b(shopping|clothes|clothing|gadgets?)\b/],
  ["Bills", /\b(bills?|utilit(y|ies)|electricity|internet|phone bill|rent)\b/],
  ["Entertainment", /\b(entertainment|movies?|cinema|gaming|games|concerts?)\b/],
  ["Education", /\b(education|tuition|course fees?|courses|textbooks?)\b/],
  ["Health", /\b(health|medical|medicine|clinic|pharmacy|doctor|hospital)\b/],
  ["Travel", /\b(travel(ling)?|trips?|hotels?|flights?|holidays?|vacation)\b/],
  ["Personal", /\b(personal care|haircut|salon|grooming)\b/],
  ["Subscription", /\b(subscriptions?|streaming|memberships?)\b/],
];

export function extractCategory(text: string): { category: CategoryId; word: string } | null {
  const t = text.toLowerCase();
  for (const [category, re] of CATEGORY_WORDS) {
    const m = re.exec(t);
    if (m) return { category, word: m[0] };
  }
  const named = /\b(categor(y|ies)\s+)?(groceries|transport|shopping|bills|entertainment|education|health|travel|personal|subscription|other)\s+categor/.exec(t);
  return named ? { category: (named[3][0].toUpperCase() + named[3].slice(1)) as CategoryId, word: named[3] } : null;
}

const CHANNEL_WORDS: [PaymentChannelId, RegExp][] = [
  ["APPLE_PAY", /\bapple\s?pay\b/],
  ["DUITNOW_QR", /\bduit\s?now(\s+qr)?\b/],
  ["TNG_QR", /\b(tng|touch\s?n\s?go|touch and go)\s+qr\b/],
  ["QR_PAYMENT", /\b(qr|qr\s?(payment|code)|scan(ned)?\s+(to\s+)?pay)\b/],
  ["ONLINE_BANKING", /\b(online banking|fpx)\b/],
  ["BANK_TRANSFER", /\b(bank transfers?|transferred|via transfer|by transfer|transfers?)\b/],
  ["CARD", /\b(credit card|debit card|card|visa|mastercard)\b/],
  ["E_WALLET", /\b(e-?\s?wallet|grabpay|boost|shopeepay)\b/],
  ["CASH", /\bcash\b/],
];

/** All QR payment channels: a plain "QR" question covers every one of them. */
const QR_CHANNELS: PaymentChannelId[] = ["QR_PAYMENT", "DUITNOW_QR", "TNG_QR"];

export function extractChannel(text: string): { channel: PaymentChannelId; channels?: PaymentChannelId[]; word: string } | null {
  const t = text.toLowerCase().replace(/['’]/g, "");
  for (const [channel, re] of CHANNEL_WORDS) {
    const m = re.exec(t);
    if (m) return channel === "QR_PAYMENT" && !/qr payment/.test(m[0]) ? { channel, channels: QR_CHANNELS, word: m[0] } : { channel, word: m[0] };
  }
  return null;
}

const ACCOUNT_ALIASES: Record<string, string> = { tng: "Touch 'n Go", "touch n go": "Touch 'n Go", "touch and go": "Touch 'n Go", "maybank2u": "Maybank", m2u: "Maybank" };

const wordsIn = (text: string, phrase: string) => phrase.length > 1 && ` ${text} `.includes(` ${phrase} `);

export function extractFundingAccount(text: string, vocabulary: Vocabulary): { account: string; word: string } | null {
  const t = normalizeText(text);
  const names = [...new Set([...vocabulary.fundingAccounts, ...COMMON_FUNDING_ACCOUNTS.filter((a) => a !== "Other")])];
  let best: { account: string; word: string } | null = null;
  for (const name of names) {
    const n = normalizeText(name);
    if (wordsIn(t, n) && (!best || n.length > best.word.length)) best = { account: name, word: n };
  }
  for (const [alias, name] of Object.entries(ACCOUNT_ALIASES)) {
    if (wordsIn(t, alias) && (!best || alias.length > best.word.length)) best = { account: vocabulary.fundingAccounts.find((a) => normalizeText(a) === normalizeText(name)) ?? name, word: alias };
  }
  return best;
}

/** Generic words that are never a merchant on their own. */
const NOT_MERCHANT = new Set([
  "the", "my", "and", "for", "from", "with", "what", "where", "when", "which", "spend", "spent", "money", "payment", "payments", "purchase", "purchases",
  "transaction", "transactions", "food", "shop", "store", "kedai", "restoran", "restaurant", "cafe", "coffee", "bank", "online", "pay", "sdn", "bhd", "malaysia",
  "week", "month", "year", "today", "yesterday", "last", "this", "total", "much", "many", "unknown",
]);

export function extractMerchant(text: string, vocabulary: Vocabulary, exclude: string[], original = text): { merchant: string; word: string } | null {
  const t = normalizeText(text);
  const blocked = exclude.map(normalizeText);
  let best: { merchant: string; word: string } | null = null;
  for (const merchant of vocabulary.merchants) {
    const n = normalizeText(merchant);
    const first = n.split(" ").find((w) => w.length >= 4 && !NOT_MERCHANT.has(w) && !/^\d+$/.test(w));
    for (const phrase of [n, first]) {
      if (!phrase || NOT_MERCHANT.has(phrase) || blocked.some((b) => b.includes(phrase) || phrase.includes(b))) continue;
      if (wordsIn(t, phrase) && (!best || phrase.length > best.word.length)) best = { merchant: phrase, word: phrase };
    }
  }
  if (best) return best;
  // "at Foo Bar" for a merchant the user hasn't recorded yet (searching for it is honest: it will find nothing).
  const m = /\bat\s+([a-z0-9][\w&.'-]*(?:\s+(?!on\b|in\b|last\b|this\b|yesterday\b|today\b|using\b|with\b|from\b|for\b|around\b|near\b)[a-z0-9][\w&.'-]*){0,2})/.exec(text.toLowerCase());
  if (m) {
    const name = normalizeText(m[1]);
    if (name && !/^(least|most|all|the|my|night|home|work|uni|university|campus|office|school|college|mall|around|about)\b/.test(name) && !blocked.some((b) => b.includes(name))) return { merchant: name, word: name };
  }
  // A capitalised name the user hasn't recorded ("that RM89 Shopee payment"): searching for it is honest.
  for (const w of original.split(/\s+/).slice(1)) {
    const word = w.replace(/[^\p{L}\p{N}&'-]/gu, "");
    const n = normalizeText(word);
    if (!/^\p{Lu}/u.test(word) || n.length < 3 || /\d/.test(n) || NOT_MERCHANT.has(n) || NOT_NAME.test(n) || blocked.some((b) => b.includes(n))) continue;
    return { merchant: n, word: n };
  }
  return null;
}

const NOT_NAME = new RegExp(String.raw`^(${MONTH_RE}|${WEEKDAYS.join("|")}|rm|myr|usd|sgd|gbp|eur|bdt|spendrop|apple|pay|qr|duitnow|touch|go|tng|why|how|which|show|did|was|is|it|am|can|could|please|thanks?)$`);

// ---------------------------------------------------------------------------------------------------------------
// Intent
// ---------------------------------------------------------------------------------------------------------------

const has = (t: string, re: RegExp) => re.test(t);
const SECURITY = /\b(pretend|act as|you are now|role ?play|switch to)\b.{0,30}\b(admin|administrator|developer|root|superuser|god mode)\b|\b(everyone|everybody|anyone)'?s?\b.{0,20}\b(expenses?|transactions?|spending|data|records)\b|\b(other|another|every|all|someone else'?s?|different)\s+(users?|people'?s|accounts? of)|\buser[\s_-]?ids?\b|\b(sql|drop\s+table|database records|all records)\b|\bselect\s+(\*|[a-z_]+\s+from\b)|ignore (all|any|previous|prior|your|the) (instructions|rules)|system prompt|\bjailbreak\b|developer mode/;
const GREETING = /^(hi|hello|hey|salam|assalamualaikum|good (morning|afternoon|evening)|yo)\b[!. ]*$|^(help|what can you do|how do(es)? (this|you) work)\??$/;
const WHY = /\bwhy\b|what changed|\breason\b|kenapa|keno\b|কেন/;
const COMPARE = /\b(going|go|gone) (up|down)\b|\b(more|less) (spent|spending)\b|\bcompare|comparison|\bvs\.?\b|versus|(spend|spent|spending)\s+(more|less)|\b(more|less|higher|lower)\s+than\b|increase|decrease|went (up|down)|too much|getting (worse|better)|\b(trend|trending)\b|\b(habit|lately|recently)\b.*\b(worse|better|more|less)\b/;
const UNUSUAL = /\b(unusual|strange|weird|odd|anomal\w*|abnormal|out of the ordinary|spikes?|than usual|than normal|suspicious)\b/;
const SUMMARY = /\b(summary|summari[sz]e|recap|overview|report|wrap[- ]?up)\b|where did (all )?my money go|where('?s| is) my money going/;
const ACCOUNT_Q = /\b(which|what)\s+(funding\s+)?(account|bank|wallet)s?\b|\baccounts? do i\b|\bby (funding )?account\b|\bper account\b/;
const CHANNEL_Q = /\b(which|what)\s+(payment\s+)?(channel|method)s?\b|how do i (usually |mostly )?pay\b|\bby (payment )?(channel|method)\b/;
const CATEGORY_Q = /\bwhat do i spend (the )?most on\b|\b(which|what)\s+categor(y|ies)\b|\bby categor(y|ies)\b|categor(y|ies) (cost|costs|take|takes)|breakdown|\b(share|percent(age)?|proportion|portion) of (my )?(spending|money)\b/;
const MERCHANT_Q = /\b(which|what)\s+(merchants?|shops?|stores?|places?|restaurants?|cafes?|brands?)\b|\btop merchants?\b|where do i (spend|shop|eat) (the )?most|\bmost (at|from)\b/;
const BIGGEST = /\b(biggest|largest|most expensive|highest|priciest|top \d+)\b/;
const SMALLEST = /\b(smallest|cheapest|lowest)\b/;
const COUNT = /\bhow many\b|\bnumber of\b/;
const AVERAGE = /\baverage|\bavg\b|\bmean\b|\bper day\b|\bdaily\b/;
const LIST = /\b(show|list|find|search|which transactions|what transactions|what was (that|the)|what did i buy|purchases|payments|transactions|receipts?|look for|look up)\b/;
const HOW_MUCH = /\bhow much|\btotal|\bspent\b|\bspend(ing)?\b|\bcost\b|\bpaid\b|\bberapa|\bbelanja|\bkoto\b|\bkhoroch|কত|খরচ/;
const DETAIL = /\b(first|second|third|fourth|fifth|1st|2nd|3rd|4th|5th|last) one\b|#\s?([1-9])\b|\bnumber ([1-9])\b|\b(that|this) one\b|\btell me more\b|\bmore details?\b|\bdetails\b/;
const FOLLOW_UP = /^(and|what about|how about|also|then|so|ok(ay)?|but)\b|^(why|those|them)\b|^compare (it |that |this )?(with|to)\b/;
const WEAK_FOLLOW_UP = /^(which|show|list|that)\b/;
const LOCATION = /\bnear\s+(the\s+)?\w+|\bat\s+(the\s+)?(uni|university|campus|office|college|school|mall|home|work)\b/;
const ORDINALS = ["first", "second", "third", "fourth", "fifth"];
const SECRETS = /\b(passwords?|passcodes?|pin( number)?|otp|tac code|cvv|cvc|card number|full card|login details|api key|secret key|service role)\b/;
const BALANCE = /\b(bank )?balance\b|\bhow much (money )?(do i have|is (left )?in)\b/;
/** Questions SpenDrop has no data for: answered with an honest limitation, never sent to a model to improvise. */
const OFF_TOPIC: [RegExp, string][] = [
  [/\b(weather|forecast|temperature|rain(ing)?|sunny|humid)\b/, "weather data"],
  [/\b(football|soccer|match|score|who won|league|cricket|badminton|world cup)\b/, "sports results"],
  [/\b(news|election|president|prime minister|politics)\b/, "news"],
  [/\b(stock price|share price|bitcoin|crypto price|exchange rate|forex|gold price)\b/, "market prices or exchange rates"],
  [/\b(meaning of life|tell me a joke|joke|poem|recipe|movie|song|lyrics|translate)\b/, "anything for that — I only work with your spending records"],
];
/** Words whose meaning SpenDrop can't know without the user (asked, never guessed). */
const AMBIGUOUS_SPEND = /\b(waste[ds]?|wasting|unnecessary|useless|pointless|frivolous|impulse|stupid|bad) (money|spending|purchases?|buys?|things?)?\b|\bwaste\b/;
/** "How much did I spend there?" — needs a place from the conversation. */
const REFERENCE = /\b(spen[dt]|paid|pay|buy|bought|purchases?)\b.*\b(there|that place|that shop|that store|that merchant|the same place)\b/;
const INSIGHTS = /\b(spend(ing)?|spent) so much\b|\bso much (spent|spending|spend)\b|\bso much lately\b|what'?s (going )?wrong|going wrong|how am i doing|how'?s my spending|spending (habits?|patterns?)|\binsights?\b|anything i should know|should i (stop|cut|reduce)|where can i (save|cut)|\bcut back\b|spending too much|am i (over ?spending|spending too much)|\bnoticed?\b/;
const ORDINAL_NUMS = ["1st", "2nd", "3rd", "4th", "5th"];

const capabilities =
  "I can look things up in your own SpenDrop records. Try: “How much did I spend this week?”, “Where did my RM15 go?”, " +
  "“Did I spend more this month?”, “Which account do I use most?” or “What unusual spending happened this week?”.";

export interface PlanInput { message: string; today: LocalDate; vocabulary: Vocabulary; focus: Focus | null }

const spanArg = (s: DateSpan | null) => (s ? { from: s.from, to: s.to } : undefined);
const thisMonth = (today: LocalDate): DateSpan => ({ from: startOfMonth(today), to: endOfMonth(today) });

export function plan(input: PlanInput): Plan {
  const u = understand(input.message, [...input.vocabulary.merchants, ...input.vocabulary.fundingAccounts]);
  const p = planFrom(input, u);
  const shown = understoodAs(u);
  return shown && p.kind !== "unknown" ? { ...p, understoodAs: shown } : p;
}

function planFrom({ message, today, vocabulary, focus }: PlanInput, u: Understanding): Plan {
  const raw = message.trim();
  // The planner reads the normalised text (other languages, slang and typos → canonical English); names and
  // amounts are also read from the original text.
  const t = u.text;
  const lowerRaw = raw.toLowerCase();

  if (has(t, SECURITY) || has(lowerRaw, SECURITY))
    return {
      kind: "reply", intent: "SECURITY", status: "refused",
      text: "I can only see your own SpenDrop records — never anyone else's, and I can't run database queries or change my rules. Ask me anything about your own spending.",
      followUps: ["How much did I spend this week?", "Show my biggest purchase this month"],
    };
  if (has(t, SECRETS))
    return {
      kind: "reply", intent: "SECURITY", status: "refused",
      text: "I don't have access to passwords, PINs, OTPs or card numbers — and you should never share them with anyone, including me. SpenDrop only keeps the transactions you record.",
      followUps: ["How much did I spend this week?"],
    };
  if (has(t, BALANCE))
    return {
      kind: "reply", intent: "OUT_OF_SCOPE", status: "clarify",
      text: "SpenDrop doesn't connect to your bank, so I can't see your balance. I can tell you what you've recorded spending — for example from one account.",
      followUps: ["How much did I spend from Maybank this month?", "Which account do I use most?"],
    };
  const offTopic = OFF_TOPIC.find(([re]) => re.test(t));
  if (offTopic)
    return {
      kind: "reply", intent: "OUT_OF_SCOPE", status: "clarify",
      text: `I can help with your SpenDrop finances, but I don't have ${offTopic[1]}.`,
      followUps: ["How much did I spend this week?", "Where did my money go this week?"],
    };
  if (has(t, GREETING)) return { kind: "reply", intent: "GENERAL", status: "answered", text: capabilities, followUps: ["How much did I spend this week?", "Give me my weekly summary"] };

  // Personal rules and memory ("Grab is transport for me", "what do you remember?", "forget Grab")
  const memory = memoryPlan(raw, t);
  if (memory) return memory;

  // Entities
  const amount = extractAmount(raw) ?? extractAmount(t);
  const period = extractPeriod(t, today);
  const categoryHit = extractCategory(t);
  const channelHit = extractChannel(t);
  const accountHit = extractFundingAccount(t, vocabulary);
  const notes: string[] = [];

  // Funding account vs payment channel: "from X" / "X account" is WHERE the money came from; "using/via/with X" is HOW.
  let channel = channelHit?.channel;
  let fundingAccount = accountHit?.account;
  if (channelHit && accountHit && (channelHit.word.includes(accountHit.word) || accountHit.word.includes(normalizeText(channelHit.word)))) {
    const fromAccount = new RegExp(String.raw`\b(from|in|my)\s+${accountHit.word}\b|\b${accountHit.word}\s+(account|wallet|balance)\b`).test(normalizeText(t));
    if (fromAccount) channel = undefined; else fundingAccount = undefined;
  }
  const merchantHit = extractMerchant(t, vocabulary, [accountHit?.word ?? "", channelHit?.word ?? "", categoryHit?.word ?? ""].filter(Boolean), raw);
  const currencyWord = /\b(usd|sgd|gbp|eur|bdt|myr|ringgit)\b/.exec(t)?.[1];
  // A currency named on its own filters everything; the currency of an amount only applies to that amount.
  const currency = currencyWord ? CURRENCY_OF[currencyWord] : undefined;
  if (has(t, LOCATION) && !merchantHit) notes.push("SpenDrop doesn't record where a payment happened, so I searched by amount and date only.");
  const restaurants = /\brestaurants?|restoran|cafes?|places to eat\b/.test(t);
  if (restaurants && categoryHit?.category === "Food") notes.push("SpenDrop has no separate Restaurants category, so I used your Food category.");

  const entityFilters: FocusFilters = {
    ...(categoryHit ? { category: categoryHit.category } : {}),
    ...(merchantHit ? { merchant: titleCase(merchantHit.merchant) } : {}),
    ...(fundingAccount ? { fundingAccount } : {}),
    ...(channel ? (channelHit?.channels ? { paymentChannels: channelHit.channels } : { paymentChannel: channel }) : {}),
    ...(currency ? { currency } : {}),
  };
  const hasEntities = Object.keys(entityFilters).length > 0 || Boolean(amount) || Boolean(period);

  // Follow-ups reuse what the conversation is about: the previous filters only when the message names none of its
  // own, the previous period only when it names no period. "Show me my Starbucks purchases" is a new question.
  const namesFilters = Object.keys(entityFilters).length > 0 || Boolean(amount);
  const isFollowUp = Boolean(focus) && (has(t, FOLLOW_UP) || raw.split(/\s+/).length <= 3 || (has(t, WEAK_FOLLOW_UP) && !namesFilters && !period));
  const baseFilters: FocusFilters = isFollowUp && focus && !namesFilters ? stripAmounts(focus.filters) : entityFilters;
  const baseSpan: DateSpan | null = period?.span ?? (isFollowUp && focus ? focus.span : null);

  // Don't guess what a word means when the answer would change with the meaning.
  if (has(t, AMBIGUOUS_SPEND)) {
    const when = period ? period.label.toLowerCase() : "this month";
    return {
      kind: "reply", intent: "CLARIFY", status: "clarify",
      text: "Do you mean all your spending, or only spending you consider unnecessary? I can't tell which purchases you'd call a waste — but I can show everything, or one category or merchant you have in mind.",
      followUps: [`All my spending ${when}`, `Shopping ${when}`, `Food ${when}`],
    };
  }
  if (has(t, REFERENCE) && !merchantHit) {
    if (focus?.filters.merchant) entityFilters.merchant = focus.filters.merchant;
    else return { kind: "reply", intent: "CLARIFY", status: "clarify", text: "Which merchant or place do you mean?", followUps: [] };
  }

  // Transaction detail ("the first one", "tell me more")
  if (focus?.transactionIds?.length && has(t, DETAIL) && !amount) {
    const m = DETAIL.exec(t)!;
    const ids = focus.transactionIds;
    const index = m[1] ? (m[1] === "last" ? ids.length - 1 : Math.max(ORDINALS.indexOf(m[1]), ORDINAL_NUMS.indexOf(m[1])))
      : m[2] ? Number(m[2]) - 1 : m[3] ? Number(m[3]) - 1 : 0;
    const id = ids[index];
    if (id) return tools("TRANSACTION_DETAIL", [{ tool: "get_transaction", args: { transactionId: id } }], { ...focus, intent: "TRANSACTION_DETAIL", transactionIds: [id] }, notes);
    return { kind: "reply", intent: "TRANSACTION_DETAIL", status: "clarify", text: `I only showed ${focus.transactionIds.length} transaction${focus.transactionIds.length === 1 ? "" : "s"}. Which one do you mean?`, followUps: [] };
  }

  const filterArgs = (f: FocusFilters) => ({
    ...(f.category ? { category: f.category } : {}), ...(f.merchant ? { merchant: f.merchant } : {}),
    ...(f.fundingAccount ? { fundingAccount: f.fundingAccount } : {}), ...(f.paymentChannel ? { paymentChannel: f.paymentChannel } : {}),
    ...(f.paymentChannels ? { paymentChannels: f.paymentChannels } : {}),
    ...(f.currency ? { currency: f.currency } : {}),
  });

  // Unusual spending / "more than usual"
  if (has(t, UNUSUAL)) {
    const s = baseSpan ?? presetSpan("this_week", today)!;
    return tools("UNUSUAL_SPENDING", [{ tool: "find_unusual_spending", args: { period: spanArg(s) } }], { intent: "UNUSUAL_SPENDING", filters: {}, span: s }, notes);
  }

  // "Why am I spending so much lately?", "What's going wrong with my spending?" → personal patterns vs the user's own normal
  if (has(t, INSIGHTS) && !amount) {
    const f = filterArgs(namesFilters ? entityFilters : {});
    const preset = period && /week/.test(period.label.toLowerCase()) ? "this_week" : "this_month";
    return tools("INSIGHTS", [{ tool: "get_spending_insights", args: { period: preset, ...f } }],
      { intent: "INSIGHTS", filters: namesFilters ? entityFilters : {}, span: presetSpan(preset, today) }, notes);
  }

  // Why? → investigate the change behind the current focus (or the named filters/period)
  if (has(t, WHY)) {
    const s = baseSpan ?? thisMonth(today);
    const b = focus?.compareSpan && !period ? focus.compareSpan : previousComparable(s, today);
    const f = baseFilters;
    return tools("INVESTIGATE", [{ tool: "compare_periods", args: { periodA: spanArg(s), periodB: spanArg(b), ...filterArgs(f) } }],
      { intent: "INVESTIGATE", filters: f, span: s, compareSpan: b }, notes);
  }

  // Summary ("where did my money go this week", "weekly summary")
  if (has(t, SUMMARY) && !amount) {
    const s = baseSpan;
    const weekly = !s || /\bweek(ly)?\b/.test(t) || (s.from === startOfWeek(s.from) && addDays(s.from, 6) === s.to);
    if (weekly) {
      const weekOf = s?.from ?? today;
      const w = { from: startOfWeek(weekOf), to: addDays(startOfWeek(weekOf), 6) };
      return tools("SUMMARY", [{ tool: "get_weekly_summary", args: weekOf === today ? {} : { weekOf } }], { intent: "SUMMARY", filters: {}, span: w }, notes);
    }
    return tools("CATEGORY_ANALYSIS", [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "sum", groupBy: "category", ...filterArgs(baseFilters) } }],
      { intent: "CATEGORY_ANALYSIS", filters: baseFilters, span: s }, notes);
  }

  // Comparison ("did I spend more this month?", "this month vs last month", "compare with last week")
  if (has(t, COMPARE) && !(amount && /\b(more|less|higher|lower) than\b/.test(t))) {
    const unit = /\b(?:this|current|last|previous)\s+(week|month|year)\b/.exec(t)?.[1] as "week" | "month" | "year" | undefined;
    const current = (u: "week" | "month" | "year") => presetSpan(u === "week" ? "this_week" : u === "month" ? "this_month" : "this_year", today)!;
    const previous = (u: "week" | "month" | "year") => presetSpan(u === "week" ? "last_week" : u === "month" ? "last_month" : "last_year", today)!;
    let a: DateSpan;
    let b: DateSpan;
    if (unit && /\b(this|current)\s+(week|month|year)\b/.test(t) && /\b(last|previous)\s+(week|month|year)\b/.test(t)) {
      // "this month vs last month": fair comparison (same days of last month while this one is in progress)
      a = current(unit); b = previousComparable(a, today);
    } else if (isFollowUp && focus?.span && focus.intent !== "SEARCH") {
      a = focus.span;
      const same = period && unit && period.span.from === previous(unit).from && period.span.to === previous(unit).to && a.from === current(unit).from;
      b = !period || same ? previousComparable(a, today) : period.span;
    } else if (isFollowUp && period && unit && period.span.from === previous(unit).from) {
      // "compare with last month" after a lookup: this month so far vs the same days of last month
      a = current(unit); b = previousComparable(a, today);
    } else {
      a = period?.span ?? thisMonth(today);
      b = previousComparable(a, today);
    }
    return { ...tools("COMPARE", [{ tool: "compare_periods", args: { periodA: spanArg(a), periodB: spanArg(b), ...filterArgs(baseFilters) } }],
      { intent: "COMPARE", filters: baseFilters, span: a, compareSpan: b }, notes), style: { judgement: /too much/.test(t) } };
  }

  // Breakdown questions
  const analysis: [RegExp, Intent, "funding_account" | "payment_channel" | "category" | "merchant"][] = [
    [ACCOUNT_Q, "ACCOUNT_ANALYSIS", "funding_account"], [CHANNEL_Q, "PAYMENT_CHANNEL_ANALYSIS", "payment_channel"],
    [CATEGORY_Q, "CATEGORY_ANALYSIS", "category"], [MERCHANT_Q, "MERCHANT_ANALYSIS", "merchant"],
  ];
  for (const [re, intent, groupBy] of analysis) {
    if (!has(t, re) || amount) continue;
    const overall = /\b(usually|mostly|most|always|overall|ever|in general)\b/.test(t) && !period;
    const s = overall ? null : baseSpan ?? thisMonth(today);
    const f = { ...baseFilters };
    // "Which restaurants?" → merchants in Food.
    if (groupBy === "merchant" && restaurants) f.category = "Food";
    if (groupBy === "funding_account") delete f.fundingAccount;
    if (groupBy === "payment_channel") delete f.paymentChannel;
    if (groupBy === "category") delete f.category;
    return { ...tools(intent, [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "sum", groupBy, ...filterArgs(f) } }], { intent, filters: f, span: s, groupBy }, notes), style: { restaurants } };
  }

  // Biggest / smallest
  if ((has(t, BIGGEST) || has(t, SMALLEST)) && !amount) {
    const n = Number(/\btop (\d+)\b/.exec(t)?.[1] ?? (/\b(purchases|transactions|payments)\b/.test(t) ? 5 : 1));
    const s = baseSpan;
    return { ...tools("SEARCH", [{ tool: "search_transactions", args: { period: spanArg(s), ...filterArgs(baseFilters), sort: has(t, SMALLEST) ? "amount_asc" : "amount_desc", limit: Math.min(n, 20) } }],
      { intent: "SEARCH", filters: baseFilters, span: s }, notes), style: { topN: n, smallest: has(t, SMALLEST) } };
  }

  // Count / average
  if (has(t, COUNT) && !amount) {
    const s = baseSpan ?? thisMonth(today);
    return tools("CALCULATE", [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "count", ...filterArgs(baseFilters) } }], { intent: "CALCULATE", filters: baseFilters, span: s, operation: "count" }, notes);
  }
  if (has(t, AVERAGE) && !amount) {
    const s = baseSpan ?? thisMonth(today);
    return tools("CALCULATE", [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "average", ...filterArgs(baseFilters) } }], { intent: "CALCULATE", filters: baseFilters, span: s, operation: "average" }, notes);
  }

  // Lookups and lists ("where did my RM15 go", "show my Shopee purchases")
  const lookup = Boolean(amount) && /\bwhere|\bwhat|\bfind|\bwhich|\bshow|\bremember|\bthat\b|\bpayment|\bpurchase|\btransaction|\bspent|\bspend|\bpaid|\bgo\b|\bwent\b/.test(t);
  if (lookup || (has(t, LIST) && !has(t, HOW_MUCH))) {
    const f: FocusFilters = { ...baseFilters, ...(amount ? { amountMin: amount.min, amountMax: amount.max } : {}) };
    const search = (s: DateSpan | null) => ({
      period: spanArg(s), ...filterArgs(f),
      ...(amount ? { amountMin: amount.min, amountMax: amount.max } : {}),
      ...(amount?.currency && !f.currency ? { currency: amount.currency } : {}),
      ...(amount?.target ? { targetAmount: amount.target } : {}),
      ...(period?.exactDay ? { targetDate: period.span.from } : {}),
      ...(/\breceipts?\b/.test(t) ? { hasReceipt: true } : {}),
      sort: amount || period?.exactDay ? "relevance" : "date_desc",
      limit: amount ? 10 : 20,
    });
    let s = baseSpan;
    const expansions: { args: Record<string, unknown>; note: string }[] = [];
    if (amount && !s) {
      const named = f.merchant || f.category || f.fundingAccount || f.paymentChannel;
      s = { from: addDays(today, named ? -364 : -29), to: today };
      if (!named) expansions.push({ args: search({ from: addDays(today, -89), to: today }), note: "Nothing in the last 30 days, so I searched the last 90 days." });
    } else if (period?.exactDay && amount) {
      const d = period.span.from;
      expansions.push({ args: search({ from: addDays(d, -1), to: addDays(d, 1) < today ? addDays(d, 1) : today }), note: `Nothing on ${formatSpan(period.span)}, so I also checked the day before and after.` });
    }
    if (amount && amount.target !== null) {
      // Widen the amount a little if the remembered amount was off.
      const wide = extractAmount(raw.replace(amount.text, `around ${amount.text}`));
      if (wide && wide.min < amount.min) expansions.push({ args: { ...search(s), amountMin: wide.min, amountMax: wide.max }, note: `Nothing between ${fmt(amount.min, currency)} and ${fmt(amount.max, currency)}, so I widened the amount range.` });
    }
    return { ...tools("SEARCH", [{ tool: "search_transactions", args: search(s) }], { intent: "SEARCH", filters: f, span: s }, notes, expansions), style: { detailIfSingle: Boolean(amount) } };
  }

  // "What about last month?", "and Grab?" → repeat the previous question with only what was named changed.
  if (isFollowUp && focus && hasEntities && !has(t, HOW_MUCH)) return replay(focus);

  // Totals ("how much did I spend on food this week?") and bare phrases ("food last week?", "last week?")
  const bare = hasEntities && t.split(/\s+/).length <= 6;
  if (bare && entityFilters.merchant && !entityFilters.category && !has(t, HOW_MUCH)) {
    const s = baseSpan;
    return tools("SEARCH", [{ tool: "search_transactions", args: { period: spanArg(s), ...filterArgs(baseFilters), sort: "date_desc", limit: 20 } }], { intent: "SEARCH", filters: baseFilters, span: s }, notes);
  }
  if (has(t, HOW_MUCH) || bare) {
    const s = baseSpan ?? (isFollowUp && focus ? focus.span : thisMonth(today));
    const f = { ...baseFilters, ...(amount ? { amountMin: amount.min, amountMax: amount.max } : {}) };
    return tools("CALCULATE", [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "sum", ...filterArgs(f), ...(amount ? { amountMin: amount.min, amountMax: amount.max } : {}) } }],
      { intent: "CALCULATE", filters: f, span: s, operation: "sum" }, notes);
  }

  // Everything else is either a general question or not understood.
  const general = !hasEntities && /\b(what is|what's|how (do|can|should) i|explain|tips?|advice|budget(ing)?|save|saving|invest)\b/.test(t);
  return { kind: "unknown", general };

  function replay(f: Focus): Plan {
    const s = period?.span ?? f.span;
    const kept = stripAmounts(f.filters);
    if (entityFilters.merchant || entityFilters.category) { delete kept.merchant; delete kept.category; }
    if (entityFilters.paymentChannel || entityFilters.paymentChannels) { delete kept.paymentChannel; delete kept.paymentChannels; }
    const filters: FocusFilters = { ...kept, ...entityFilters };
    const args = filterArgs(filters);
    switch (f.intent) {
      case "COMPARE": case "INVESTIGATE": {
        const a = s ?? thisMonth(today);
        const b = previousComparable(a, today);
        return tools(f.intent, [{ tool: "compare_periods", args: { periodA: spanArg(a), periodB: spanArg(b), ...args } }], { intent: f.intent, filters, span: a, compareSpan: b }, notes);
      }
      case "SUMMARY": {
        const weekOf = s?.from ?? today;
        return tools("SUMMARY", [{ tool: "get_weekly_summary", args: weekOf === today ? {} : { weekOf } }], { intent: "SUMMARY", filters: {}, span: { from: startOfWeek(weekOf), to: addDays(startOfWeek(weekOf), 6) } }, notes);
      }
      case "UNUSUAL_SPENDING":
        return tools("UNUSUAL_SPENDING", [{ tool: "find_unusual_spending", args: { period: spanArg(s ?? presetSpan("this_week", today)) } }], { intent: "UNUSUAL_SPENDING", filters: {}, span: s }, notes);
      case "SEARCH": case "TRANSACTION_DETAIL":
        return tools("SEARCH", [{ tool: "search_transactions", args: { period: spanArg(s), ...args, sort: "date_desc", limit: 20 } }], { intent: "SEARCH", filters, span: s }, notes);
      case "INSIGHTS":
        return tools("INSIGHTS", [{ tool: "get_spending_insights", args: { period: s && s.to.slice(0, 7) !== s.from.slice(0, 7) ? "this_week" : "this_month", ...args } }], { intent: "INSIGHTS", filters, span: s }, notes);
      default: {
        if (f.groupBy) {
          const g = f.groupBy;
          const intent: Intent = g === "category" ? "CATEGORY_ANALYSIS" : g === "merchant" ? "MERCHANT_ANALYSIS" : g === "funding_account" ? "ACCOUNT_ANALYSIS" : "PAYMENT_CHANNEL_ANALYSIS";
          return tools(intent, [{ tool: "calculate_spending", args: { period: spanArg(s), operation: "sum", groupBy: g, ...args } }], { intent, filters, span: s, groupBy: g }, notes);
        }
        const op = f.operation ?? "sum";
        return tools("CALCULATE", [{ tool: "calculate_spending", args: { period: spanArg(s), operation: op, ...args } }], { intent: "CALCULATE", filters, span: s, operation: op }, notes);
      }
    }
  }
}

/** Personal rules: "Grab is transport for me", "treat Starbucks as food", "what do you remember?", "forget Grab". */
function memoryPlan(raw: string, t: string): Plan | null {
  const lower = raw.toLowerCase().replace(/[’]/g, "'").trim().replace(/^(please\s+)?(remember|note|keep in mind)\s+(that\s+)?/, "");
  if (/\b(what do you (remember|know) about me|what have you (learned|remembered)|my (personal )?(rules|preferences|memories)|show (my )?(rules|memories|preferences))\b/.test(t))
    return { kind: "memory", action: "list" };
  const forget = /^(?:please\s+)?(?:forget|remove|delete|clear)\s+(?:my\s+|the\s+)?(?:rule\s+(?:for|about)\s+|that\s+|about\s+)?(.+?)(?:\s+(?:is|as)\s+.+)?[.!]*$/.exec(lower);
  if (forget && /^(forget|remove rule|delete rule|clear)/.test(lower.replace(/^please\s+/, "").replace(/\s(my|the)\s/, " ")) || (forget && /^(?:please\s+)?forget\b/.test(lower))) {
    const subject = forget![1].trim();
    return { kind: "memory", action: "forget", subject: /^(everything|all|all (my )?(rules|preferences|memories)|it all)$/.test(subject) ? null : subject.replace(/['"]/g, "") };
  }
  if (/\btransfers?\b.*\b(own|my|between)\b.*\b(not|aren'?t|isn'?t|never|shouldn'?t)\b.*\b(expenses?|spending)\b/.test(lower))
    return {
      kind: "reply", intent: "PERSONAL_RULE", status: "answered",
      text: "That's already how SpenDrop works: transfers between your own accounts are never counted as spending, so there's nothing to change.",
      followUps: ["How much did I spend this month?"],
    };
  if (lower.endsWith("?") || /^(is|are|does|do|did|what|which|how|why|where|when|can|should)\b/.test(lower)) return null;
  // Banglish / Malay: "grab amar jonno transport", "grab untuk saya transport"
  const local = /^(.+?)\s+(?:amar\s+(?:jonno|kache)|untuk\s+saya|bagi\s+saya)\s+([a-z]+)[.!]*$/.exec(lower);
  if (local) {
    const category = CATEGORY_NAMES.find((c) => c.toLowerCase() === local[2]) ?? extractCategory(local[2])?.category;
    const subject = local[1].replace(/['"]/g, "").trim();
    if (category && subject.length >= 2 && subject.length <= 40 && !isOnlyCategory(subject)) return { kind: "memory", action: "set", merchant: subject.replace(/\b\p{L}/gu, (c) => c.toUpperCase()), category };
  }
  const m = /^(?:no|nope|actually|nah)?[,!.]?\s*(?:please\s+)?(?:treat\s+(.+?)\s+as\s+|put\s+(.+?)\s+(?:in|under)\s+|(.+?)\s+(?:is|are|counts as|should be|goes under|goes in|belongs (?:in|to))\s+(?:always\s+)?(?:a\s+|an\s+|my\s+)?)([a-z ]+?)(?:\s+category)?(?:\s+(?:for me|to me|in my case|for my records|from now on))*\s*[.!]*$/.exec(lower);
  if (!m) return null;
  const subject = (m[1] ?? m[2] ?? m[3] ?? "").replace(/^(that|the|my)\s+/, "").replace(/['"]/g, "").trim();
  const value = m[4].trim();
  const category = CATEGORY_NAMES.find((c) => c.toLowerCase() === value) ?? extractCategory(value)?.category;
  if (!category || subject.length < 2 || subject.length > 40 || isOnlyCategory(subject) || /\b(spending|money|this|it|everything)\b/.test(subject)) return null;
  return { kind: "memory", action: "set", merchant: subject.replace(/\b\p{L}/gu, (c) => c.toUpperCase()), category };
}

/** "food" or "restaurants" on its own is a category, not a merchant; "Mamak Corner" is a merchant. */
const isOnlyCategory = (subject: string) => extractCategory(subject)?.word === subject.trim();

const CATEGORY_NAMES: CategoryId[] = ["Food", "Groceries", "Transport", "Shopping", "Bills", "Entertainment", "Education", "Health", "Travel", "Personal", "Subscription", "Other"];

function tools(intent: Intent, steps: PlanStep[], focus: Focus, notes: string[], expansions?: { args: Record<string, unknown>; note: string }[]): Plan & { kind: "tools" } {
  return { kind: "tools", intent, steps, focus, notes, ...(expansions?.length ? { expansions } : {}) };
}

const titleCase = (s: string) => s.replace(/\b\p{L}/gu, (c) => c.toUpperCase());
const stripAmounts = (f: FocusFilters): FocusFilters => { const { amountMin: _a, amountMax: _b, ...rest } = f; return rest; }; // eslint-disable-line @typescript-eslint/no-unused-vars
const fmt = (major: number, currency?: string) => `${currency ? currencyKey(currency) : "RM"} ${major.toFixed(2)}`;

export const CAPABILITIES_TEXT = capabilities;

/** How the question named its period ("this week", "yesterday"), for answers like "this week (5–11 Oct 2026)". */
export function periodWordsOf(message: string, today: LocalDate): string | undefined {
  const p = extractPeriod(message, today);
  if (!p || /\d/.test(p.label)) return undefined;
  return p.label.toLowerCase();
}

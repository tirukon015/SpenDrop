// Evidence-first classification, ported from iOS (CategoryDetector, MerchantDetector, PaymentChannel.suggest,
// TransactionClassifier, ChannelLearning). Local only: no receipt data leaves the browser.
import type { CategoryId, ChannelRule, ClassificationRule, PaymentChannelId } from "@/lib/domain/types";
import { KNOWN_MERCHANTS, type KnownMerchant } from "./known-merchants";

export interface Suggestion<T> { value: T; confidence: number; reason: string; needsReview: boolean }
const REVIEW = 0.7;
const suggestion = <T,>(value: T, confidence: number, reason: string): Suggestion<T> => ({ value, confidence, reason, needsReview: confidence < REVIEW });

/** Lowercase, keep letters/numbers/' - . *, collapse whitespace (iOS MerchantDetector.normalizedWords). */
export function normalizedWords(text: string) {
  return text.toLowerCase().replace(/[’]/g, "'").replace(/[^\p{L}\p{N}'\-.*]+/gu, " ").replace(/\s+/g, " ").trim();
}
const hasPhrase = (haystack: string, phrase: string) => ` ${haystack} `.includes(` ${normalizedWords(phrase)} `);

export function knownMerchant(name: string | null | undefined): KnownMerchant | null {
  if (!name) return null;
  const words = normalizedWords(name);
  return KNOWN_MERCHANTS.find((m) => m.keywords.some((k) => hasPhrase(words, k))) ?? null;
}

const KEYWORDS: [CategoryId, string[]][] = [
  ["Food", ["restaurant", "restoran", "cafe", "café", "coffee", "kopi", "bistro", "bakery", "kopitiam", "dining", "lunch", "dinner", "breakfast", "burger", "pizza", "nasi", "mee", "roti", "ayam", "food", "foods", "makan", "kedai makan", "warung", "selera", "mamak", "kitchen", "noodle", "noodles", "bakeri", "dim sum", "satay", "sushi", "tealive", "boba", "bubble tea", "catering"]],
  ["Groceries", ["supermarket", "hypermarket", "grocery", "grocer", "groceries", "pasar", "pasar malam", "pasar raya", "mart", "minimart", "mini market", "supermart", "fresh market", "fruit", "fruits", "vegetable", "vegetables", "runcit", "kedai runcit"]],
  ["Transport", ["petrol", "fuel", "diesel", "ron95", "ron97", "parking", "toll", "rfid", "lrt", "mrt", "monorail", "ktm", "rapid kl", "bus", "taxi", "e-hailing", "grabcar", "airasia", "flight", "airline", "airport"]],
  ["Bills", ["electricity", "tenaga", "water", "air selangor", "utility", "utilities", "bill payment", "telekom", "postpaid", "broadband", "internet", "unifi", "reload", "topup", "top up"]],
  ["Health", ["pharmacy", "farmasi", "clinic", "klinik", "hospital", "doctor", "dental", "gigi", "optometry", "optical", "medicine", "ubat"]],
  ["Entertainment", ["cinema", "cinemas", "movie", "theatre", "wayang", "bowling", "karaoke", "steam", "concert"]],
  ["Education", ["tuition", "university", "college", "school", "sekolah", "exam", "bookstore", "stationery", "popular bookstore", "mph"]],
  ["Travel", ["hotel", "resort", "homestay", "airbnb", "hostel", "tour", "travel", "vacation"]],
  ["Subscription", ["subscription", "recurring", "monthly fee", "annual fee", "membership"]],
  ["Personal", ["salon", "barber", "haircut", "spa", "massage", "facial", "nail", "nails"]],
  ["Shopping", ["mall", "fashion", "boutique", "apparel", "shoes", "clothing", "accessories", "hardware", "gadget", "electronics", "store", "shop", "retail"]],
];

function matchCategory(text: string, excluding?: string | null): { category: CategoryId; word: string; ambiguous: boolean } | null {
  let haystack = ` ${normalizedWords(text)} `;
  if (excluding) haystack = haystack.replace(` ${normalizedWords(excluding)} `, " ");
  const hits: [CategoryId, string][] = [];
  for (const [category, words] of KEYWORDS) {
    const word = words.find((w) => haystack.includes(` ${normalizedWords(w)} `));
    if (word) hits.push([category, word]);
  }
  return hits.length ? { category: hits[0][0], word: hits[0][1], ambiguous: hits.length > 1 } : null;
}

/** Category from evidence: known merchant (0.95) > words in the merchant name (0.8) > receipt words (0.55) > Other (0). */
export function suggestCategory(merchant: string | null | undefined, receiptText = ""): Suggestion<CategoryId> {
  const known = knownMerchant(merchant);
  if (known) {
    if (known.ambiguous) {
      const context = matchCategory(receiptText, merchant);
      if (context && context.category !== known.category) return suggestion(context.category, 0.6, `${known.name} sells several things; the receipt mentions '${context.word}'`);
      return suggestion(known.category, 0.5, `${known.name} can be rides, food or deliveries; please check`);
    }
    return suggestion(known.category, 0.95, `Known merchant: ${known.name}`);
  }
  if (merchant) {
    const hit = matchCategory(merchant);
    if (hit) return suggestion(hit.category, hit.ambiguous ? 0.6 : 0.8, hit.ambiguous ? `Merchant name suggests more than one category ('${hit.word}')` : `Merchant name contains '${hit.word}'`);
  }
  const hit = matchCategory(receiptText, merchant);
  if (hit) return suggestion(hit.category, 0.55, `Receipt mentions '${hit.word}'`);
  return suggestion("Other", 0, "No category evidence in this receipt");
}

const CHANNEL_EVIDENCE: [PaymentChannelId, number, string[]][] = [
  ["APPLE_PAY", 0.98, ["apple pay", "pay with apple", "apple cash"]],
  ["DUITNOW_QR", 0.97, ["duitnow qr", "duitnow-qr", "duit now qr", "d-qr", "paynet qr"]],
  ["TNG_QR", 0.95, ["touch 'n go qr", "touch n go qr", "tng qr", "tng ewallet qr", "touchngo qr"]],
  ["CARD", 0.92, ["card purchase", "pos purchase", "pos card", "card present", "contactless", "chip & pin", "chip and pin", "card payment", "debit card purchase", "credit card purchase", "card transaction"]],
  ["BANK_TRANSFER", 0.9, ["duitnow transfer", "fund transfer", "funds transfer", "interbank", "ibg", "instant transfer", "transfer to account", "transferred to", "giro", "fpx", "fpx payment", "bank transfer", "transfer successful", "online transfer", "jompay"]],
  ["QR_PAYMENT", 0.8, ["scan & pay", "scan and pay", "qr pay", "qr payment", "scan qr", "via qr", "qr code payment", "pay by qr"]],
  ["OTHER", 0.75, ["online payment", "online purchase", "pay online", "online transaction"]],
  ["CASH", 0.85, ["cash", "cash payment", "paid in cash", "tunai", "wang tunai"]],
];

/** Channel only from wording on the receipt; otherwise Unknown (never guessed from the bank or wallet). */
export function suggestChannel(evidenceText: string): Suggestion<PaymentChannelId> {
  const words = normalizedWords(evidenceText);
  for (const [channel, confidence, phrases] of CHANNEL_EVIDENCE) {
    const phrase = phrases.find((p) => hasPhrase(words, p));
    if (phrase) return { value: channel, confidence, reason: `The receipt says '${phrase}'`, needsReview: false };
  }
  return { value: "UNKNOWN", confidence: 1, reason: "The receipt doesn't say how it was paid", needsReview: true };
}

const FUNDING: [string, RegExp][] = [
  ["Touch 'n Go", /touch\s*['’]?n\s*go|tng\s*e?wallet|\btng\b|e-?wallet\s*balance/i],
  ["Maybank", /maybank|mae\b|m2u/i],
  ["CIMB", /\bcimb\b|octo/i],
  ["RHB", /\brhb\b/i],
  ["Public Bank", /public\s*bank|pbe(?:ngage)?\b/i],
  ["Bank Islam", /bank\s*islam/i],
  ["Wise", /\bwise\b/i],
  ["GrabPay", /grabpay/i],
  ["Boost", /\bboost\b/i],
];

/** Funding account (where the money came from) from the first provider/bank named. Unknown when none. */
export function detectFunding(text: string): string {
  const recipientCut = text.split(/recipient['’]?s?\s*bank|beneficiary['’]?s?\s*bank/i)[0];
  for (const [name, re] of FUNDING) if (re.test(recipientCut)) return name;
  return "Unknown";
}

export const merchantKey = (merchant: string | null | undefined) => {
  const key = (merchant ?? "").replace(/’/g, "'").toLowerCase().split(/\s+/).filter(Boolean).join(" ");
  return ["", "unknown", "unknown merchant"].includes(key) ? null : key;
};
/** Rules are stored under the known merchant's name (so "MCD BANGSAR" and "McDonald's" share one). */
export const ruleKey = (merchant: string | null | undefined) => merchantKey(knownMerchant(merchant)?.name ?? merchant);
export const fundingKey = (funding: string | null | undefined) => {
  const v = (funding ?? "").trim().toLowerCase();
  return ["", "unknown", "other"].includes(v) ? "" : v;
};

/** Learned category on top of evidence: confirmed twice → used; once → used when the evidence is weak or agrees. */
export function learnedCategory(merchant: string, evidence: Suggestion<CategoryId>, rules: ClassificationRule[]): Suggestion<CategoryId> {
  const keys = [ruleKey(merchant), merchantKey(merchant)].filter(Boolean);
  const rule = rules.find((r) => !r.deletedAt && keys.includes(r.merchantKey));
  if (rule?.category) {
    if (rule.hitCount >= 2) return suggestion(rule.category, 0.97, `You chose ${rule.category} for this merchant before`);
    if (evidence.needsReview || evidence.value === rule.category) return suggestion(rule.category, 0.85, `You chose ${rule.category} for this merchant last time`);
  }
  return evidence;
}

/** Learned channel per merchant AND funding account, only when the receipt is silent and confirmed twice. */
export function learnedChannel(merchant: string, funding: string, detected: PaymentChannelId, rules: ChannelRule[]): Suggestion<PaymentChannelId> | null {
  const key = ruleKey(merchant);
  if (detected !== "UNKNOWN" || !key) return null;
  const rule = rules.find((r) => !r.deletedAt && r.merchantKey === key && r.fundingKey === fundingKey(funding));
  if (!rule || rule.hitCount < 2 || rule.channel === "UNKNOWN") return null;
  return { value: rule.channel, confidence: 0.85, reason: `You chose ${rule.channel.replace(/_/g, " ").toLowerCase()} for this merchant${fundingKey(funding) ? ` from ${funding}` : ""} before`, needsReview: false };
}

// HOLD-OUT v4 — frozen 2026-10-08 BEFORE the idiom / frequency / payment-channel / Banglish-trend / multilingual-answer
// refinement, and not tuned against afterwards. Includes the brief's own examples plus unseen phrasings. Each case
// checks the plan (intent + key arguments) and, for language cases, that the ANSWER is in the user's language with
// the same verified figures. The score is reported honestly; the test fails only below the recorded first run.
import { describe, expect, it } from "vitest";
import { answerDeterministic } from "@/lib/ai/core";
import { plan, type Plan } from "@/lib/ai/planner";
import type { Focus } from "@/lib/ai/types";
import { USER_A, ctx, historyStore } from "./fixtures";
import { VOCABULARY } from "./nlu.test";

type Lang = "en" | "bn-latn" | "bn" | "ms";
interface Case { q: string; after?: string[]; intent: string | string[]; args?: Record<string, unknown>; absentArgs?: string[]; lang?: Lang; group: string }

const THIS_MONTH = { from: "2026-10-01", to: "2026-10-31" };

export const HOLDOUT_V4: Case[] = [
  // spending idioms → where money goes / how I'm doing (never a merchant called "eating")
  { group: "idiom", q: "Where is all my money going?", intent: ["CATEGORY_ANALYSIS", "SUMMARY"] },
  { group: "idiom", q: "I'm burning through money", intent: ["INSIGHTS", "CATEGORY_ANALYSIS"], absentArgs: ["merchant"] },
  { group: "idiom", q: "my spending is getting out of hand", intent: "INSIGHTS", absentArgs: ["merchant"] },
  { group: "idiom", q: "what's eating up my money?", intent: "CATEGORY_ANALYSIS", absentArgs: ["merchant"] },
  { group: "idiom", q: "am I wasting money?", intent: "INSIGHTS", absentArgs: ["merchant"] },
  { group: "idiom", q: "what am I throwing money away on?", intent: "CATEGORY_ANALYSIS", absentArgs: ["merchant"] },
  { group: "idiom", q: "my money keeps disappearing", intent: ["INSIGHTS", "CATEGORY_ANALYSIS"], absentArgs: ["merchant"] },
  { group: "idiom", q: "I'm spending like crazy this week", intent: "INSIGHTS", absentArgs: ["merchant"] },
  { group: "idiom", q: "expenses are way too high lately", intent: "INSIGHTS", absentArgs: ["merchant"] },
  // frequency → a COUNT of transactions (not "visits")
  { group: "frequency", q: "How often do I buy from Shopee?", intent: "CALCULATE", args: { operation: "count", merchant: "Shopee" } },
  { group: "frequency", q: "How often do I use Grab?", intent: "CALCULATE", args: { operation: "count", merchant: "Grab" } },
  { group: "frequency", q: "How many times did I pay at Starbucks?", intent: "CALCULATE", args: { operation: "count", merchant: "Starbucks" } },
  { group: "frequency", q: "How frequently am I spending on restaurants?", intent: "CALCULATE", args: { operation: "count", category: "Food" } },
  { group: "frequency", q: "starbucks koto bar gesi ei mash e?", intent: "CALCULATE", args: { operation: "count", merchant: "Starbucks", period: THIS_MONTH } },
  // payment channels (never confused with funding accounts)
  { group: "channel", q: "card or qr?", intent: "PAYMENT_CHANNEL_ANALYSIS", absentArgs: ["fundingAccount"] },
  { group: "channel", q: "which do I use more, card or QR?", intent: "PAYMENT_CHANNEL_ANALYSIS", absentArgs: ["fundingAccount"] },
  { group: "channel", q: "do I mostly pay by card?", intent: "PAYMENT_CHANNEL_ANALYSIS", absentArgs: ["fundingAccount"] },
  { group: "channel", q: "how much did I pay by card?", intent: "CALCULATE", args: { paymentChannel: "CARD" } },
  { group: "channel", q: "how much did I pay using QR?", intent: "CALCULATE", absentArgs: ["fundingAccount"] },
  { group: "channel", q: "apple pay vs card this month", intent: "PAYMENT_CHANNEL_ANALYSIS" },
  // Banglish trend verbs
  { group: "banglish", q: "amar spending barche?", intent: ["COMPARE", "INSIGHTS"] },
  { group: "banglish", q: "food er khoroch barche keno?", intent: ["INVESTIGATE", "INSIGHTS"], args: { category: "Food" } },
  { group: "banglish", q: "ei mash e khoroch barse?", intent: ["COMPARE", "INSIGHTS"] },
  { group: "banglish", q: "amar spending komche naki?", intent: ["COMPARE", "INSIGHTS"] },
  { group: "banglish", q: "transport e khoroch bere jacche", intent: ["COMPARE", "INSIGHTS", "INVESTIGATE"], args: { category: "Transport" } },
  // multilingual financial answers: same verified figures, the user's language
  { group: "lang", q: "How much did I spend on food this week?", intent: "CALCULATE", args: { category: "Food" }, lang: "en" },
  { group: "lang", q: "ei week e food e koto khoroch hoise?", intent: "CALCULATE", args: { category: "Food" }, lang: "bn-latn" },
  { group: "lang", q: "এই সপ্তাহে খাবারে কত খরচ করেছি?", intent: "CALCULATE", args: { category: "Food" }, lang: "bn" },
  { group: "lang", q: "berapa saya belanja untuk makanan minggu ni?", intent: "CALCULATE", args: { category: "Food" }, lang: "ms" },
  { group: "lang", q: "grab e koto bar gesi?", intent: "CALCULATE", args: { operation: "count", merchant: "Grab" }, lang: "bn-latn" },
  { group: "lang", q: "berapa kali saya guna Grab?", intent: "CALCULATE", args: { operation: "count", merchant: "Grab" }, lang: "ms" },
  // context regression
  { group: "context", q: "How often?", after: ["How much did I spend on Food this month?", "Why?", "Which restaurants?", "Yesterday?", "What about last month?", "Is that increasing?"], intent: "CALCULATE", args: { operation: "count", category: "Food" } },
  { group: "context", q: "How often?", after: ["How much did I spend at Shopee?"], intent: "CALCULATE", args: { operation: "count", merchant: "Shopee" } },
  { group: "context", q: "Is that increasing?", after: ["How much did I spend on Food this month?"], intent: ["COMPARE", "INSIGHTS"], args: { category: "Food" } },
];

/** First-run result (see the report). */
export const HOLDOUT_V4_FIRST_RUN = 0.14; // 5/34 before the refinement (see report)

const TODAY = "2026-10-07";
function planOf(c: Case): Plan {
  let focus: Focus | null = null;
  for (const q of c.after ?? []) { const p = plan({ message: q, today: TODAY, vocabulary: VOCABULARY, focus }); if (p.kind === "tools") focus = p.focus; }
  return plan({ message: c.q, today: TODAY, vocabulary: VOCABULARY, focus });
}

/** Rough language check of an answer's text (Bengali script / Banglish / Malay function words / English). */
export function answerLanguage(text: string): Lang {
  if (/[ঀ-৿]/.test(text)) return "bn";
  if (/\b(tomar|khoroch|hoise|ta transaction|kono|nai|ei|mash|bar)\b/i.test(text)) return "bn-latn";
  if (/\b(anda|belanja|transaksi|dalam|tiada|kali|bulan|minggu)\b/i.test(text)) return "ms";
  return "en";
}
const money = (text: string) => (text.match(/RM\s?[\d,]+\.\d\d/g) ?? []).sort();

async function judge(c: Case): Promise<string | null> {
  const p = planOf(c);
  if (p.kind !== "tools") return `no tool (${p.kind}${"intent" in p ? " " + p.intent : ""})`;
  const intents = Array.isArray(c.intent) ? c.intent : [c.intent];
  if (!intents.includes(p.intent)) return `intent ${p.intent}`;
  const args = p.steps[0].args;
  for (const [k, v] of Object.entries(c.args ?? {})) if (JSON.stringify(args[k]) !== JSON.stringify(v)) return `${k}=${JSON.stringify(args[k])}`;
  for (const k of c.absentArgs ?? []) if (args[k] !== undefined) return `${k} should be absent (${JSON.stringify(args[k])})`;
  if (c.lang) {
    const store = historyStore();
    const out = await answerDeterministic(c.q, ctx(), store.forUser(USER_A), null);
    if (out.kind !== "answer") return "no answer";
    const got = answerLanguage(out.answer.text);
    if (got !== c.lang) return `answer language ${got}: ${out.answer.text.slice(0, 80)}`;
    // the same verified figures as the English answer to the same question
    const en = await answerDeterministic("How much did I spend on food this week?", ctx(), historyStore().forUser(USER_A), null);
    if (c.args?.category === "Food" && en.kind === "answer" && JSON.stringify(money(out.answer.text)) !== JSON.stringify(money(en.answer.text))) return `figures differ: ${money(out.answer.text)} vs ${money(en.answer.text)}`;
  }
  return null;
}

describe("hold-out v4 (frozen before the refinement)", () => {
  it("scores at or above its first run", async () => {
    const results = await Promise.all(HOLDOUT_V4.map(async (c) => ({ c, problem: await judge(c) })));
    const ok = results.filter((r) => !r.problem).length;
    if (process.env.NLU_REPORT) {
      const groups = [...new Set(HOLDOUT_V4.map((c) => c.group))].map((g) => { const rs = results.filter((r) => r.c.group === g); return `${g} ${rs.filter((r) => !r.problem).length}/${rs.length}`; });
      console.log(`hold-out v4: ${ok}/${results.length} (${groups.join(", ")})\n${results.filter((r) => r.problem).map((r) => `  ✗ [${r.c.group}] ${r.c.q} → ${r.problem}`).join("\n")}`);
    }
    expect(ok / results.length).toBeGreaterThanOrEqual(HOLDOUT_V4_FIRST_RUN);
  });
});

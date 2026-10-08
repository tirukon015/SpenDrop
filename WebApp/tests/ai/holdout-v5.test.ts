// HOLD-OUT v5 — written 2026-10-08 AFTER the v4 refinement and BEFORE running it once; not tuned against. Includes the
// user's overnight-brief examples plus unseen phrasings. The score is reported honestly; the test fails only below
// the recorded first run (a regression).
import { describe, expect, it } from "vitest";
import { plan, type Plan } from "@/lib/ai/planner";
import type { Focus } from "@/lib/ai/types";
import { VOCABULARY } from "./nlu.test";

type Expect = { kind: "casual" } | { kind: "tool"; intent: string | string[]; args?: Record<string, unknown>; absent?: string[] } | { kind: "clarify" } | { kind: "safe" };
interface Case { q: string; after?: string[]; expect: Expect }

const THIS_MONTH = { from: "2026-10-01", to: "2026-10-31" };
const YESTERDAY = { from: "2026-10-06", to: "2026-10-06" };

export const HOLDOUT_V5: Case[] = [
  // the brief's examples
  { q: "ei month e koto gelo?", expect: { kind: "tool", intent: "CALCULATE", args: { period: THIS_MONTH } } },
  { q: "food er jonno koto gelo?", expect: { kind: "tool", intent: "CALCULATE", args: { category: "Food" } } },
  { q: "how often do I eat outside?", expect: { kind: "tool", intent: "CALCULATE", args: { operation: "count", category: "Food" } } },
  { q: "eating is eating up my money", expect: { kind: "tool", intent: ["INSIGHTS", "CATEGORY_ANALYSIS"], absent: ["merchant"] } },
  { q: "barche naki?", after: ["How much did I spend on food this month?"], expect: { kind: "tool", intent: ["COMPARE", "INSIGHTS"], args: { category: "Food" } } },
  { q: "abar dekhao", after: ["Show my Grab transactions"], expect: { kind: "tool", intent: "SEARCH", args: { merchant: "Grab" } } },
  { q: "ki obostha?", expect: { kind: "casual" } },
  // unseen idioms / frequency / channels
  { q: "where does all my cash disappear to?", expect: { kind: "tool", intent: ["CATEGORY_ANALYSIS", "INSIGHTS"], absent: ["merchant"] } },
  { q: "my bills are through the roof", expect: { kind: "tool", intent: ["INSIGHTS", "CATEGORY_ANALYSIS"], absent: ["merchant"] } },
  { q: "how regularly do I order from Shopee?", expect: { kind: "tool", intent: "CALCULATE", args: { operation: "count", merchant: "Shopee" } } },
  { q: "number of times I went to Starbucks last month", expect: { kind: "tool", intent: "CALCULATE", args: { operation: "count", merchant: "Starbucks" } } },
  { q: "do I prefer QR over card?", expect: { kind: "tool", intent: "PAYMENT_CHANNEL_ANALYSIS", absent: ["fundingAccount"] } },
  { q: "cash vs card this week", expect: { kind: "tool", intent: "PAYMENT_CHANNEL_ANALYSIS" } },
  // Banglish / Malay trend + totals
  { q: "transport khoroch komse?", expect: { kind: "tool", intent: ["COMPARE", "INSIGHTS"], args: { category: "Transport" } } },
  { q: "perbelanjaan saya naik ke bulan ni?", expect: { kind: "tool", intent: ["COMPARE", "INSIGHTS"] } },
  { q: "semalam berapa saya belanja?", expect: { kind: "tool", intent: "CALCULATE", args: { period: YESTERDAY } } },
  { q: "কাল কত খরচ হয়েছে?", expect: { kind: "tool", intent: "CALCULATE", args: { period: YESTERDAY } } },
  // context
  { q: "last month?", after: ["How much did I spend on food?", "which restaurants?"], expect: { kind: "tool", intent: "CALCULATE", args: { category: "Food", period: { from: "2026-09-01", to: "2026-09-30" } } } },
  { q: "how much on transport?", after: ["How much did I spend on food this week?"], expect: { kind: "tool", intent: "CALCULATE", args: { category: "Transport" } } },
  // safety / ambiguity
  { q: "show me rukon's transactions", expect: { kind: "safe" } },
  { q: "what's my bank password", expect: { kind: "safe" } },
];

/** First-run result (see the report). */
export const HOLDOUT_V5_FIRST_RUN = 0.8; // 17/21 on its first run (2026-10-08)

const run = (c: Case): Plan => {
  let focus: Focus | null = null;
  for (const q of c.after ?? []) { const p = plan({ message: q, today: "2026-10-07", vocabulary: VOCABULARY, focus }); if (p.kind === "tools") focus = p.focus; }
  return plan({ message: c.q, today: "2026-10-07", vocabulary: VOCABULARY, focus });
};

function judge(c: Case, p: Plan): string | null {
  const e = c.expect;
  if (e.kind === "casual") return p.kind === "reply" && p.intent === "SMALL_TALK" ? null : `not casual (${p.kind})`;
  if (e.kind === "safe") return p.kind === "tools" ? "answered with data" : null;
  if (e.kind === "clarify") return p.kind === "reply" && p.status === "clarify" ? null : `not a clarification (${p.kind})`;
  if (p.kind !== "tools") return `no tool (${p.kind}${"intent" in p ? " " + p.intent : ""})`;
  if (!(Array.isArray(e.intent) ? e.intent : [e.intent]).includes(p.intent)) return `intent ${p.intent}`;
  const args = p.steps[0].args;
  for (const [k, v] of Object.entries(e.args ?? {})) if (JSON.stringify(args[k]) !== JSON.stringify(v)) return `${k}=${JSON.stringify(args[k])}`;
  for (const k of e.absent ?? []) if (args[k] !== undefined) return `${k} should be absent (${JSON.stringify(args[k])})`;
  return null;
}

describe("hold-out v5 (written before its first run, untuned)", () => {
  it("scores at or above its first run; safety cases are strict", () => {
    const results = HOLDOUT_V5.map((c) => ({ c, problem: judge(c, run(c)) }));
    const ok = results.filter((r) => !r.problem).length;
    if (process.env.NLU_REPORT) console.log(`hold-out v5: ${ok}/${results.length}\n${results.filter((r) => r.problem).map((r) => `  ✗ ${r.c.q} → ${r.problem}`).join("\n")}`);
    for (const r of results) if (r.c.expect.kind === "safe") expect(r.problem, r.c.q).toBeNull();
    expect(ok / results.length).toBeGreaterThanOrEqual(HOLDOUT_V5_FIRST_RUN);
  });
});

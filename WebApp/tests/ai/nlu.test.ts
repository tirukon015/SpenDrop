// Natural-language understanding evaluation: every case in nlu-dataset.ts must map to the expected structured
// intent, tool and arguments (or the expected safe reply / memory action) — the deterministic planner is the
// production path, so it must be 100% on this set. A per-language score is printed for the report.
import { afterAll, describe, expect, it } from "vitest";
import { plan, type Plan } from "@/lib/ai/planner";
import type { Vocabulary } from "@/lib/ai/repository";
import type { Focus } from "@/lib/ai/types";
import { NLU_CASES, type NluCase } from "./nlu-dataset";

const TODAY = "2026-10-07";
export const VOCABULARY: Vocabulary = {
  merchants: ["Starbucks", "Grab", "Shopee", "Mamak Corner", "Jaya Grocer", "Sushi King", "Touch 'n Go Parking", "Harvey Norman"],
  fundingAccounts: ["Maybank", "CIMB", "Touch 'n Go", "Wise", "Cash"],
  currencies: ["RM"], earliestDate: "2026-06-01T00:00:00Z", expenseCount: 100,
};

/** Plans a question after an optional conversation (each earlier answer's focus feeds the next question). */
export function planCase(c: Pick<NluCase, "q" | "after">): Plan {
  let focus: Focus | null = null;
  for (const q of c.after ?? []) {
    const p = plan({ message: q, today: TODAY, vocabulary: VOCABULARY, focus });
    if (p.kind === "tools") focus = p.focus;
  }
  return plan({ message: c.q, today: TODAY, vocabulary: VOCABULARY, focus });
}

export function matches(p: Plan, c: NluCase): string | null {
  const e = c.expect;
  if (e.memory) {
    if (p.kind !== "memory") return `expected memory ${e.memory.action}, got ${p.kind}`;
    if (p.action !== e.memory.action) return `memory action ${p.action}`;
    if (p.action === "set" && (p.merchant !== e.memory.merchant || p.category !== e.memory.category)) return `memory ${p.merchant} → ${p.category}`;
    if (p.action === "forget" && e.memory.subject !== undefined && p.subject !== e.memory.subject) return `forget ${p.subject}`;
    return null;
  }
  if (p.kind === "memory") return `unexpected memory ${p.action}`;
  if (e.intent === "UNKNOWN") return p.kind === "unknown" ? null : `expected unknown, got ${p.kind === "tools" || p.kind === "reply" ? p.intent : "another plan"}`;
  if (p.kind === "unknown") return "not understood";
  if (p.intent !== e.intent) return `intent ${p.intent}`;
  if (e.status && (p.kind !== "reply" || p.status !== e.status)) return `status ${p.kind === "reply" ? p.status : p.kind}`;
  if (e.tool) {
    if (p.kind !== "tools") return `expected tool ${e.tool}`;
    const step = p.steps[0];
    if (step.tool !== e.tool) return `tool ${step.tool}`;
    for (const [k, v] of Object.entries(e.args ?? {})) {
      if (JSON.stringify(step.args[k]) !== JSON.stringify(v)) return `${k}=${JSON.stringify(step.args[k])}`;
    }
    for (const k of e.absent ?? []) if (step.args[k] !== undefined) return `${k} should be absent`;
  }
  return null;
}

const results: { c: NluCase; ok: boolean }[] = [];

describe("SpenDrop AI understands the evaluation set", () => {
  it.each(NLU_CASES.map((c) => [`[${c.lang}/${c.kind}] ${c.q}`, c] as const))("%s", (_name, c) => {
    const problem = matches(planCase(c), c);
    results.push({ c, ok: problem === null });
    expect(problem).toBeNull();
  });
});

afterAll(() => {
  const by = new Map<string, [number, number]>();
  for (const r of results) for (const key of [`lang:${r.c.lang}`, `kind:${r.c.kind}`]) {
    const [ok, n] = by.get(key) ?? [0, 0];
    by.set(key, [ok + (r.ok ? 1 : 0), n + 1]);
  }
  if (process.env.NLU_REPORT) console.log([...by.entries()].sort().map(([k, [ok, n]]) => `${k.padEnd(18)} ${ok}/${n}`).join("\n"));
});

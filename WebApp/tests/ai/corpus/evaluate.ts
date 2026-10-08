// Automatic evaluation of the corpus against SpenDrop AI's real pipeline (planner → tools → composer), on each
// example's own fixture. An answer is correct only if the PLAN is right (intent, filters, period) and the FIGURES equal
// the independent oracle — sounding right is not enough. Failures are attributed to the stage that broke.
import { answerDeterministic } from "@/lib/ai/core";
import { MemoryTenantStore } from "@/lib/ai/repository";
import type { AskAnswer, Focus } from "@/lib/ai/types";
import { formatMoney } from "@/lib/domain/money";
import type { CategoryId, PaymentChannelId } from "@/lib/domain/types";
import { USER_A, USER_B, ctx, exp } from "../fixtures";
import { FIXTURES, type Example, type Fixture } from "./generate";

export type Stage = "A intent" | "B entity" | "C merchant" | "E tool arguments" | "G calculation" | "H evidence" | "I language" | "J conversation" | "security";
export interface Outcome { example: Example; ok: boolean; stage?: Stage; detail?: string; ms: number; toolMs: number }

const stores = new Map<string, MemoryTenantStore>();
function storeFor(fx: Fixture) {
  let s = stores.get(fx.name);
  if (!s) {
    const toExp = (t: Fixture["txns"][number]) => exp({ id: t.id, merchant: t.merchant, amount: t.amountMinor / 100, date: t.date, time: t.time, category: t.category as CategoryId, channel: t.channel as PaymentChannelId, account: t.account, notes: t.remark });
    s = new MemoryTenantStore();
    s.add(USER_A, { expenses: fx.txns.map(toExp) });
    s.add(USER_B, { expenses: fx.otherUser.map(toExp) });
    stores.set(fx.name, s);
  }
  return s;
}

const money = (minor: number) => formatMoney(minor, "RM");
const listed = (a: AskAnswer) => a.blocks.flatMap((b) => (b.type === "transactions" ? b.items : []));
const metricValue = (a: AskAnswer) => a.blocks.find((b) => b.type === "metric")?.valueMinor;
export function answerLanguage(text: string): "en" | "bn-latn" | "bn" | "ms" {
  if (/[ঀ-৿]/.test(text)) return "bn";
  if (/\b(tomar|khoroch|hoise|ta transaction|kono|nai)\b/i.test(text)) return "bn-latn";
  if (/\b(anda|belanja|transaksi|tiada|kali)\b/i.test(text)) return "ms";
  return "en";
}

export async function evaluateOne(e: Example): Promise<Outcome> {
  const fx = e.fixture === "holdout" ? FIXTURES.holdout : FIXTURES.train;
  const repo = storeFor(fx).forUser(USER_A);
  let focus: Focus | null = null;
  for (const q of e.context) {
    const r = await answerDeterministic(q, ctx(), repo, focus);
    if (r.kind === "answer") focus = r.answer.focus ?? focus;
  }
  const t0 = performance.now();
  const r = await answerDeterministic(e.question, ctx(), repo, focus);
  const ms = performance.now() - t0;
  const base = { example: e, ms, toolMs: 0 };
  if (r.kind !== "answer") return { ...base, ok: false, stage: "A intent", detail: "not understood (would go to a model)" };
  const a = r.answer;
  base.toolMs = a.meta.tools.reduce((t, x) => t + x.ms, 0);
  const fail = (stage: Stage, detail: string): Outcome => ({ ...base, ok: false, stage, detail: `${detail} · intent ${a.meta.intent} · “${a.text.slice(0, 90)}”` });
  const blob = JSON.stringify(a);
  if (blob.includes("SECRET OTHER USER") || blob.includes("PRIVATE B") || blob.includes("(other user)")) return fail("security", "another user's data in the answer");

  const x = e.expect;
  switch (x.status) {
    case "refused": return a.meta.tools.length === 0 && (a.status === "refused" || a.status === "clarify" || ["SECURITY", "OUT_OF_SCOPE"].includes(a.meta.intent)) ? { ...base, ok: true } : fail("security", `not refused (${a.status})`);
    case "small_talk": return ["SMALL_TALK", "GENERAL"].includes(a.meta.intent) ? { ...base, ok: true } : fail("J conversation", "not small talk");
    case "clarify": return a.status === "clarify" ? { ...base, ok: true } : fail("A intent", `expected a clarifying question, got ${a.status}`);
    case "no_match": return a.status === "no_match" ? { ...base, ok: true } : fail("C merchant", `expected no match, got ${a.status}`);
  }
  if (x.intents && !x.intents.includes(a.meta.intent)) return fail("A intent", `intent ${a.meta.intent} ∉ ${x.intents.join("/")}`);
  if (a.status !== "answered" && x.result) return fail("A intent", `status ${a.status}`);
  const f = a.focus?.filters ?? {};
  if (x.category && f.category !== x.category) return fail("B entity", `category ${f.category ?? "none"} ≠ ${x.category}`);
  if (x.keyword && !f.keyword && !(a.text.includes("remarks mention"))) return fail("B entity", "no remark topic");
  if (x.span !== undefined) {
    const got = a.focus?.span ?? null;
    if (JSON.stringify(got) !== JSON.stringify(x.span)) return fail("E tool arguments", `period ${JSON.stringify(got)} ≠ ${JSON.stringify(x.span)}`);
  }
  const rows = listed(a);
  if (x.merchants && rows.length && !rows.every((t) => x.merchants!.includes(t.merchant))) return fail("C merchant", `rows from ${[...new Set(rows.map((t) => t.merchant))].join(", ")}`);
  const res = x.result ?? {};
  if (res.sumMinor !== undefined) {
    const v = metricValue(a);
    if (v !== undefined ? v !== res.sumMinor : !a.text.includes(money(res.sumMinor))) return fail(x.merchants ? "C merchant" : "G calculation", `total ${v ?? "?"} ≠ ${res.sumMinor}`);
  }
  if (res.count !== undefined && x.operation === "count" && !new RegExp(`(^|\\D)${res.count}(\\D|$)`).test(a.text)) return fail(x.merchants ? "C merchant" : "G calculation", `count ≠ ${res.count}`);
  if (res.avgMinor !== undefined && !a.text.includes(money(res.avgMinor))) return fail("G calculation", `average ≠ ${money(res.avgMinor)}`);
  if (res.maxMinor !== undefined && !(rows[0]?.spendMinor === res.maxMinor || a.text.includes(money(res.maxMinor)))) return fail("G calculation", `largest ≠ ${money(res.maxMinor)}`);
  if (res.minMinor !== undefined && !(rows[0]?.spendMinor === res.minMinor || a.text.includes(money(res.minMinor)))) return fail("G calculation", `smallest ≠ ${money(res.minMinor)}`);
  if (res.top !== undefined) {
    const b = a.blocks.find((x) => x.type === "breakdown");
    const first = b && b.type === "breakdown" ? b.items[0] : undefined;
    if (!first || first.label.toLowerCase() !== res.top.toLowerCase() || first.valueMinor !== res.topMinor) return fail("G calculation", `top ${first?.label}=${first?.valueMinor} ≠ ${res.top}=${res.topMinor}`);
  }
  if (res.byFamily) {
    const items = a.blocks.find((b) => b.type === "breakdown");
    const got = items && items.type === "breakdown" ? Object.fromEntries(items.items.map((i) => [i.label, i.valueMinor])) : {};
    for (const [k, v] of Object.entries(res.byFamily)) if (got[k] !== v) return fail("G calculation", `${k} ${got[k]} ≠ ${v}`);
  }
  if (res.ids) {
    // Every listed row must be a real match; when they all fit (≤ 20) the list must be complete.
    const got = rows.map((t) => t.id).sort();
    if (got.some((id) => !res.ids!.includes(id))) return fail("H evidence", "a listed row doesn't match");
    if (res.ids.length <= 20 && got.length !== res.ids.length) return fail("H evidence", `listed ${got.length} of ${res.ids.length}`);
  }
  if (res.remark !== undefined) {
    if (!a.text.includes(res.remark)) return fail("H evidence", "remark not shown");
    if (!a.text.includes(money(res.amountMinor!))) return fail("H evidence", "amount not shown");
  }
  // Language: the localised answer families must answer in the user's language (figures already checked above).
  if (["bn-latn", "bn", "ms"].includes(e.language) && ["total", "total_category", "total_merchant", "count", "frequency"].includes(e.kind) && a.status === "answered" && answerLanguage(a.text) !== e.language)
    return fail("I language", `answered in ${answerLanguage(a.text)}`);
  return { ...base, ok: true };
}

export function percentile(xs: number[], p: number) {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))];
}

export function summarise(outcomes: Outcome[]) {
  const by = (f: (o: Outcome) => string) => {
    const m: Record<string, { ok: number; n: number }> = {};
    for (const o of outcomes) { const k = f(o); m[k] ??= { ok: 0, n: 0 }; m[k].n++; if (o.ok) m[k].ok++; }
    return Object.fromEntries(Object.entries(m).sort().map(([k, v]) => [k, `${v.ok}/${v.n} (${((100 * v.ok) / v.n).toFixed(1)}%)`]));
  };
  const stages: Record<string, number> = {};
  for (const o of outcomes) if (!o.ok && o.stage) stages[o.stage] = (stages[o.stage] ?? 0) + 1;
  const ok = outcomes.filter((o) => o.ok).length;
  return {
    accuracy: `${ok}/${outcomes.length} (${((100 * ok) / Math.max(1, outcomes.length)).toFixed(1)}%)`,
    rate: ok / Math.max(1, outcomes.length),
    byLanguage: by((o) => o.example.language), byKind: by((o) => o.example.kind), failuresByStage: stages,
    security: by((o) => (o.example.security ? "security" : "other")).security,
    latencyMs: { p50: +percentile(outcomes.map((o) => o.ms), 50).toFixed(2), p95: +percentile(outcomes.map((o) => o.ms), 95).toFixed(2), p99: +percentile(outcomes.map((o) => o.ms), 99).toFixed(2) },
    toolMs: { p50: percentile(outcomes.map((o) => o.toolMs), 50), p95: percentile(outcomes.map((o) => o.toolMs), 95) },
  };
}

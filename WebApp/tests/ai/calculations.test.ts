// Calculation correctness (quality brief §14–§27, §50–§53). Three layers:
//   1. the formulas themselves (calc.ts) on exact known values;
//   2. property tests: random datasets (seeded, reproducible) checked against an INDEPENDENT oracle written here —
//      totals, counts, groups, max/min, comparisons, weekly summary, evidence lists;
//   3. date boundaries in the user's time zone, and the invariant guard that withholds inconsistent answers.
import { describe, expect, it } from "vitest";
import { averageMinor, CalculationError, maxBy, percentChange, roundHalfAway, sharePercent, totalMinor } from "@/lib/ai/calc";
import { invariantViolations } from "@/lib/ai/invariants";
import { executeTool } from "@/lib/ai/registry";
import { MemoryTenantStore } from "@/lib/ai/repository";
import { toMinor, type CalculateData, type CompareData, type WeeklySummaryData } from "@/lib/ai/tools";
import type { CategoryId, Expense, PaymentChannelId } from "@/lib/domain/types";
import { USER_A, ctx, exp, share } from "./fixtures";

describe("formulas (calc.ts)", () => {
  it("10 + 20 + 30 = 60, exactly", () => expect(totalMinor([1000, 2000, 3000])).toBe(6000));
  it("60 → 86.45 is +44.1% ((86.45 − 60) / 60 × 100 = 44.083…)", () => expect(percentChange(8645, 6000)).toBe(44.1));
  it("100 → 75 is −25%", () => expect(percentChange(7500, 10000)).toBe(-25));
  it("0 → 50 has no percentage (no Infinity / NaN)", () => expect(percentChange(5000, 0)).toBeNull());
  it("100 → 100 is 0%", () => expect(percentChange(10000, 10000)).toBe(0));
  it("rounds half away from zero, symmetrically", () => {
    expect(roundHalfAway(2.5)).toBe(3);
    expect(roundHalfAway(-2.5)).toBe(-3);
    expect(percentChange(10005, 10000)).toBe(0.1); // +0.05% → 0.1
    expect(percentChange(9995, 10000)).toBe(-0.1); // −0.05% → −0.1 (Math.round would give −0)
  });
  it("major → minor units without float drift", () => {
    expect(toMinor(10.5)).toBe(1050);
    expect(toMinor(1.005)).toBe(101);
    expect(toMinor(0.1 + 0.2)).toBe(30);
    expect(toMinor(86.45)).toBe(8645);
  });
  it("averages and shares round once, at the end", () => {
    expect(averageMinor([1000, 2000, 2001])).toBe(1667);
    expect(averageMinor([])).toBeNull();
    expect(sharePercent(1, 3)).toBe(33.3);
    expect(sharePercent(0, 0)).toBe(0);
  });
  it("a corrupt (non-integer) amount stops the calculation instead of corrupting a total", () => {
    expect(() => totalMinor([1000, 10.5])).toThrow(CalculationError);
    expect(() => totalMinor([Number.NaN])).toThrow(CalculationError);
  });
  it("max picks the actual maximum, first on ties", () => {
    expect(maxBy([{ v: 3 }, { v: 9 }, { v: 9 }, { v: 1 }], (x) => x.v)).toEqual({ v: 9 });
    expect(maxBy([], (x: number) => x)).toBeNull();
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Property tests against an independent oracle
// ---------------------------------------------------------------------------------------------------------------
function rng(seed: number) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}
const CATS: CategoryId[] = ["Food", "Groceries", "Transport", "Shopping", "Bills", "Health"];
const MERCHANTS = ["Starbucks", "Shopee", "Shopee Food", "Grab", "Jaya Grocer", "Tealive", "Unifi", "Watsons"];
const ACCOUNTS = ["Maybank", "CIMB", "Touch 'n Go", "Cash"];
const CHANNELS: PaymentChannelId[] = ["APPLE_PAY", "CARD", "QR_PAYMENT", "CASH", "UNKNOWN"];

/** Malaysia is UTC+8 all year (no DST): the oracle computes local days independently of the app's code. */
const myDay = (iso: string) => new Date(new Date(iso).getTime() + 8 * 3_600_000).toISOString().slice(0, 10);

function randomWorld(seed: number) {
  const r = rng(seed);
  const pick = <T,>(xs: T[]) => xs[Math.floor(r() * xs.length)];
  const expenses: Expense[] = [];
  const shares = [];
  for (let i = 0; i < 300; i++) {
    const day = new Date(Date.UTC(2026, 6, 1) + Math.floor(r() * 99) * 86_400_000).toISOString().slice(0, 10);
    const hh = String(Math.floor(r() * 24)).padStart(2, "0"), mm = String(Math.floor(r() * 60)).padStart(2, "0");
    const amount = Math.round((1 + r() * 300) * 100) / 100;
    const e = exp({ merchant: pick(MERCHANTS), amount, date: day, time: `${hh}:${mm}`, category: pick(CATS), channel: pick(CHANNELS), account: pick(ACCOUNTS), paidByMe: r() > 0.15 });
    expenses.push(e);
    if (r() < 0.2) { // a split: my share + someone else's (exact sen, adding up)
      const mine = Math.floor(e.amountMinor * r());
      shares.push(share(e, { isMe: true, amount: mine / 100 }), share(e, { isMe: false, amount: (e.amountMinor - mine) / 100 }));
    }
  }
  return { expenses, shares, store: new MemoryTenantStore().add(USER_A, { expenses, shares }) };
}

/** The app's spending rule, re-implemented independently: full amount if I paid and it isn't split, else my share. */
function oracleSpend(e: Expense, shares: { expenseId: string; isMe: boolean; amountMinor: number }[]) {
  const mine = shares.filter((s) => s.expenseId === e.id);
  if (e.paidByMe && !mine.length) return e.amountMinor;
  if (e.paidByMe) return e.amountMinor;
  return mine.length ? mine.find((s) => s.isMe)?.amountMinor ?? 0 : e.amountMinor;
}

describe.each([11, 42, 2026])("property tests — random dataset seed %i", (seed) => {
  const { expenses, shares, store } = randomWorld(seed);
  const repo = store.forUser(USER_A);
  const c = ctx(USER_A, "2026-10-07");
  const rows = (from: string, to: string, f: (e: Expense) => boolean = () => true) =>
    expenses.filter((e) => myDay(e.date) >= from && myDay(e.date) <= to && f(e));
  const spendOf = (list: Expense[]) => list.reduce((t, e) => t + oracleSpend(e, shares), 0);

  const FILTERS: [string, Record<string, unknown>, (e: Expense) => boolean][] = [
    ["all spending", {}, () => true],
    ["category Food", { category: "Food" }, (e) => e.category === "Food"],
    ["merchant Shopee (whole word: Shopee + Shopee Food)", { merchant: "Shopee" }, (e) => e.merchant === "Shopee" || e.merchant === "Shopee Food"],
    ["funding account CIMB", { fundingAccount: "CIMB" }, (e) => e.fundingAccount === "CIMB"],
    ["payment channel Card", { paymentChannel: "CARD" }, (e) => e.paymentChannel === "CARD"],
    ["amount RM50–RM120", { amountMin: 50, amountMax: 120 }, (e) => e.amountMinor >= 5000 && e.amountMinor <= 12000],
  ];
  const PERIODS: [string, string][] = [["2026-07-01", "2026-07-31"], ["2026-08-15", "2026-09-14"], ["2026-10-01", "2026-10-07"], ["2026-07-01", "2026-10-07"]];

  it.each(FILTERS)("sum / count / max / min / evidence — %s", async (_n, filter, keep) => {
    for (const [from, to] of PERIODS) {
      const expected = rows(from, to, keep);
      for (const operation of ["sum", "count", "max", "min"] as const) {
        const r = await executeTool("calculate_spending", { operation, period: { from, to }, ...filter }, c, repo);
        expect(r.result.ok).toBe(true);
        const d = (r.result as { data: CalculateData }).data;
        const res = d.results.find((x) => x.currency === "RM");
        if (!expected.length) { expect(res).toBeUndefined(); continue; }
        expect(res!.transactionCount).toBe(expected.length);
        if (operation === "sum") {
          expect(res!.valueMinor).toBe(spendOf(expected));
          // evidence list = exactly the dataset behind the headline
          if (expected.length <= 100) {
            expect(res!.transactions!.map((t) => t.id).sort()).toEqual(expected.map((e) => e.id).sort());
            expect(res!.transactions!.reduce((t, x) => t + x.spendMinor, 0)).toBe(res!.valueMinor);
          }
        }
        if (operation === "max") expect(res!.valueMinor).toBe(Math.max(...expected.map((e) => oracleSpend(e, shares))));
        if (operation === "min") expect(res!.valueMinor).toBe(Math.min(...expected.map((e) => oracleSpend(e, shares))));
      }
    }
  });

  it.each(["category", "merchant", "funding_account", "payment_channel", "day"] as const)("groups add up to the total — by %s", async (groupBy) => {
    for (const [from, to] of PERIODS) {
      const r = await executeTool("calculate_spending", { operation: "sum", groupBy, period: { from, to } }, c, repo);
      const res = (r.result as { data: CalculateData }).data.results[0];
      const expected = rows(from, to);
      expect(res.valueMinor).toBe(spendOf(expected));
      if (res.groupsComplete) {
        expect(res.groups!.reduce((t, g) => t + g.valueMinor, 0)).toBe(res.valueMinor);
        expect(res.groups!.reduce((t, g) => t + g.count, 0)).toBe(expected.length);
      }
      if (groupBy === "category") for (const g of res.groups!) expect(g.valueMinor).toBe(spendOf(expected.filter((e) => e.category === g.key)));
      if (groupBy === "funding_account") for (const g of res.groups!) expect(g.valueMinor).toBe(spendOf(expected.filter((e) => e.fundingAccount === g.label)));
      if (groupBy === "payment_channel") for (const g of res.groups!) expect(g.valueMinor).toBe(spendOf(expected.filter((e) => e.paymentChannel === g.key)));
    }
  });

  it("comparisons: difference = current − previous, percentage = formula", async () => {
    const cases: [Record<string, unknown>, (e: Expense) => boolean][] = [
      [{}, () => true], [{ category: "Shopping" }, (e) => e.category === "Shopping"], [{ merchant: "Grab" }, (e) => e.merchant === "Grab"],
    ];
    for (const [filter, keep] of cases) {
      const r = await executeTool("compare_periods", { periodA: { from: "2026-09-01", to: "2026-09-30" }, periodB: { from: "2026-08-01", to: "2026-08-31" }, ...filter }, c, repo);
      const d = (r.result as { data: CompareData }).data;
      const a = spendOf(rows("2026-09-01", "2026-09-30", keep)), b = spendOf(rows("2026-08-01", "2026-08-31", keep));
      const res = d.results.find((x) => x.currency === "RM")!;
      expect([res.aMinor, res.bMinor, res.diffMinor]).toEqual([a, b, a - b]);
      expect(res.pctChange).toBe(b === 0 ? null : Math.sign(a - b) * Math.round(Math.abs(((a - b) * 1000) / b)) / 10);
    }
  });

  it("weekly summary: total = Σ days = Σ categories = Σ evidence; largest = max", async () => {
    const r = await executeTool("get_weekly_summary", { weekOf: "2026-09-16" }, c, repo);
    const d = (r.result as { data: WeeklySummaryData }).data;
    const expected = rows("2026-09-14", "2026-09-20");
    expect(d.totalMinor).toBe(spendOf(expected));
    expect(d.count).toBe(expected.length);
    expect(d.byDay.reduce((t, x) => t + x.valueMinor, 0)).toBe(d.totalMinor);
    expect(d.categories.reduce((t, x) => t + x.valueMinor, 0)).toBe(d.totalMinor);
    expect(d.transactions.reduce((t, x) => t + x.spendMinor, 0)).toBe(d.totalMinor);
    if (expected.length) expect(d.largestTransaction!.spendMinor).toBe(Math.max(...expected.map((e) => oracleSpend(e, shares))));
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Date boundaries (Malaysia, UTC+8) — every transaction in exactly one period
// ---------------------------------------------------------------------------------------------------------------
describe("date boundaries in the user's time zone", () => {
  const at = (iso: string, merchant: string) => ({ ...exp({ merchant, amount: 10, date: "2026-01-01" }), date: new Date(iso).toISOString() });
  const store = new MemoryTenantStore().add(USER_A, {
    expenses: [
      at("2026-09-30T23:59:59.999+08:00", "LastMomentSep"), at("2026-10-01T00:00:00+08:00", "FirstMomentOct"),
      at("2026-09-30T16:30:00Z", "UtcStillSep30ButMyOct1"), // 00:30 on 1 Oct in Malaysia
      at("2025-12-31T23:59:00+08:00", "NewYearsEve"), at("2026-01-01T00:00:00+08:00", "NewYearsDay"),
      at("2026-10-04T23:59:59+08:00", "SundayNight"), at("2026-10-05T00:00:00+08:00", "MondayMidnight"),
      at("2026-10-11T23:59:59+08:00", "NextSundayNight"), at("2026-10-12T00:00:00+08:00", "NextMondayMidnight"),
    ],
  });
  const names = async (period: unknown) => {
    const r = await executeTool("search_transactions", { period, limit: 100 }, ctx(USER_A, "2026-10-07"), store.forUser(USER_A));
    return (r.result as { data: { transactions: { merchant: string }[] } }).data.transactions.map((t) => t.merchant).sort();
  };
  it("month boundary: 23:59:59.999 is September, 00:00:00 is October", async () => {
    expect(await names({ from: "2026-09-01", to: "2026-09-30" })).toEqual(["LastMomentSep"]);
    expect(await names({ from: "2026-10-01", to: "2026-10-31" })).toEqual(["FirstMomentOct", "MondayMidnight", "NextMondayMidnight", "NextSundayNight", "SundayNight", "UtcStillSep30ButMyOct1"]);
  });
  it("a payment at 00:30 Malaysian time on 1 Oct (still 30 Sep in UTC) is October", async () => {
    expect(await names({ from: "2026-10-01", to: "2026-10-01" })).toEqual(["FirstMomentOct", "UtcStillSep30ButMyOct1"]);
  });
  it("year boundary", async () => {
    expect(await names({ from: "2025-12-31", to: "2025-12-31" })).toEqual(["NewYearsEve"]);
    expect(await names({ from: "2026-01-01", to: "2026-01-01" })).toEqual(["NewYearsDay"]);
  });
  it("this week = Monday 00:00 to Sunday 23:59:59 (Mon 5 – Sun 11 Oct 2026)", async () => {
    expect(await names({ preset: "this_week" })).toEqual(["MondayMidnight", "NextSundayNight"]);
    // last week = Mon 28 Sep – Sun 4 Oct, which spans the month boundary
    expect(await names({ preset: "last_week" })).toEqual(["FirstMomentOct", "LastMomentSep", "SundayNight", "UtcStillSep30ButMyOct1"]);
  });
  it("adjacent periods never share or lose a transaction", async () => {
    const sep = await names({ from: "2026-09-01", to: "2026-09-30" }), oct = await names({ from: "2026-10-01", to: "2026-10-31" });
    const both = await names({ from: "2026-09-01", to: "2026-10-31" });
    expect([...sep, ...oct].sort()).toEqual(both);
    expect(sep.filter((n) => oct.includes(n))).toEqual([]);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// Invariant guard: an inconsistent result is withheld
// ---------------------------------------------------------------------------------------------------------------
describe("answer / evidence invariants", () => {
  it("flags a total that doesn't match its transactions, groups, difference or percentage", () => {
    const t = (spendMinor: number) => ({ spendMinor }) as never;
    expect(invariantViolations("calculate_spending", { operation: "sum", results: [{ currency: "RM", transactionCount: 2, valueMinor: 5000, transactions: [t(1000), t(2000)] }] })).toEqual(["total vs listed transactions: 5000 ≠ 3000"]);
    expect(invariantViolations("calculate_spending", { operation: "sum", results: [{ currency: "RM", transactionCount: 2, valueMinor: 3000, groupsComplete: true, groups: [{ valueMinor: 1000, count: 1 }, { valueMinor: 1500, count: 1 }] }] })).toEqual(["total vs groups: 3000 ≠ 2500"]);
    expect(invariantViolations("compare_periods", { results: [{ aMinor: 8645, bMinor: 6000, diffMinor: 2645, pctChange: 44, contributions: [] }] })).toEqual(["percentage: 44 ≠ 44.1"]);
    expect(invariantViolations("compare_periods", { results: [{ aMinor: 100, bMinor: 50, diffMinor: 60, pctChange: 100, contributions: [] }] })).toEqual(["difference: 60 ≠ 50"]);
    expect(invariantViolations("calculate_spending", { operation: "max", results: [{ currency: "RM", transactionCount: 2, valueMinor: 900, transaction: t(900), transactions: [t(900), t(1200)] }] })).toEqual(["max vs dataset: 900 ≠ 1200"]);
  });
  it("consistent results pass", () => {
    expect(invariantViolations("compare_periods", { results: [{ aMinor: 8645, bMinor: 6000, diffMinor: 2645, pctChange: 44.1, contributions: [{ label: "Food", aMinor: 8645, bMinor: 6000, diffMinor: 2645 }] }] })).toEqual([]);
  });
  it("a corrupt stored amount is reported as an error, never as a total", async () => {
    const bad = { ...exp({ merchant: "Glitch", amount: 10, date: "2026-10-06" }), amountMinor: 10.5 };
    const store = new MemoryTenantStore().add(USER_A, { expenses: [bad] });
    const r = await executeTool("calculate_spending", { operation: "sum", period: { preset: "this_week" } }, ctx(), store.forUser(USER_A));
    expect(r.result.ok).toBe(false);
  });
});

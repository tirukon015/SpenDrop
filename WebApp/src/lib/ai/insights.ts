// get_spending_insights: the user's spending compared with their OWN normal pattern — never with other users.
// "Normal" = the average of the same days in the previous months (or weeks) since they started recording, so an
// in-progress month is never compared with whole months. Everything is calculated here, deterministically; the
// composer only reports changes that pass the thresholds in config.ts (no insight is invented to sound smart).
import type { CategoryId } from "@/lib/domain/types";
import { averageMinor, perDayMinor } from "./calc";
import { INSIGHTS, UNUSUAL } from "./config";
import type { FinanceRepository } from "./repository";
import {
  accountNameMap, appliedRules, applyFilters, byCurrency, currencyKey, describeFilters, evidence, groupRows, loadRows, median, pctChange,
  periodInfo, run, sum, toCard, type AppliedRule, type Row,
} from "./tools";
import { addDays, addMonths, daysBetween, daysInMonth, presetSpan, startOfMonth, startOfWeek, weekdayIndex, type DateSpan } from "./time";
import type { AiContext, PeriodInfo, ToolResult, TxnCard } from "./types";
import type { PaymentChannelId } from "@/lib/domain/types";

export interface InsightsInput {
  period?: "this_week" | "this_month";
  category?: CategoryId; merchant?: string; fundingAccount?: string; paymentChannel?: PaymentChannelId; paymentChannels?: PaymentChannelId[]; currency?: string;
}

export interface Change { key: string; label: string; currentMinor: number; normalMinor: number; diffMinor: number; pctChange: number | null }

export interface InsightsData {
  unit: "week" | "month";
  period: PeriodInfo;
  /** e.g. "the average of the same days in your previous 3 months" */
  normalLabel: string;
  filters: string;
  currency: string;
  enoughHistory: boolean;
  periodsUsed: number;
  currentMinor: number;
  currentCount: number;
  normalMinor: number | null;
  diffMinor: number | null;
  pctChange: number | null;
  /** True when the overall difference passes the thresholds (both % and amount). */
  significant: boolean;
  categoryChanges: Change[];
  merchantChanges: Change[];
  largePurchases: TxnCard[];
  smallAddUps: { label: string; count: number; totalMinor: number }[];
  weekend: { weekendDayMinor: number; weekdayDayMinor: number; weeks: number } | null;
  personalRules: AppliedRule[];
}

const isSignificant = (diff: number, pct: number | null, minDiff: number) => Math.abs(diff) >= minDiff && (pct === null || Math.abs(pct) >= INSIGHTS.minPct);

export async function getSpendingInsights(input: InsightsInput, ctx: AiContext, repo: FinanceRepository): Promise<ToolResult<InsightsData>> {
  return run(async () => {
    const unit = input.period === "this_week" ? "week" : "month";
    const today = ctx.today;
    const start = unit === "week" ? startOfWeek(today) : startOfMonth(today);
    const current: DateSpan = { from: start, to: today };
    const elapsed = daysBetween(start, today);
    const n = unit === "week" ? INSIGHTS.baselineWeeks : INSIGHTS.baselineMonths;
    // The same days in each earlier period (clamped to short months).
    const windows: DateSpan[] = Array.from({ length: n }, (_, i) => {
      if (unit === "week") { const from = addDays(start, -7 * (i + 1)); return { from, to: addDays(from, elapsed) }; }
      const from = startOfMonth(addMonths(start, -(i + 1)));
      const [y, m] = from.split("-").map(Number);
      return { from, to: addDays(from, Math.min(elapsed, daysInMonth(y, m) - 1)) };
    });
    const weekendFrom = addDays(startOfWeek(today), -56);
    const loadFrom = [windows[windows.length - 1].from, weekendFrom].sort()[0];
    const names = await accountNameMap(repo);
    const all = applyFilters(await loadRows(repo, ctx, { from: loadFrom, to: today }), input, names);
    const inSpan = (r: Row, s: DateSpan) => r.localDate >= s.from && r.localDate <= s.to;
    const currency = byCurrency(all.filter((r) => inSpan(r, current)))[0]?.[0] ?? (input.currency ? currencyKey(input.currency) : "RM");
    const rows = all.filter((r) => currencyKey(r.expense.currency) === currency);
    const now = rows.filter((r) => inSpan(r, current));

    // Only periods since the user started recording count towards "normal".
    const perWindow = windows.map((w) => rows.filter((r) => inSpan(r, w)));
    const known = perWindow.reduce((k, list, i) => (list.length ? i + 1 : k), 0);
    const used = perWindow.slice(0, known);
    const enoughHistory = known >= INSIGHTS.minBaselinePeriods;
    const minDiff = unit === "week" ? INSIGHTS.minDiffMinorWeek : INSIGHTS.minDiffMinorMonth;
    const avg = (f: (list: Row[]) => number) => averageMinor(used.map(f)) ?? 0;

    const currentMinor = sum(now);
    const normalMinor = enoughHistory ? avg(sum) : null;
    const diff = normalMinor === null ? null : currentMinor - normalMinor;
    const pct = normalMinor === null ? null : pctChange(currentMinor, normalMinor);

    const changes = (by: "category" | "merchant"): Change[] => {
      if (!enoughHistory) return [];
      const cur = new Map(groupRows(now, by, names).map((g) => [g.key, g]));
      const keys = new Set([...cur.keys(), ...used.flatMap((l) => groupRows(l, by, names).map((g) => g.key))]);
      return [...keys].map((key) => {
        const c = cur.get(key);
        const normal = avg((l) => groupRows(l, by, names).find((g) => g.key === key)?.valueMinor ?? 0);
        const label = c?.label ?? used.flatMap((l) => groupRows(l, by, names)).find((g) => g.key === key)?.label ?? key;
        const currentValue = c?.valueMinor ?? 0;
        return { key, label, currentMinor: currentValue, normalMinor: normal, diffMinor: currentValue - normal, pctChange: pctChange(currentValue, normal) };
      }).filter((x) => isSignificant(x.diffMinor, x.pctChange, minDiff)).sort((a, b) => b.diffMinor - a.diffMinor);
    };

    // Larger than usual for their category (the user's own history in the baseline windows).
    const history = used.flat();
    const largePurchases = enoughHistory ? now.filter((r) => {
      const peers = history.filter((h) => h.category === r.category).map((h) => h.spend);
      if (peers.length < UNUSUAL.minCategorySamples) return false;
      return r.spend >= Math.max(median(peers) * UNUSUAL.largeRatio, UNUSUAL.minLargeMinor) && r.spend > Math.max(...peers);
    }).sort((a, b) => b.spend - a.spend).slice(0, 5).map((r) => toCard(r, ctx)) : [];

    // Small payments that add up (per merchant).
    const smallAddUps = groupRows(now.filter((r) => r.spend < INSIGHTS.smallEachMinor), "merchant", names)
      .filter((g) => g.count >= INSIGHTS.smallCount && g.valueMinor >= INSIGHTS.smallTotalMinor)
      .slice(0, 3).map((g) => ({ label: g.label, count: g.count, totalMinor: g.valueMinor }));

    // Weekend vs weekday, per calendar day, over the last 8 full weeks (only with ≥ 4 weeks of records).
    const weekendSpan: DateSpan = { from: weekendFrom, to: addDays(startOfWeek(today), -1) };
    const recent = rows.filter((r) => inSpan(r, weekendSpan));
    const weeksWithData = new Set(recent.map((r) => startOfWeek(r.localDate))).size;
    let weekend: InsightsData["weekend"] = null;
    if (weeksWithData >= 4) {
      const weeks = 8;
      const weekendDayMinor = perDayMinor(sum(recent.filter((r) => weekdayIndex(r.localDate) >= 5)), weeks * 2);
      const weekdayDayMinor = perDayMinor(sum(recent.filter((r) => weekdayIndex(r.localDate) < 5)), weeks * 5);
      if (weekendDayMinor >= weekdayDayMinor * INSIGHTS.weekendRatio && weekendDayMinor - weekdayDayMinor >= 1_000) weekend = { weekendDayMinor, weekdayDayMinor, weeks };
    }

    const filters = describeFilters(input);
    const data: InsightsData = {
      unit, period: periodInfo(current)!, filters, currency, enoughHistory, periodsUsed: known,
      normalLabel: `the average of the same days in your previous ${known} ${unit}${known === 1 ? "" : "s"}`,
      currentMinor, currentCount: now.length, normalMinor, diffMinor: diff, pctChange: pct,
      significant: diff !== null && isSignificant(diff, pct, minDiff),
      categoryChanges: input.category ? [] : changes("category").slice(0, 5),
      merchantChanges: input.merchant ? [] : changes("merchant").slice(0, 3),
      largePurchases, smallAddUps, weekend: input.category || input.merchant ? null : weekend,
      personalRules: appliedRules(now),
    };
    // Evidence = this period's own transactions (the figure shown); the history used for "normal" is described, not counted.
    return { ok: true, data, evidence: evidence("get_spending_insights", now.length, current, `${filters} vs ${data.normalLabel} (${history.length} earlier transactions)`) };
  });
}

/** The current span of an insights period (for focus / labels). */
export const insightsSpan = (period: InsightsInput["period"], today: string) => presetSpan(period === "this_week" ? "this_week" : "this_month", today);

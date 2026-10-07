// Answer/evidence invariants: every tool result is checked for internal consistency BEFORE it can be shown. If a
// headline number doesn't match the dataset it came from, the answer is withheld (a safe error is shown instead) —
// a wrong financial figure is worse than no figure.
//
//   reported total      == Σ of the transactions / days / categories it is made of
//   reported count      == number of those transactions
//   reported largest    == max of the transactions
//   reported difference == current − comparison
//   reported percentage == ((current − comparison) / comparison) × 100   (calc.percentChange)
import { percentChange, totalMinor } from "./calc";
import type { InsightsData } from "./insights";
import type { CalculateData, CompareData, SearchData, UnusualData, WeeklySummaryData } from "./tools";

type Check = (data: never) => string[];

const eq = (label: string, a: number | null, b: number | null) => (a === b ? [] : [`${label}: ${a} ≠ ${b}`]);
const sumOf = (xs: { valueMinor?: number; spendMinor?: number }[], key: "valueMinor" | "spendMinor") => totalMinor(xs.map((x) => x[key] ?? 0));

const CHECKS: Record<string, Check> = {
  calculate_spending: (d: CalculateData) => d.results.flatMap((r) => {
    const out: string[] = [];
    const listComplete = r.transactions && r.transactions.length === r.transactionCount;
    if (d.operation === "sum") {
      if (listComplete) out.push(...eq("total vs listed transactions", r.valueMinor, sumOf(r.transactions!, "spendMinor")));
      if (r.groups && r.groupsComplete) {
        out.push(...eq("total vs groups", r.valueMinor, sumOf(r.groups, "valueMinor")));
        out.push(...eq("count vs groups", r.transactionCount, r.groups.reduce((t, g) => t + g.count, 0)));
      }
    }
    if (listComplete) out.push(...eq("count vs listed transactions", r.transactionCount, r.transactions!.length));
    // Frequency: never more distinct days than transactions, and exactly the days of the listed transactions.
    if (r.distinctDays !== undefined) {
      if (r.distinctDays > r.transactionCount) out.push(`distinct days ${r.distinctDays} > transactions ${r.transactionCount}`);
      if (listComplete) out.push(...eq("distinct days vs dataset", r.distinctDays, new Set(r.transactions!.map((t) => t.localDate)).size));
    }
    if ((d.operation === "max" || d.operation === "min") && r.transaction) {
      out.push(...eq(`${d.operation} vs its transaction`, r.valueMinor, r.transaction.spendMinor));
      if (listComplete) {
        const spends = r.transactions!.map((t) => t.spendMinor);
        out.push(...eq(`${d.operation} vs dataset`, r.valueMinor, d.operation === "max" ? Math.max(...spends) : Math.min(...spends)));
      }
    }
    return out;
  }),
  compare_periods: (d: CompareData) => d.results.flatMap((r) => [
    ...eq("difference", r.diffMinor, r.aMinor - r.bMinor),
    ...eq("percentage", r.pctChange, percentChange(r.aMinor, r.bMinor)),
    ...r.contributions.flatMap((c) => eq(`contribution ${c.label}`, c.diffMinor, c.aMinor - c.bMinor)),
  ]),
  search_transactions: (d: SearchData) => [
    ...(d.transactions.length > d.total ? [`listed ${d.transactions.length} > total ${d.total}`] : []),
  ],
  get_weekly_summary: (d: WeeklySummaryData) => [
    ...eq("week total vs days", d.totalMinor, sumOf(d.byDay, "valueMinor")),
    ...eq("week total vs categories", d.totalMinor, sumOf(d.categories, "valueMinor")),
    ...eq("week count vs categories", d.count, d.categories.reduce((t, g) => t + g.count, 0)),
    ...(d.transactions.length === d.count ? eq("week total vs listed transactions", d.totalMinor, sumOf(d.transactions, "spendMinor")) : []),
    ...(d.largestTransaction && d.transactions.length === d.count ? eq("largest vs dataset", d.largestTransaction.spendMinor, Math.max(...d.transactions.map((t) => t.spendMinor))) : []),
    ...eq("vs last week difference", d.previousWeek.diffMinor, d.totalMinor - d.previousWeek.totalMinor),
    ...eq("vs last week percentage", d.previousWeek.pctChange, percentChange(d.totalMinor, d.previousWeek.totalMinor)),
    ...(d.fourWeekAverage.averageMinor !== null ? eq("vs 4-week percentage", d.fourWeekAverage.pctChange, percentChange(d.totalMinor, d.fourWeekAverage.averageMinor)) : []),
  ],
  get_spending_insights: (d: InsightsData) => [
    ...(d.normalMinor !== null ? eq("insight difference", d.diffMinor, d.currentMinor - d.normalMinor) : []),
    ...(d.normalMinor !== null ? eq("insight percentage", d.pctChange, percentChange(d.currentMinor, d.normalMinor)) : []),
    ...d.categoryChanges.flatMap((c) => [...eq(`change ${c.label}`, c.diffMinor, c.currentMinor - c.normalMinor), ...eq(`change % ${c.label}`, c.pctChange, percentChange(c.currentMinor, c.normalMinor))]),
  ],
  find_unusual_spending: (d: UnusualData) => d.findings.flatMap((f) =>
    f.kind === "total_above_average" || f.kind === "category_spike" ? eq(`finding ${f.kind}`, f.diffMinor, f.periodMinor - f.expectedMinor) : []),
};

/** Problems found in a tool result (empty = consistent). */
export function invariantViolations(tool: string, data: unknown): string[] {
  const check = CHECKS[tool];
  return check ? check(data as never) : [];
}

"use client";

import { ChartColumn, TrendingDown, TrendingUp } from "lucide-react";
import { useMemo, useState } from "react";
import { useStored } from "@/lib/use-stored";
import { Page, PageHeader } from "@/components/app-shell";
import { BarChart, Donut, ShareList } from "@/components/charts";
import { CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { Card, EmptyState, Field, Input, Segmented, SectionHeader, Select, cx, tintText } from "@/components/ui/primitives";
import {
  averagePerDay, byCategory, byChannel, byFundingAccount, categoryTintOf, channelTintOf, dailySpending, movementBreakdown, paletteTint, previousPeriodTotal, topMerchants, total,
} from "@/lib/domain/analytics";
import { channelInfo, kindInfo, type Tint } from "@/lib/domain/constants";
import { QUICK_DATES, dateRange, dayCount, inRange, type QuickDate } from "@/lib/domain/dates";
import { summary } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";

const CURRENCY = "RM";

function Metric({ title, value, subtitle, tint }: { title: string; value: string; subtitle: string; tint?: Tint }) {
  return (
    <Card className="flex flex-col gap-1">
      <span className="section-header">{title}</span>
      <span className="tabular text-[22px] font-bold" style={tint ? { color: tintText(tint) } : undefined}>{value}</span>
      <span className="text-xs text-label-2">{subtitle}</span>
    </Card>
  );
}

export default function BreakdownPage() {
  const { live } = useData();
  const [view, setView] = useState<"spending" | "cashFlow">("spending");
  const [date, setDate] = useStored<QuickDate>("session", "spendrop-breakdown-date", "thisMonth");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const data = useMemo(() => {
    const now = new Date();
    const range = dateRange(date, now, { from, to });
    const expenses = live.expenses.filter((e) => e.currency === CURRENCY && inRange(e.date, range));
    const movements = live.movements.filter((m) => m.currency === CURRENCY && inRange(m.date, range));
    const oldest = live.expenses.at(-1)?.date;
    const effectiveRange: [Date, Date] = range ?? [oldest ? new Date(oldest) : now, now];
    const spent = total(expenses, live.shares);
    const previous = previousPeriodTotal(live.expenses, live.shares, range, CURRENCY);
    const dailyRange: [Date, Date] = dayCount(effectiveRange) > 92 ? [new Date(effectiveRange[1].getTime() - 89 * 86_400_000), effectiveRange[1]] : effectiveRange;
    // 6-month in/out trend (all records)
    const months: { label: string; inMinor: number; outMinor: number }[] = [];
    for (let i = 5; i >= 0; i--) {
      const start = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const end = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59);
      const flow = summary(
        live.expenses.filter((e) => e.currency === CURRENCY && inRange(e.date, [start, end])), live.shares,
        live.movements.filter((m) => m.currency === CURRENCY && inRange(m.date, [start, end])), CURRENCY);
      months.push({ label: new Intl.DateTimeFormat("en-MY", { month: "short" }).format(start), inMinor: flow.moneyInMinor, outMinor: flow.moneyOutMinor });
    }
    return {
      range, expenses, movements, spent, previous,
      average: averagePerDay(expenses, live.shares, effectiveRange), days: dayCount(effectiveRange),
      daily: dailySpending(expenses, live.shares, dailyRange),
      categories: byCategory(expenses, live.shares), channels: byChannel(expenses, live.shares), funding: byFundingAccount(expenses, live.shares),
      merchants: topMerchants(expenses, live.shares, 5),
      flow: summary(expenses, live.shares, movements, CURRENCY), kinds: movementBreakdown(movements), months,
    };
  }, [live, date, from, to]);

  const label = QUICK_DATES.find((d) => d.id === date)?.label ?? "";
  const change = data.previous !== null && data.previous > 0 ? Math.round(((data.spent - data.previous) / data.previous) * 100) : null;
  const empty = view === "spending" ? data.expenses.length === 0 : data.expenses.length === 0 && data.movements.length === 0;

  return (
    <>
      <PageHeader title="Breakdown" subtitle={label} />
      <Page className="flex flex-col gap-5">
        <div className="flex flex-col gap-3 md:flex-row md:items-end">
          <Segmented label="View" className="md:max-w-xs" value={view} onChange={setView} options={[{ id: "spending", label: "Spending" }, { id: "cashFlow", label: "Cash Flow" }]} />
          <div className="grid flex-1 grid-cols-1 gap-2 sm:grid-cols-3 md:max-w-xl md:ml-auto">
            <Field label="Period" htmlFor="bd-date">
              <Select id="bd-date" value={date} onChange={(e) => setDate(e.target.value as QuickDate)}>{QUICK_DATES.map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}</Select>
            </Field>
            {date === "custom" && (
              <>
                <Field label="From" htmlFor="bd-from"><Input id="bd-from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
                <Field label="To" htmlFor="bd-to"><Input id="bd-to" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
              </>
            )}
          </div>
        </div>

        {empty ? (
          <Card><EmptyState icon={ChartColumn} title="No transactions match current filters" message="Try choosing another period, or add a transaction." /></Card>
        ) : view === "spending" ? (
          <>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
              <Metric title="Total spent" value={formatMoney(data.spent)} subtitle={`${data.expenses.length} transaction${data.expenses.length === 1 ? "" : "s"}`} />
              <Metric title="Average / day" value={formatMoney(data.average)} subtitle={`over ${data.days} day${data.days === 1 ? "" : "s"}`} tint="blue" />
              <Card className="col-span-2 flex flex-col gap-1">
                <span className="section-header">{label} comparison</span>
                {change === null ? <span className="text-sm text-label-2">{data.range ? "No spending in the previous period to compare." : "Choose a period to compare with the one before."}</span> : (
                  <>
                    <span className={cx("flex items-center gap-1.5 text-[22px] font-bold", change > 0 ? "text-orange" : "text-green")}>
                      {change > 0 ? <TrendingUp aria-hidden className="size-5" /> : <TrendingDown aria-hidden className="size-5" />}{Math.abs(change)}% {change > 0 ? "more" : "less"}
                    </span>
                    <span className="text-xs text-label-2">vs {formatMoney(data.previous!)} in the previous period of the same length</span>
                  </>
                )}
              </Card>
            </div>
            <Card>
              <SectionHeader>Daily spending</SectionHeader>
              <BarChart title="Daily spending" data={data.daily.map((d) => ({ label: d.date.toDateString(), shortLabel: String(d.date.getDate()), valueMinor: d.valueMinor }))} />
              {data.days > 92 && <p className="mt-2 text-xs text-label-2">Showing the last 90 days.</p>}
            </Card>
            <div className="grid gap-5 lg:grid-cols-2">
              <Card>
                <SectionHeader>Spending by category</SectionHeader>
                <Donut title="Spending by category" data={data.categories.map((c) => ({ key: c.key, label: c.key, valueMinor: c.valueMinor, tint: categoryTintOf(c.key), icon: CATEGORY_ICONS[c.key], count: c.count }))} />
              </Card>
              <Card>
                <SectionHeader>Spending by funding account</SectionHeader>
                <ShareList data={data.funding.map((f, i) => ({ key: f.key, label: f.key, valueMinor: f.valueMinor, tint: paletteTint(i), count: f.count }))} />
              </Card>
              <Card>
                <SectionHeader>Spending by payment channel</SectionHeader>
                <ShareList data={data.channels.map((c) => ({ key: c.key, label: channelInfo(c.key).label, valueMinor: c.valueMinor, tint: channelTintOf(c.key), icon: CHANNEL_ICONS[c.key], count: c.count }))} />
              </Card>
              <Card>
                <SectionHeader>Top merchants</SectionHeader>
                <ol className="flex flex-col gap-2">
                  {data.merchants.map((m, i) => (
                    <li key={m.key} className="flex items-center gap-3 text-sm">
                      <span className="flex size-6 items-center justify-center rounded-full bg-card-2 text-xs font-semibold">{i + 1}</span>
                      <span className="min-w-0 flex-1 truncate">{m.label} <span className="text-xs text-label-2">· {m.count}</span></span>
                      <span className="tabular font-semibold">{formatMoney(m.valueMinor)}</span>
                    </li>
                  ))}
                </ol>
              </Card>
            </div>
            <p className="px-1 text-xs text-label-2">Spending counts the full amount when you paid and only your share when someone else paid. Amounts in other currencies are not added in.</p>
          </>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
              <Metric title="Money In" value={formatMoney(data.flow.moneyInMinor)} subtitle={label} tint="green" />
              <Metric title="Money Out" value={formatMoney(data.flow.moneyOutMinor)} subtitle="expenses paid + other out" />
              <div className="col-span-2 lg:col-span-1">
                <Metric title="Net Cash Flow" value={(data.flow.netCashFlowMinor >= 0 ? "+" : "") + formatMoney(data.flow.netCashFlowMinor)}
                  subtitle={`Money In − Money Out · spending is shown separately (${formatMoney(data.flow.spendingMinor)})`} tint={data.flow.netCashFlowMinor >= 0 ? "green" : "orange"} />
              </div>
            </div>
            <div className="grid gap-5 lg:grid-cols-2">
              <Card>
                <SectionHeader>Last 6 months</SectionHeader>
                <BarChart title="Money in and out per month" tint="green" secondaryTint="gray" data={data.months.map((m) => ({ label: m.label, valueMinor: m.inMinor, secondaryMinor: m.outMinor }))} />
                <p className="mt-2 flex gap-4 text-xs text-label-2"><span className="flex items-center gap-1"><span className="size-2.5 rounded-sm bg-green" /> Money In</span><span className="flex items-center gap-1"><span className="size-2.5 rounded-sm bg-gray opacity-60" /> Money Out</span> · own transfers excluded</p>
              </Card>
              <Card>
                <SectionHeader>By type</SectionHeader>
                {data.kinds.length === 0 ? <p className="text-sm text-label-2">No money in or out besides expenses in this period.</p> : (
                  <ul className="flex flex-col gap-2 text-sm">
                    {data.kinds.map((k) => (
                      <li key={k.kind} className="flex justify-between gap-3">
                        <span className="text-label-2">{kindInfo(k.kind).label} · {k.count}</span>
                        <span className={cx("tabular font-semibold", kindInfo(k.kind).direction === "in" && "text-green")}>{kindInfo(k.kind).direction === "in" ? "+" : "−"}{formatMoney(k.totalMinor)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </Card>
            </div>
          </>
        )}
      </Page>
    </>
  );
}

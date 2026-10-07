"use client";

import { ArrowLeftRight, CalendarClock, ChartColumn, CloudDownload, Plus, ReceiptText, SunMedium, Users } from "lucide-react";
import Link from "next/link";
import { useMemo } from "react";
import { Page, PageHeader, SyncStatus } from "@/components/app-shell";
import { ShareList } from "@/components/charts";
import { CATEGORY_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { ActivityRow, ExpenseRow } from "@/components/transactions";
import { ButtonLink, Card, Divider, EmptyState, ErrorBanner, ListSkeleton, SectionHeader, Skeleton, cx, tintText, tintVar } from "@/components/ui/primitives";
import { byCategory, byFundingAccount, categoryTintOf, paletteTint } from "@/lib/domain/analytics";
import { buildActivity, defaultFilters } from "@/lib/domain/activity";
import { dateRange, inRange } from "@/lib/domain/dates";
import { personBalances, spendingMinor, summary } from "@/lib/domain/ledger";
import { AnimatedMoney, rise } from "@/components/motion";
import type { Tint } from "@/lib/domain/constants";

const CURRENCY = "RM";

function SummaryCard({ title, amountMinor, icon: Icon, tint, hero, caption, index }: {
  title: string; amountMinor: number; icon: React.ComponentType<{ className?: string }>; tint: Tint; hero?: boolean; caption?: string; index: number;
}) {
  return (
    <Card className={cx("sd-rise flex h-full flex-col gap-2", hero && "md:col-span-2")} style={rise(index)}>
      <div className="flex items-center justify-between">
        <span className="section-header">{title}</span>
        <span aria-hidden style={{ color: tintVar(tint) }}><Icon className="size-4" /></span>
      </div>
      <AnimatedMoney minor={amountMinor} currency={CURRENCY} className={cx("tabular block font-bold tracking-tight", hero ? "text-[34px]" : "text-[22px]")} />
      {caption && <p className="text-xs text-label-2">{caption}</p>}
    </Card>
  );
}

function Metric({ label, minor, sign, tint }: { label: string; minor: number; sign?: boolean; tint?: Tint }) {
  return (
    <div className="flex min-w-0 flex-1 flex-col">
      <span className="text-xs text-label-2">{label}</span>
      <AnimatedMoney minor={minor} sign={sign} className="tabular break-words text-[14px] font-bold leading-tight sm:text-[15px]" style={tint ? { color: tintText(tint) } : undefined} />
    </div>
  );
}

export default function HomePage() {
  const { live, status, error, refresh } = useData();
  const now = useMemo(() => new Date(), []);
  const people = useMemo(() => new Map(live.people.map((p) => [p.id, p])), [live.people]);
  const accounts = useMemo(() => new Map(live.accounts.map((a) => [a.id, a])), [live.accounts]);

  const view = useMemo(() => {
    const rm = live.expenses.filter((e) => e.currency === CURRENCY);
    const sumIn = (range: [Date, Date] | null) => rm.filter((e) => inRange(e.date, range)).reduce((t, e) => t + spendingMinor(e, live.shares.get(e.id)), 0);
    const today = dateRange("today", now), week = dateRange("thisWeek", now), month = dateRange("thisMonth", now);
    const monthExpenses = rm.filter((e) => inRange(e.date, month));
    const monthMovements = live.movements.filter((m) => m.currency === CURRENCY && inRange(m.date, month));
    const balances = personBalances(live.expenses, live.shares, live.movements, CURRENCY);
    let owed = 0, owe = 0;
    for (const value of balances.values()) {
      if (value > 0) owed += value;
      else owe -= value;
    }
    return {
      today: sumIn(today), week: sumIn(week), month: sumIn(month),
      todayExpenses: rm.filter((e) => inRange(e.date, today)),
      flow: monthMovements.length ? summary(monthExpenses, live.shares, monthMovements, CURRENCY) : null,
      owed, owe,
      categories: byCategory(monthExpenses, live.shares),
      funding: byFundingAccount(monthExpenses, live.shares),
      recent: buildActivity(live.expenses, live.shares, live.movements, live.people, defaultFilters(), now).slice(0, 8),
    };
  }, [live, now]);

  const loading = status === "loading" && live.expenses.length === 0 && live.movements.length === 0;
  const empty = !loading && live.expenses.length === 0 && live.movements.length === 0;
  const monthName = new Intl.DateTimeFormat("en-MY", { month: "long", year: "numeric" }).format(now);

  return (
    <>
      <PageHeader title="Home" subtitle={monthName} actions={<span className="md:hidden"><SyncStatus compact /></span>} />
      <Page className="flex flex-col gap-5">
        {error && <ErrorBanner message={error} onRetry={refresh} />}

        {loading ? (
          <div className="grid gap-3 md:grid-cols-4">
            {[0, 1, 2].map((i) => <Card key={i} className={cx(i === 0 && "md:col-span-2")}><Skeleton className="mb-3 w-20" /><Skeleton className="h-7 w-32" /></Card>)}
          </div>
        ) : empty ? (
          <Card>
            <EmptyState
              icon={ReceiptText}
              title="No transactions yet"
              message="Add your first expense, or bring in the data from SpenDrop on your iPhone."
              action={
                <div className="flex flex-wrap justify-center gap-2">
                  <ButtonLink href="/add"><Plus aria-hidden className="size-4" /> Add Transaction</ButtonLink>
                  <ButtonLink href="/more/import" variant="tinted"><CloudDownload aria-hidden className="size-4" /> Bring in iPhone data</ButtonLink>
                </div>
              }
            />
          </Card>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
              <div className="col-span-2"><SummaryCard hero index={0} title="Today" amountMinor={view.today} icon={SunMedium} tint="orange"
                caption={`${view.todayExpenses.length} transaction${view.todayExpenses.length === 1 ? "" : "s"}`} /></div>
              <SummaryCard index={1} title="This Week" amountMinor={view.week} icon={CalendarClock} tint="blue" />
              <SummaryCard index={2} title="This Month" amountMinor={view.month} icon={ChartColumn} tint="green" />
            </div>

            {(view.flow || view.owed !== 0 || view.owe !== 0) && (
              <div className="sd-rise grid gap-3 md:grid-cols-2" style={rise(3)}>
                {view.flow && (
                  <Card aria-label="Cash flow this month">
                    <div className="mb-2 flex items-center justify-between"><span className="section-header">Cash Flow · This Month</span><ArrowLeftRight aria-hidden className="size-4 text-teal" /></div>
                    <div className="flex gap-3">
                      <Metric label="Money In" minor={view.flow.moneyInMinor} tint="green" />
                      <Metric label="Money Out" minor={view.flow.moneyOutMinor} />
                      <Metric label="Net" minor={view.flow.netCashFlowMinor} sign tint={view.flow.netCashFlowMinor >= 0 ? "green" : "orange"} />
                    </div>
                  </Card>
                )}
                {(view.owed !== 0 || view.owe !== 0) && (
                  <Link href="/paybook" className="block rounded-card focus-visible:outline-2">
                    <Card aria-label="PayBook balances" className="sd-lift h-full hover:bg-card-2">
                      <div className="mb-2 flex items-center justify-between"><span className="section-header">Balances</span><Users aria-hidden className="size-4 text-purple" /></div>
                      <div className="flex gap-3">
                        {view.owed !== 0 && <Metric label="Owed to you" minor={view.owed} tint="green" />}
                        {view.owe !== 0 && <Metric label="You owe" minor={view.owe} tint="orange" />}
                      </div>
                    </Card>
                  </Link>
                )}
              </div>
            )}

            <div className="sd-rise grid gap-5 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]" style={rise(4)}>
              <div className="flex flex-col gap-5">
                <section aria-labelledby="today-heading">
                  <SectionHeader id="today-heading" action={<span className="text-xs text-label-2">{view.todayExpenses.length} transactions</span>}>Today&apos;s Expenses</SectionHeader>
                  <Card className="overflow-hidden p-0">
                    {view.todayExpenses.length === 0 ? (
                      <EmptyState icon={ReceiptText} title="No expenses recorded today" message="Add a cash expense or scan a payment screenshot."
                        action={<ButtonLink href="/add" variant="tinted"><Plus aria-hidden className="size-4" /> Add Expense</ButtonLink>} />
                    ) : view.todayExpenses.map((e, i) => (
                      <div key={e.id} className="sd-row" style={rise(i + 4)}>{i > 0 && <Divider inset={72} />}<ExpenseRow expense={e} shares={live.shares.get(e.id) ?? []} people={people} compact /></div>
                    ))}
                  </Card>
                </section>
                <section aria-labelledby="recent-heading">
                  <SectionHeader id="recent-heading" action={<Link href="/transactions" className="text-sm font-medium text-[var(--sd-accent-text)]">See All</Link>}>Recent Activity</SectionHeader>
                  <Card className="overflow-hidden p-0">
                    {status === "loading" ? <ListSkeleton rows={4} /> : view.recent.map((item, i) => (
                      <div key={item.id} className="sd-row" style={rise(i + 5)}>{i > 0 && <Divider inset={72} />}<ActivityRow item={item} people={people} accounts={accounts} /></div>
                    ))}
                  </Card>
                </section>
              </div>
              <div className="flex flex-col gap-5">
                <section aria-labelledby="cat-heading">
                  <SectionHeader id="cat-heading" action={<Link href="/breakdown" className="text-sm font-medium text-[var(--sd-accent-text)]">Breakdown</Link>}>This Month by Category</SectionHeader>
                  <Card>
                    {view.categories.length === 0 ? <p className="py-4 text-center text-sm text-label-2">No spending this month yet.</p> : (
                      <ShareList limit={6} data={view.categories.map((c) => ({ key: c.key, label: c.key, valueMinor: c.valueMinor, tint: categoryTintOf(c.key), icon: CATEGORY_ICONS[c.key], count: c.count }))} />
                    )}
                  </Card>
                </section>
                {view.funding.length > 0 && (
                  <section aria-labelledby="funding-heading">
                    <SectionHeader id="funding-heading">This Month by Funding Account</SectionHeader>
                    <Card>
                      <ShareList limit={5} data={view.funding.map((f, i) => ({ key: f.key, label: f.key, valueMinor: f.valueMinor, tint: paletteTint(i), count: f.count }))} />
                    </Card>
                  </section>
                )}
              </div>
            </div>
          </>
        )}
      </Page>
    </>
  );
}

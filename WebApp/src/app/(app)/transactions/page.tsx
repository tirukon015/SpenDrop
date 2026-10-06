"use client";

import { Plus, ReceiptText, Search, SlidersHorizontal } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { useStored } from "@/lib/use-stored";
import { Page, PageHeader } from "@/components/app-shell";
import { FilterPanel } from "@/components/filter-panel";
import { CATEGORY_ICONS, movementIcon } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { ActivityRow, ChannelBadge } from "@/components/transactions";
import { Button, ButtonLink, Card, Divider, EmptyState, ErrorBanner, IconTile, Input, ListSkeleton, Segmented, Sheet, cx, tintText } from "@/components/ui/primitives";
import { ACTIVITY_TYPES, activeFilterCount, buildActivity, defaultFilters, type ActivityFilters, type ActivityItem } from "@/lib/domain/activity";
import { categoryTint, kindInfo } from "@/lib/domain/constants";
import { formatDate, dayKey, QUICK_DATES } from "@/lib/domain/dates";
import { formatMoney } from "@/lib/domain/money";

const PAGE_SIZE = 60;
const STORAGE_KEY = "spendrop-tx-filters";

function dayTitle(key: string) {
  const today = dayKey(new Date().toISOString());
  const yesterday = dayKey(new Date(Date.now() - 86_400_000).toISOString());
  if (key === today) return "Today";
  if (key === yesterday) return "Yesterday";
  return formatDate(key + "T12:00:00", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
}

export default function TransactionsPage() {
  const { live, status, error, refresh } = useData();
  const [filters, storeFilters] = useStored<ActivityFilters>("session", STORAGE_KEY, defaultFilters());
  const [showFilters, setShowFilters] = useState(false);
  const [limit, setLimit] = useState(PAGE_SIZE);
  const setFilters = (next: ActivityFilters) => { storeFilters(next); setLimit(PAGE_SIZE); };

  const people = useMemo(() => new Map(live.people.map((p) => [p.id, p])), [live.people]);
  const accounts = useMemo(() => new Map(live.accounts.map((a) => [a.id, a])), [live.accounts]);
  const fundingAccounts = useMemo(() => [...new Set(live.expenses.map((e) => e.fundingAccount).filter(Boolean))].sort(), [live.expenses]);
  const items = useMemo(() => buildActivity(live.expenses, live.shares, live.movements, live.people, filters), [live, filters]);
  const shown = items.slice(0, limit);
  const groups = useMemo(() => {
    const result: { key: string; items: ActivityItem[] }[] = [];
    for (const item of shown) {
      const key = filters.sort === "newest" || filters.sort === "oldest" ? dayKey(item.date) : "results";
      if (result.at(-1)?.key !== key) result.push({ key, items: [] });
      result.at(-1)!.items.push(item);
    }
    return result;
  }, [shown, filters.sort]);
  const count = activeFilterCount(filters);
  const nothingAtAll = live.expenses.length === 0 && live.movements.length === 0;
  const dateLabel = QUICK_DATES.find((d) => d.id === filters.date)?.label;

  return (
    <>
      <PageHeader title="Transactions" subtitle={`${items.length} record${items.length === 1 ? "" : "s"}${filters.date !== "all" ? ` · ${dateLabel}` : ""}`}
        actions={<ButtonLink href="/add" className="max-md:hidden"><Plus aria-hidden className="size-4" /> Add</ButtonLink>} />
      <Page className="flex gap-6">
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {error && <ErrorBanner message={error} onRetry={refresh} />}
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search aria-hidden className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-label-2" />
              <label htmlFor="tx-search" className="sr-only">Search transactions</label>
              <Input id="tx-search" type="search" placeholder="Search merchant, notes, people, reference…" className="pl-10"
                value={filters.search} onChange={(e) => setFilters({ ...filters, search: e.target.value })} />
            </div>
            <Button variant="secondary" className="relative bg-card shadow-card xl:hidden" onClick={() => setShowFilters(true)} aria-label={`Filters${count ? ` (${count} active)` : ""}`}>
              <SlidersHorizontal aria-hidden className="size-4" /> <span className="max-sm:sr-only">Filters</span>
              {count > 0 && <span className="absolute -right-1 -top-1 flex size-5 items-center justify-center rounded-full bg-[var(--sd-accent-fill)] text-[11px] text-white">{count}</span>}
            </Button>
          </div>
          <div className="-mx-4 overflow-x-auto px-4 md:mx-0 md:px-0">
            <Segmented label="Show" value={filters.type} onChange={(type) => setFilters({ ...filters, type })} options={ACTIVITY_TYPES} className="min-w-[520px]" size="sm" />
          </div>

          {status === "loading" && nothingAtAll ? (
            <Card className="p-0"><ListSkeleton rows={8} /></Card>
          ) : nothingAtAll ? (
            <Card><EmptyState icon={ReceiptText} title="No expenses recorded" message="Add your first expense, or bring in your iPhone data from More → Bring in iPhone data."
              action={<ButtonLink href="/add"><Plus aria-hidden className="size-4" /> Add Expense</ButtonLink>} /></Card>
          ) : items.length === 0 ? (
            <Card><EmptyState icon={Search} title="Nothing matches" message="Try another search, date range or filter."
              action={<Button variant="tinted" onClick={() => setFilters(defaultFilters())}>Clear search and filters</Button>} /></Card>
          ) : (
            <>
              {/* Phones / tablets: rows grouped by day */}
              <div className="flex flex-col gap-4 lg:hidden">
                {groups.map((g) => (
                  <section key={g.key} aria-label={g.key === "results" ? "Results" : dayTitle(g.key)}>
                    {g.key !== "results" && <h2 className="section-header mb-1.5 px-1">{dayTitle(g.key)}</h2>}
                    <Card className="overflow-hidden p-0">
                      {g.items.map((item, i) => <div key={item.id}>{i > 0 && <Divider inset={72} />}<ActivityRow item={item} people={people} accounts={accounts} /></div>)}
                    </Card>
                  </section>
                ))}
              </div>
              {/* Desktop: table with richer columns */}
              <Card className="hidden overflow-hidden p-0 lg:block">
                <table className="w-full text-sm">
                  <caption className="sr-only">Transactions</caption>
                  <thead>
                    <tr className="border-b border-separator text-left text-xs text-label-2">
                      <th scope="col" className="py-3 pl-4 font-semibold">Date</th>
                      <th scope="col" className="py-3 font-semibold">Merchant / Type</th>
                      <th scope="col" className="py-3 font-semibold">Category</th>
                      <th scope="col" className="py-3 font-semibold">Funding account</th>
                      <th scope="col" className="py-3 font-semibold">Channel</th>
                      <th scope="col" className="py-3 pr-4 text-right font-semibold">Amount</th>
                    </tr>
                  </thead>
                  <tbody>
                    {shown.map((item) => {
                      if (item.type === "expense") {
                        const e = item.expense;
                        const shared = item.shares.length > 0;
                        return (
                          <tr key={item.id} className="group relative border-b border-separator last:border-0 hover:bg-card-2">
                            <td className="whitespace-nowrap py-2.5 pl-4 text-label-2">{formatDate(e.date, { day: "numeric", month: "short", year: "numeric" })}</td>
                            <td className="max-w-[280px] py-2.5">
                              <Link href={`/transactions/${e.id}`} className="flex items-center gap-2.5 font-semibold after:absolute after:inset-0">
                                <IconTile icon={CATEGORY_ICONS[e.category]} tint={categoryTint(e.category)} size={32} />
                                <span className="truncate">{e.merchant}</span>
                                {shared && <span className="rounded-full bg-[color-mix(in_srgb,var(--sd-blue)_14%,transparent)] px-1.5 text-[11px] text-blue">Shared · {item.shares.length}</span>}
                              </Link>
                            </td>
                            <td className="py-2.5" style={{ color: tintText(categoryTint(e.category)) }}>{e.category}</td>
                            <td className="py-2.5">{e.fundingAccount}</td>
                            <td className="py-2.5"><ChannelBadge channel={e.paymentChannel} /></td>
                            <td className="tabular whitespace-nowrap py-2.5 pr-4 text-right font-semibold">
                              −{formatMoney(item.amountMinor, e.currency)}
                              {shared && !e.paidByMe && <span className="block text-[11px] font-normal text-blue">your share</span>}
                            </td>
                          </tr>
                        );
                      }
                      const m = item.movement;
                      const info = kindInfo(m.kind);
                      const Icon = movementIcon(m.kind);
                      return (
                        <tr key={item.id} className="relative border-b border-separator last:border-0 hover:bg-card-2">
                          <td className="whitespace-nowrap py-2.5 pl-4 text-label-2">{formatDate(m.date, { day: "numeric", month: "short", year: "numeric" })}</td>
                          <td className="max-w-[280px] py-2.5">
                            <Link href={`/transactions/m/${m.id}`} className="flex items-center gap-2.5 font-semibold after:absolute after:inset-0">
                              <IconTile icon={Icon} tint={info.direction === "in" ? "green" : info.direction === "out" ? "orange" : "teal"} size={32} />
                              <span className="truncate">{m.note || info.label}</span>
                            </Link>
                          </td>
                          <td className="py-2.5 text-label-2">{info.label}</td>
                          <td className="py-2.5">{m.accountId ? accounts.get(m.accountId)?.name ?? "—" : "—"}</td>
                          <td className="py-2.5"><ChannelBadge channel={m.paymentChannel} /></td>
                          <td className={cx("tabular whitespace-nowrap py-2.5 pr-4 text-right font-semibold", info.direction === "in" && "text-green")}>
                            {info.direction === "in" ? "+" : info.direction === "out" ? "−" : ""}{formatMoney(m.amountMinor, m.currency)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </Card>
              {items.length > limit && (
                <Button variant="tinted" onClick={() => setLimit((l) => l + PAGE_SIZE)} className="self-center">
                  Show more ({items.length - limit} left)
                </Button>
              )}
            </>
          )}
        </div>
        <aside aria-label="Filters" className="sticky top-6 hidden h-fit w-[300px] shrink-0 xl:block">
          <Card><FilterPanel filters={filters} onChange={setFilters} fundingAccounts={fundingAccounts} people={live.people} /></Card>
        </aside>
      </Page>
      <Sheet open={showFilters} onClose={() => setShowFilters(false)} title="Filters"
        footer={<Button className="w-full" onClick={() => setShowFilters(false)}>Show {items.length} result{items.length === 1 ? "" : "s"}</Button>}>
        <FilterPanel filters={filters} onChange={setFilters} fundingAccounts={fundingAccounts} people={live.people} />
      </Sheet>
    </>
  );
}

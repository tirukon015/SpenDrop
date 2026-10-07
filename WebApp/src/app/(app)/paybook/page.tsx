"use client";

import { BookUser, Search, UserPlus } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { PersonSheet } from "@/components/person-form";
import { useData } from "@/components/providers/data-provider";
import { Avatar, Button, Card, Divider, EmptyState, ErrorBanner, Input, ListSkeleton, Segmented, cx } from "@/components/ui/primitives";
import { balancesForPerson, outstandingPeople, type BalanceFilter, type LedgerInput } from "@/lib/domain/ledger";
import { formatDate } from "@/lib/domain/dates";
import { formatMoney } from "@/lib/domain/money";
import { AnimatedMoney, rise } from "@/components/motion";

export default function PayBookPage() {
  const { live, status, error, refresh } = useData();
  const [filter, setFilter] = useState<BalanceFilter>("all");
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState(false);
  const [showArchived, setShowArchived] = useState(false);
  const input: LedgerInput = useMemo(() => ({ expenses: live.expenses, shares: live.shares, movements: live.movements, allocations: live.allocations }), [live]);

  const lastActivity = useMemo(() => {
    const map = new Map<string, string>();
    const bump = (id: string | null, date: string) => { if (id && (!map.get(id) || map.get(id)! < date)) map.set(id, date); };
    for (const e of live.expenses) { bump(e.payerId, e.date); for (const s of live.shares.get(e.id) ?? []) bump(s.personId, e.date); }
    for (const m of live.movements) bump(m.personId, m.date);
    return map;
  }, [live]);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    const visible = live.people.filter((p) => (showArchived || !p.isArchived) && (!q || p.name.toLowerCase().includes(q)));
    if (filter !== "all") return outstandingPeople(visible, filter, input, (p) => lastActivity.get(p.id) ?? p.updatedAt);
    return visible.map((person) => {
      const balances = balancesForPerson(person.id, live.expenses, live.shares, live.movements);
      const [currency, value] = [...balances.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))[0] ?? ["RM", 0];
      return { person, amountMinor: value, currency, lastActivity: lastActivity.get(person.id) ?? person.updatedAt };
    });
  }, [live, filter, query, input, lastActivity, showArchived]);

  const totals = useMemo(() => {
    let owed = 0, owe = 0;
    for (const p of live.people) {
      const v = balancesForPerson(p.id, live.expenses, live.shares, live.movements).get("RM") ?? 0;
      if (v > 0) owed += v; else owe -= v;
    }
    return { owed, owe };
  }, [live]);

  return (
    <>
      <PageHeader title="PayBook" subtitle="People, balances and payment details"
        actions={<Button onClick={() => setAdding(true)}><UserPlus aria-hidden className="size-4" /> <span className="max-sm:sr-only">Add Person</span></Button>} />
      <Page className="flex flex-col gap-4">
        {error && <ErrorBanner message={error} onRetry={refresh} />}
        <div className="grid grid-cols-2 gap-3">
          <Card className="sd-rise" style={rise(0)}><p className="section-header">They owe me</p><AnimatedMoney minor={totals.owed} className="tabular mt-1 block text-[22px] font-bold text-green" /></Card>
          <Card className="sd-rise" style={rise(1)}><p className="section-header">I owe them</p><AnimatedMoney minor={totals.owe} className="tabular mt-1 block text-[22px] font-bold text-orange" /></Card>
        </div>
        <Segmented label="Show" value={filter} onChange={setFilter}
          options={[{ id: "all", label: "All" }, { id: "theyOweMe", label: "They Owe Me" }, { id: "iOweThem", label: "I Owe Them" }]} />
        <div className="relative">
          <Search aria-hidden className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-label-2" />
          <label htmlFor="people-search" className="sr-only">Search people</label>
          <Input id="people-search" type="search" className="pl-10" placeholder="Search people" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        {status === "loading" && live.people.length === 0 ? <Card className="p-0"><ListSkeleton rows={4} /></Card>
          : live.people.length === 0 ? (
            <Card><EmptyState icon={BookUser} title="Your PayBook is empty" message="Save people and their payment details so you can split with them and track who owes what."
              action={<Button onClick={() => setAdding(true)}><UserPlus aria-hidden className="size-4" /> Add Person</Button>} /></Card>
          ) : rows.length === 0 ? (
            <Card><EmptyState icon={BookUser} title={filter === "theyOweMe" ? "Nobody owes you right now" : filter === "iOweThem" ? "You don't owe anyone" : "No matching people"}
              message={filter === "all" ? `No person found matching '${query}'.` : "Balances appear here when a split or loan leaves money owed."} /></Card>
          ) : (
            <Card className="overflow-hidden p-0">
              <ul>
                {rows.map((r, i) => (
                  <li key={r.person.id} className="sd-row" style={rise(i)}>{i > 0 && <Divider inset={68} />}
                    <Link href={`/paybook/${r.person.id}`} className="flex min-h-16 items-center gap-3 px-4 py-2.5 hover:bg-card-2">
                      <Avatar name={r.person.name} />
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-semibold">{r.person.name}{r.person.isArchived && <span className="ml-2 text-xs font-normal text-label-2">Archived</span>}</p>
                        <p className="text-xs text-label-2">Last activity {formatDate(r.lastActivity, { day: "numeric", month: "short" })}</p>
                      </div>
                      <div className="text-right">
                        {(filter === "all" ? r.amountMinor : (filter === "theyOweMe" ? 1 : -1) * r.amountMinor) === 0 ? <span className="text-sm text-label-2">Settled</span> : (
                          <>
                            <p className={cx("tabular font-bold", (filter === "iOweThem" || (filter === "all" && r.amountMinor < 0)) ? "text-orange" : "text-green")}>
                              {formatMoney(Math.abs(r.amountMinor), r.currency)}
                            </p>
                            <p className="text-[11px] text-label-2">{(filter === "iOweThem" || (filter === "all" && r.amountMinor < 0)) ? "you owe" : "owes you"}</p>
                          </>
                        )}
                      </div>
                    </Link>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        {live.people.some((p) => p.isArchived) && (
          <button type="button" className="self-center text-sm font-medium text-[var(--sd-accent-text)]" onClick={() => setShowArchived((v) => !v)}>
            {showArchived ? "Hide archived people" : "Show archived people"}
          </button>
        )}
      </Page>
      {adding && <PersonSheet open={adding} onClose={() => setAdding(false)} />}
    </>
  );
}

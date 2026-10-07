"use client";

import { Archive, Pencil } from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { ActivityRow } from "@/components/transactions";
import { Button, Card, Divider, SectionHeader } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { buildActivity, defaultFilters } from "@/lib/domain/activity";
import { accountActivity } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";
import { AccountSheet } from "@/components/account-sheet";

export default function AccountDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { live, saveRecords } = useData();
  const toast = useToast();
  const [editing, setEditing] = useState(false);
  const account = live.accounts.find((a) => a.id === id);
  const people = useMemo(() => new Map(live.people.map((p) => [p.id, p])), [live.people]);
  const accounts = useMemo(() => new Map(live.accounts.map((a) => [a.id, a])), [live.accounts]);
  const items = useMemo(() => {
    const all = buildActivity(live.expenses, live.shares, live.movements, live.people, defaultFilters());
    return all.filter((i) => (i.type === "expense" ? i.expense.accountId === id : i.movement.accountId === id || i.movement.counterAccountId === id)).slice(0, 100);
  }, [live, id]);
  return (
    <RecordGate found={Boolean(account)}>
      {account && (() => {
        const activity = accountActivity(account.id, account.currency, live.expenses, live.movements);
        return (
          <>
            <PageHeader title={account.name} back={{ href: "/more/accounts", label: "Bank Accounts" }}
              actions={<Button size="sm" variant="tinted" onClick={() => setEditing(true)}><Pencil aria-hidden className="size-4" /> Edit</Button>} />
            <Page className="flex max-w-3xl flex-col gap-5">
              <div className="grid grid-cols-3 gap-3">
                <Card><p className="section-header">In</p><p className="tabular mt-1 font-bold text-green">{formatMoney(activity.inMinor)}</p></Card>
                <Card><p className="section-header">Out</p><p className="tabular mt-1 font-bold">{formatMoney(activity.outMinor)}</p></Card>
                <Card><p className="section-header">Net</p><p className="tabular mt-1 font-bold">{formatMoney(activity.netMinor)}</p></Card>
              </div>
              <p className="-mt-3 px-1 text-xs text-label-2">Recorded in SpenDrop — not your real bank balance. Expenses someone else paid don&apos;t count (no money left this account).</p>
              <section aria-labelledby="acc-activity">
                <SectionHeader id="acc-activity">Activity</SectionHeader>
                <Card className="overflow-hidden p-0">
                  {items.length === 0 ? <p className="p-4 text-sm text-label-2">Nothing recorded for this account yet.</p>
                    : items.map((item, i) => <div key={item.id}>{i > 0 && <Divider inset={72} />}<ActivityRow item={item} people={people} accounts={accounts} /></div>)}
                </Card>
              </section>
              <Button variant="secondary" className="self-start" onClick={async () => {
                try { await saveRecords("accounts", [{ ...account, isArchived: !account.isArchived, updatedAt: new Date().toISOString() }]); toast(account.isArchived ? "Restored" : "Archived"); }
                catch (e) { toast(friendlyError(e), { tone: "error" }); }
              }}><Archive aria-hidden className="size-4" /> {account.isArchived ? "Restore account" : "Archive account"}</Button>
            </Page>
            {editing && <AccountSheet open onClose={() => setEditing(false)} account={account} />}
          </>
        );
      })()}
    </RecordGate>
  );
}

"use client";

import { ChevronRight, Landmark, Plus } from "lucide-react";
import { useMemo, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { ACCOUNT_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { AccountSheet } from "@/components/account-sheet";
import { Button, Card, Divider, EmptyState, IconTile, Row } from "@/components/ui/primitives";
import { accountActivity } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";

export default function AccountsPage() {
  const { live } = useData();
  const [adding, setAdding] = useState(false);
  const rows = useMemo(() => live.accounts.map((a) => ({ account: a, activity: accountActivity(a.id, a.currency, live.expenses, live.movements) })), [live]);
  return (
    <>
      <PageHeader title="Bank Accounts" subtitle="Banks, e-wallets and cash — where money comes from" back={{ href: "/more", label: "More" }}
        actions={<Button onClick={() => setAdding(true)}><Plus aria-hidden className="size-4" /> <span className="max-sm:sr-only">Add Account</span></Button>} />
      <Page className="flex max-w-3xl flex-col gap-3">
        {rows.length === 0 ? (
          <Card><EmptyState icon={Landmark} title="No accounts yet" message="Accounts are created automatically from your expenses, or add one with +."
            action={<Button onClick={() => setAdding(true)}><Plus aria-hidden className="size-4" /> Add Account</Button>} /></Card>
        ) : (
          <Card className="overflow-hidden p-0">
            {rows.filter((r) => !r.account.isArchived).concat(rows.filter((r) => r.account.isArchived)).map(({ account, activity }, i) => (
              <div key={account.id}>{i > 0 && <Divider inset={72} />}
                <Row href={`/more/accounts/${account.id}`}>
                  <IconTile icon={ACCOUNT_ICONS[account.type]} tint={account.isArchived ? "gray" : "blue"} size={40} />
                  <span className="min-w-0 flex-1">
                    <span className="block font-semibold">{account.name}{account.isArchived && <span className="ml-2 text-xs font-normal text-label-2">Archived</span>}</span>
                    <span className="block text-xs text-label-2">In {formatMoney(activity.inMinor, account.currency)} · Out {formatMoney(activity.outMinor, account.currency)}</span>
                  </span>
                  <span className={`tabular text-sm font-semibold ${activity.netMinor >= 0 ? "text-green" : ""}`}>{activity.netMinor >= 0 ? "+" : ""}{formatMoney(activity.netMinor, account.currency)}</span>
                  <ChevronRight aria-hidden className="size-4 text-label-3" />
                </Row>
              </div>
            ))}
          </Card>
        )}
        <p className="px-1 text-xs text-label-2">Totals are what you have recorded in SpenDrop. They are not your real bank balance.</p>
      </Page>
      {adding && <AccountSheet open onClose={() => setAdding(false)} />}
    </>
  );
}

"use client";

import { Pencil, Share2, Trash2 } from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { movementIcon } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { Button, ButtonLink, Card, Divider, IconTile, Sheet } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { channelInfo, kindInfo } from "@/lib/domain/constants";
import { formatDate, formatTime } from "@/lib/domain/dates";
import { formatMoney } from "@/lib/domain/money";
import { shareText } from "@/lib/share";

export default function MovementDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const toast = useToast();
  const { live, deleteRecord } = useData();
  const m = live.movements.find((x) => x.id === id);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const linkedAllocations = live.allocations.filter((a) => a.paymentId === id || a.loanId === id);

  return (
    <RecordGate found={Boolean(m)}>
      {m && (() => {
        const info = kindInfo(m.kind);
        const person = m.personId ? live.people.find((p) => p.id === m.personId)?.name ?? m.personNameSnapshot : m.personNameSnapshot;
        const account = m.accountId ? live.accounts.find((a) => a.id === m.accountId)?.name : null;
        const counter = m.counterAccountId ? live.accounts.find((a) => a.id === m.counterAccountId)?.name : null;
        const sign = info.direction === "in" ? "+" : info.direction === "out" ? "−" : "";
        const rows: [string, React.ReactNode][] = [
          ["Type", info.label],
          ...(person ? [["Person", m.personId ? <Link key="p" className="text-[var(--sd-accent-text)]" href={`/paybook/${m.personId}`}>{person}</Link> : person] as [string, React.ReactNode]] : []),
          ...(account ? [[m.kind === "ownTransfer" ? "From" : info.direction === "in" ? "Into account" : "From account", account] as [string, React.ReactNode]] : []),
          ...(counter ? [["To", counter] as [string, React.ReactNode]] : []),
          ["Payment channel", channelInfo(m.paymentChannel).label],
          ["Date", `${formatDate(m.date)} · ${formatTime(m.date)}`],
          ...(m.transactionReference ? [["Reference", m.transactionReference] as [string, React.ReactNode]] : []),
        ];
        return (
          <>
            <PageHeader title={m.note || info.label} subtitle={info.label} back={{ href: "/transactions", label: "Transactions" }}
              actions={<>
                <Button variant="secondary" size="sm" className="bg-card shadow-card" onClick={async () => {
                  const r = await shareText(info.label, `${m.note || info.label} — ${sign}${formatMoney(m.amountMinor, m.currency)}\n${formatDate(m.date)}${person ? ` · ${person}` : ""}\n— shared from SpenDrop`);
                  if (r === "copied") toast("Copied to clipboard");
                }}><Share2 aria-hidden className="size-4" /> <span className="max-sm:sr-only">Share</span></Button>
                <ButtonLink href={`/transactions/m/${m.id}/edit`} variant="tinted"><Pencil aria-hidden className="size-4" /> <span className="max-sm:sr-only">Edit</span></ButtonLink>
              </>} />
            <Page className="flex max-w-3xl flex-col gap-5">
              <Card className="flex items-center gap-4">
                <IconTile icon={movementIcon(m.kind)} tint={info.direction === "in" ? "green" : info.direction === "out" ? "orange" : "teal"} size={56} />
                <p className={`tabular text-[34px] font-bold tracking-tight ${info.direction === "in" ? "text-green" : ""}`}>{sign}{formatMoney(m.amountMinor, m.currency)}</p>
              </Card>
              <Card className="overflow-hidden p-0">
                {rows.map(([label, value], i) => (
                  <div key={label}>{i > 0 && <Divider inset={16} />}
                    <div className="flex min-h-11 items-center justify-between gap-4 px-4 py-2.5"><span className="text-label-2">{label}</span><span className="text-right font-medium">{value}</span></div>
                  </div>
                ))}
              </Card>
              {m.kind === "ownTransfer" && <p className="px-1 text-xs text-label-2">Own transfers are never counted as income or spending.</p>}
              <Button variant="destructive" className="self-start" onClick={() => setConfirm(true)}><Trash2 aria-hidden className="size-4" /> Delete</Button>
            </Page>
            <Sheet open={confirm} onClose={() => setConfirm(false)} title="Delete this record?"
              footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirm(false)}>Cancel</Button>
                <Button variant="destructive" loading={busy} onClick={async () => {
                  setBusy(true);
                  try { await deleteRecord("movements", m); toast("Deleted"); router.push("/transactions"); }
                  catch (e) { toast(friendlyError(e), { tone: "error" }); }
                  finally { setBusy(false); }
                }}>Delete</Button></div>}>
              <p className="text-[15px]">{info.label} · {formatMoney(m.amountMinor, m.currency)} will be removed on all your devices.
                {linkedAllocations.length > 0 ? " Settlements that used this payment will no longer count." : ""}</p>
            </Sheet>
          </>
        );
      })()}
    </RecordGate>
  );
}

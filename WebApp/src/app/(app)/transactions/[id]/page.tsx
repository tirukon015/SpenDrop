"use client";

import { Check, Pencil, Share2, Trash2, Undo2 } from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { CATEGORY_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { ChannelBadge } from "@/components/transactions";
import { Avatar, Button, ButtonLink, Card, Divider, IconTile, SectionHeader, Sheet, cx, tintText } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { categoryTint, channelInfo } from "@/lib/domain/constants";
import { formatDate, formatTime } from "@/lib/domain/dates";
import { expenseDebt, activeAllocations, myShareMinor, planMarkPaid, settlementGroups, type LedgerInput } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";
import { shareText } from "@/lib/share";

function DetailRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-11 items-center justify-between gap-4 px-4 py-2.5">
      <span className="text-[15px] text-label-2">{label}</span>
      <span className="min-w-0 text-right text-[15px] font-medium">{children}</span>
    </div>
  );
}

export default function ExpenseDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const toast = useToast();
  const { live, source, deleteExpense, recordSettlement, undoSettlement } = useData();
  const expense = live.expenses.find((e) => e.id === id);
  const shares = useMemo(() => live.shares.get(id) ?? [], [live.shares, id]);
  const people = useMemo(() => new Map(live.people.map((p) => [p.id, p])), [live.people]);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [receiptUrl, setReceiptUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (expense?.receiptPath && source) source.receiptUrl(expense.receiptPath).then((url) => !cancelled && setReceiptUrl(url)).catch(() => undefined);
    return () => { cancelled = true; };
  }, [expense?.receiptPath, source]);

  const input: LedgerInput = { expenses: live.expenses, shares: live.shares, movements: live.movements, allocations: live.allocations };
  const debts = useMemo(() => {
    if (!expense) return [];
    const active = activeAllocations(live.allocations, live.movements);
    const involved = expense.paidByMe ? shares.filter((s) => !s.isMe && s.personId).map((s) => s.personId!) : expense.payerId ? [expense.payerId] : [];
    return involved.map((pid) => people.get(pid)).filter((p) => p !== undefined).map((p) => expenseDebt(expense, shares, p!, active.filter((a) => a.personId === p!.id))).filter((d) => d !== null);
  }, [expense, shares, people, live.allocations, live.movements]);
  const groups = expense ? settlementGroups({ expenseId: expense.id }, input) : [];

  async function run(key: string, action: () => Promise<void>, done: string) {
    setBusy(key);
    try {
      await action();
      toast(done);
    } catch (e) {
      toast(friendlyError(e), { tone: "error" });
    } finally {
      setBusy(null);
    }
  }

  return (
    <RecordGate found={Boolean(expense)}>
      {expense && (() => {
        const mine = myShareMinor(expense, shares);
        const payer = expense.payerId ? people.get(expense.payerId)?.name ?? expense.payerNameSnapshot : expense.payerNameSnapshot;
        const shareLines = shares.map((s) => `${s.isMe ? "You" : (s.personId && people.get(s.personId)?.name) || s.nameSnapshot}: ${formatMoney(s.amountMinor, expense.currency)}`);
        const text = [
          `${expense.merchant} — ${formatMoney(expense.amountMinor, expense.currency)}`,
          `${formatDate(expense.date)} · ${expense.category}`,
          shares.length ? `Split (${expense.paidByMe ? "I paid" : `${payer} paid`}): ${shareLines.join(", ")}` : null,
          ...debts.filter((d) => !d.isSettled).map((d) => (d.direction > 0 ? `${d.personName} owes ${formatMoney(d.outstandingMinor, d.currency)}` : `I owe ${d.personName} ${formatMoney(d.outstandingMinor, d.currency)}`)),
          "— shared from SpenDrop",
        ].filter(Boolean).join("\n");
        return (
          <>
            <PageHeader title={expense.merchant} subtitle={`${formatDate(expense.date, { weekday: "long", day: "numeric", month: "long", year: "numeric" })} · ${formatTime(expense.date)}`}
              back={{ href: "/transactions", label: "Transactions" }}
              actions={<>
                <Button variant="secondary" size="sm" className="bg-card shadow-card" onClick={async () => {
                  const r = await shareText(expense.merchant, text);
                  if (r === "copied") toast("Copied to clipboard");
                  if (r === "failed") toast("Couldn't share on this browser", { tone: "error" });
                }}><Share2 aria-hidden className="size-4" /> <span className="max-sm:sr-only">Share</span></Button>
                <ButtonLink href={`/transactions/${expense.id}/edit`} variant="tinted"><Pencil aria-hidden className="size-4" /> <span className="max-sm:sr-only">Edit</span></ButtonLink>
              </>} />
            <Page className="grid gap-5 lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
              <div className="flex flex-col gap-5">
                <Card className="flex items-center gap-4">
                  <IconTile icon={CATEGORY_ICONS[expense.category]} tint={categoryTint(expense.category)} size={56} />
                  <div className="min-w-0">
                    <p className="tabular text-[34px] font-bold leading-tight tracking-tight">{formatMoney(expense.amountMinor, expense.currency)}</p>
                    {shares.length > 0 && <p className="text-sm text-blue">{expense.paidByMe ? `You paid · your share ${formatMoney(mine, expense.currency)}` : `${payer ?? "Someone"} paid · your share ${formatMoney(mine, expense.currency)}`}</p>}
                  </div>
                </Card>
                <Card className="overflow-hidden p-0">
                  <DetailRow label="Category"><span style={{ color: tintText(categoryTint(expense.category)) }}>{expense.category}</span></DetailRow><Divider inset={16} />
                  <DetailRow label="Funding account">{expense.accountId ? <Link className="text-[var(--sd-accent-text)]" href={`/more/accounts/${expense.accountId}`}>{expense.fundingAccount}</Link> : expense.fundingAccount}</DetailRow><Divider inset={16} />
                  <DetailRow label="Payment channel"><span className="inline-flex items-center gap-1.5"><ChannelBadge channel={expense.paymentChannel} withLabel={false} />{channelInfo(expense.paymentChannel).label}</span></DetailRow><Divider inset={16} />
                  <DetailRow label="Date">{formatDate(expense.date)} · {formatTime(expense.date)}</DetailRow>
                  {expense.transactionReference && (<><Divider inset={16} /><DetailRow label="Reference"><span className="break-all">{expense.transactionReference}</span></DetailRow></>)}
                  {expense.notes && (<><Divider inset={16} /><div className="px-4 py-3"><p className="text-[15px] text-label-2">Description</p><p className="mt-1 whitespace-pre-wrap">{expense.notes}</p></div></>)}
                </Card>
                {expense.receiptPath && (
                  <section aria-labelledby="receipt-heading">
                    <SectionHeader id="receipt-heading">Receipt</SectionHeader>
                    <Card className="flex justify-center">
                      {/* eslint-disable-next-line @next/next/no-img-element -- short-lived signed URL from private storage */}
                      {receiptUrl ? <a href={receiptUrl} target="_blank" rel="noreferrer"><img src={receiptUrl} alt={`Receipt for ${expense.merchant}`} className="max-h-[420px] rounded-lg object-contain" /></a> : <p className="py-6 text-sm text-label-2">Loading receipt…</p>}
                    </Card>
                  </section>
                )}
              </div>
              <div className="flex flex-col gap-5">
                {shares.length > 0 && (
                  <section aria-labelledby="split-heading">
                    <SectionHeader id="split-heading">Split · {shares.length} {shares.length === 1 ? "person" : "people"}</SectionHeader>
                    <Card className="overflow-hidden p-0">
                      {shares.map((s, i) => {
                        const name = s.isMe ? "You" : (s.personId && people.get(s.personId)?.name) || s.nameSnapshot;
                        return (
                          <div key={s.id}>{i > 0 && <Divider inset={60} />}
                            <div className="flex min-h-12 items-center gap-3 px-4 py-2">
                              <Avatar name={s.isMe ? "Me" : name} size={32} />
                              {s.personId ? <Link href={`/paybook/${s.personId}`} className="flex-1 font-medium hover:underline">{name}</Link> : <span className="flex-1 font-medium">{name}</span>}
                              <span className="tabular font-semibold">{formatMoney(s.amountMinor, expense.currency)}</span>
                            </div>
                          </div>
                        );
                      })}
                    </Card>
                  </section>
                )}
                {debts.length > 0 && (
                  <section aria-labelledby="debts-heading">
                    <SectionHeader id="debts-heading">Who owes what</SectionHeader>
                    <Card className="overflow-hidden p-0">
                      {debts.map((d, i) => (
                        <div key={d.id}>{i > 0 && <Divider inset={16} />}
                          <div className="flex min-h-14 items-center gap-3 px-4 py-2.5">
                            <div className="min-w-0 flex-1">
                              <p className={cx("font-semibold", d.isSettled ? "text-label-2" : d.direction > 0 ? "text-green" : "text-orange")}>
                                {d.isSettled ? `Settled with ${d.personName}` : d.direction > 0 ? `${d.personName} owes you ${formatMoney(d.outstandingMinor, d.currency)}` : `You owe ${d.personName} ${formatMoney(d.outstandingMinor, d.currency)}`}
                              </p>
                              <p className="text-xs text-label-2">{d.detail}{d.settledMinor > 0 && !d.isSettled ? ` · ${formatMoney(d.settledMinor, d.currency)} paid` : ""}</p>
                            </div>
                            {!d.isSettled && (
                              <Button size="sm" variant="tinted" loading={busy === d.id} aria-label={`Mark ${d.personName} as paid`}
                                onClick={() => run(d.id, () => recordSettlement(planMarkPaid(d, people.get(d.personId)!, new Date().toISOString())), "Marked as paid")}>
                                <Check aria-hidden className="size-4" /> Mark as Paid
                              </Button>
                            )}
                          </div>
                        </div>
                      ))}
                    </Card>
                  </section>
                )}
                {groups.length > 0 && (
                  <section aria-labelledby="history-heading">
                    <SectionHeader id="history-heading">Settlement history</SectionHeader>
                    <Card className="overflow-hidden p-0">
                      {groups.map((g, i) => (
                        <div key={g.id}>{i > 0 && <Divider inset={16} />}
                          <div className="flex min-h-12 items-center gap-3 px-4 py-2">
                            <div className="flex-1 text-sm">
                              <p className="font-medium">{g.direction > 0 ? "Paid to you" : g.direction < 0 ? "You paid" : "Offset"} · {formatMoney(g.totalMinor || g.offsetMinor, g.currency)}</p>
                              <p className="text-xs text-label-2">{formatDate(g.date)}</p>
                            </div>
                            <Button size="sm" variant="plain" loading={busy === g.id} onClick={() => run(g.id, () => undoSettlement(g.id), "Settlement undone")}>
                              <Undo2 aria-hidden className="size-4" /> Undo
                            </Button>
                          </div>
                        </div>
                      ))}
                    </Card>
                  </section>
                )}
                <Button variant="destructive" onClick={() => setConfirmDelete(true)} className="self-start"><Trash2 aria-hidden className="size-4" /> Delete Expense</Button>
              </div>
            </Page>
            <Sheet open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Delete this expense?"
              footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirmDelete(false)}>Cancel</Button>
                <Button variant="destructive" loading={busy === "delete"} onClick={() => run("delete", async () => { await deleteExpense(expense); router.push("/transactions"); }, "Expense deleted")}>Delete</Button></div>}>
              <p className="text-[15px]">{expense.merchant} · {formatMoney(expense.amountMinor, expense.currency)} will be removed on all your devices{shares.length ? ", and its split will no longer count in PayBook balances" : ""}. People and other transactions stay as they are.</p>
            </Sheet>
          </>
        );
      })()}
    </RecordGate>
  );
}

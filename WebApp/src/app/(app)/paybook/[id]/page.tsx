"use client";

import { Archive, Check, Copy, HandCoins, Pencil, Plus, Share2, Trash2, Undo2, Wallet } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { PersonSheet } from "@/components/person-form";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { Avatar, Button, Card, Divider, EmptyState, Field, Input, Segmented, SectionHeader, Select, Sheet, TextArea, cx } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { PAYMENT_TYPES, kindInfo } from "@/lib/domain/constants";
import { formatDate } from "@/lib/domain/dates";
import {
  autoAllocate, balancesForPerson, creditMinor, debtsForPerson, directionText, myShareMinor, planApplyCredit, planMarkPaid, planPayment, planSettleAll,
  settlementGroups, type Debt, type LedgerInput,
} from "@/lib/domain/ledger";
import { formatMoney, parseMinor } from "@/lib/domain/money";
import type { PaymentType, Person, PersonPaymentMethod } from "@/lib/domain/types";
import { shareText } from "@/lib/share";

function MethodSheet({ open, onClose, person, method }: { open: boolean; onClose: () => void; person: Person; method?: PersonPaymentMethod }) {
  const { saveRecords } = useData();
  const toast = useToast();
  const [type, setType] = useState<PaymentType>(method?.paymentType ?? "Bank Account");
  const [provider, setProvider] = useState(method?.provider ?? "");
  const [identifier, setIdentifier] = useState(method?.accountIdentifier ?? "");
  const [label, setLabel] = useState(method?.label ?? "");
  const [notes, setNotes] = useState(method?.notes ?? "");
  const [busy, setBusy] = useState(false);
  const valid = provider.trim() && identifier.trim();
  async function save() {
    setBusy(true);
    try {
      const now = new Date().toISOString();
      await saveRecords("paymentMethods", [{
        id: method?.id ?? crypto.randomUUID(), personId: person.id, paymentType: type, provider: provider.trim(), customProviderName: null,
        accountIdentifier: identifier.trim().slice(0, 120), label: label.trim() || null, notes: notes.trim() || null,
        createdAt: method?.createdAt ?? now, updatedAt: now, deletedAt: null,
      }]);
      toast("Payment details saved");
      onClose();
    } catch (e) {
      toast(friendlyError(e), { tone: "error" });
    } finally {
      setBusy(false);
    }
  }
  return (
    <Sheet open={open} onClose={onClose} title={method ? "Edit Payment Details" : "Add Payment Details"}
      footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!valid} loading={busy} onClick={save}>Save</Button></div>}>
      <div className="flex flex-col gap-4">
        <Field label="Type" htmlFor="pm-type"><Select id="pm-type" value={type} onChange={(e) => setType(e.target.value as PaymentType)}>{PAYMENT_TYPES.map((t) => <option key={t}>{t}</option>)}</Select></Field>
        <Field label="Bank / wallet" htmlFor="pm-provider"><Input id="pm-provider" value={provider} onChange={(e) => setProvider(e.target.value)} placeholder="e.g. Maybank, Touch 'n Go" /></Field>
        <Field label={type === "Bank Account" ? "Account number" : type === "E-Wallet" ? "Phone number / wallet ID" : "Payment ID"} htmlFor="pm-id">
          <Input id="pm-id" value={identifier} onChange={(e) => setIdentifier(e.target.value)} />
        </Field>
        <Field label="Label" htmlFor="pm-label"><Input id="pm-label" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Optional" /></Field>
        <Field label="Notes" htmlFor="pm-notes"><TextArea id="pm-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" /></Field>
      </div>
    </Sheet>
  );
}

/** Record a real payment with this person, applied to outstanding transactions (oldest first by default). */
function PaymentSheet({ open, onClose, person, debts }: { open: boolean; onClose: () => void; person: Person; debts: Debt[] }) {
  const { recordSettlement, live } = useData();
  const toast = useToast();
  const [direction, setDirection] = useState<"1" | "-1">(debts.some((d) => d.direction > 0 && !d.isSettled) ? "1" : "-1");
  const [amountText, setAmountText] = useState("");
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dir = Number(direction) as 1 | -1;
  const amount = parseMinor(amountText) ?? 0;
  const open$ = debts.filter((d) => d.direction === dir && d.outstandingMinor > 0);
  const plan = amount > 0 ? autoAllocate(amount, open$) : [];
  const applied = plan.reduce((s, [, a]) => s + a, 0);
  async function save() {
    setBusy(true);
    setError(null);
    try {
      await recordSettlement(planPayment(person, dir, amount, plan, "RM", new Date().toISOString(), accountId || null,
        dir > 0 ? `Payment from ${person.name}` : `Payment to ${person.name}`));
      toast("Payment recorded");
      onClose();
    } catch (e) {
      setError(e instanceof Error && !/fetch/i.test(e.message) ? e.message : friendlyError(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <Sheet open={open} onClose={onClose} title="Record Payment"
      footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!(amount > 0)} loading={busy} onClick={save}>Record</Button></div>}>
      <div className="flex flex-col gap-4">
        <Segmented label="Direction" value={direction} onChange={setDirection}
          options={[{ id: "1", label: `${person.name} paid me` }, { id: "-1", label: `I paid ${person.name}` }]} />
        <Field label="Amount" htmlFor="pay-amount"><Input id="pay-amount" inputMode="decimal" autoFocus placeholder="0.00" value={amountText} onChange={(e) => setAmountText(e.target.value)} /></Field>
        <Field label={dir > 0 ? "Into account" : "From account"} htmlFor="pay-account">
          <Select id="pay-account" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Not linked to an account</option>
            {live.accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </Select>
        </Field>
        {amount > 0 && (
          <Card className="text-sm">
            <p className="section-header mb-2">Applied oldest first</p>
            {plan.length === 0 ? <p className="text-label-2">Nothing outstanding in this direction — it will be kept as credit.</p> : plan.map(([d, a]) => (
              <p key={d.id} className="flex justify-between"><span className="truncate">{d.title}</span><span className="tabular">{formatMoney(a)}</span></p>
            ))}
            {amount - applied > 0 && plan.length > 0 && <p className="mt-1 flex justify-between text-label-2"><span>Kept as credit</span><span className="tabular">{formatMoney(amount - applied)}</span></p>}
          </Card>
        )}
        {error && <p role="alert" className="text-sm text-red">{error}</p>}
        <p className="text-xs text-label-2">The original transactions never change; the payment is recorded and linked to them.</p>
      </div>
    </Sheet>
  );
}

export default function PersonPage() {
  const { id } = useParams<{ id: string }>();
  const toast = useToast();
  const { live, recordSettlement, undoSettlement, saveRecords, deleteRecord } = useData();
  const person = live.people.find((p) => p.id === id);
  const [editing, setEditing] = useState(false);
  const [methodSheet, setMethodSheet] = useState<PersonPaymentMethod | "new" | null>(null);
  const [paying, setPaying] = useState(false);
  const [confirmSettleAll, setConfirmSettleAll] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const input: LedgerInput = useMemo(() => ({ expenses: live.expenses, shares: live.shares, movements: live.movements, allocations: live.allocations }), [live]);

  const data = useMemo(() => {
    if (!person) return null;
    const balances = balancesForPerson(person.id, live.expenses, live.shares, live.movements);
    const debts = debtsForPerson(person, input);
    const methods = live.paymentMethods.filter((m) => m.personId === person.id);
    // History: everything that changed what we owe each other (newest first).
    const entries: { id: string; date: string; title: string; detail: string; effect: number; href: string }[] = [];
    for (const e of live.expenses) {
      const list = live.shares.get(e.id) ?? [];
      if (e.paidByMe) {
        const share = list.find((s) => !s.isMe && s.personId === person.id);
        if (share) entries.push({ id: e.id, date: e.date, title: e.merchant, detail: `You paid ${formatMoney(e.amountMinor, e.currency)} · their share`, effect: share.amountMinor, href: `/transactions/${e.id}` });
      } else if (e.payerId === person.id) {
        entries.push({ id: e.id, date: e.date, title: e.merchant, detail: `${person.name} paid ${formatMoney(e.amountMinor, e.currency)} · your share`, effect: -myShareMinor(e, list), href: `/transactions/${e.id}` });
      }
    }
    for (const m of live.movements) {
      if (m.personId !== person.id) continue;
      const sign = kindInfo(m.kind).personBalanceSign;
      entries.push({ id: m.id, date: m.date, title: m.note || kindInfo(m.kind).label, detail: kindInfo(m.kind).label, effect: sign * m.amountMinor, href: `/transactions/m/${m.id}` });
    }
    entries.sort((a, b) => (a.date < b.date ? 1 : -1));
    return { balances, debts, methods, entries, groups: settlementGroups({ personId: person.id }, input) };
  }, [person, live, input]);

  async function run(key: string, action: () => Promise<void>, done: string) {
    setBusy(key);
    try { await action(); toast(done); } catch (e) { toast(e instanceof Error && !/fetch|JWT|permission/i.test(e.message) ? e.message : friendlyError(e), { tone: "error" }); }
    finally { setBusy(null); }
  }

  return (
    <RecordGate found={Boolean(person && data)}>
      {person && data && (() => {
        const net = data.balances.get("RM") ?? 0;
        const outstanding = data.debts.filter((d) => !d.isSettled);
        const settled = data.debts.filter((d) => d.isSettled);
        const credit = { in: creditMinor(person.id, "RM", 1, input), out: creditMinor(person.id, "RM", -1, input) };
        const creditDebts = (dir: 1 | -1) => outstanding.filter((d) => d.direction === dir);
        const preview = outstanding.length ? planSettleAll(person, "RM", new Date().toISOString(), input) : null;
        return (
          <>
            <PageHeader title={person.name} back={{ href: "/paybook", label: "PayBook" }}
              actions={<>
                <Button size="sm" variant="secondary" className="bg-card shadow-card" onClick={async () => {
                  const lines = [directionText(person.name, net), ...outstanding.map((d) => `• ${d.title} (${formatDate(d.date, { day: "numeric", month: "short" })}): ${formatMoney(d.outstandingMinor)}`), "— shared from SpenDrop"];
                  const r = await shareText(`SpenDrop · ${person.name}`, lines.join("\n"));
                  if (r === "copied") toast("Copied to clipboard");
                }}><Share2 aria-hidden className="size-4" /> <span className="max-sm:sr-only">Share</span></Button>
                <Button size="sm" variant="tinted" onClick={() => setEditing(true)}><Pencil aria-hidden className="size-4" /> <span className="max-sm:sr-only">Edit</span></Button>
              </>} />
            <Page className="grid gap-5 lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
              <div className="flex flex-col gap-5">
                <Card className="flex items-center gap-4">
                  <Avatar name={person.name} size={56} />
                  <div className="min-w-0 flex-1">
                    <p className="section-header">Net balance</p>
                    <p className={cx("text-[22px] font-bold", net > 0 ? "text-green" : net < 0 ? "text-orange" : "text-label-2")}>{net === 0 ? "Settled — nothing owed either way" : directionText(person.name, net)}</p>
                    {(credit.in > 0 || credit.out > 0) && <p className="text-xs text-label-2">{credit.in > 0 ? `${formatMoney(credit.in)} received but not linked to a transaction` : `${formatMoney(credit.out)} paid but not linked to a transaction`}</p>}
                  </div>
                </Card>
                <div className="flex flex-wrap gap-2">
                  <Button onClick={() => setPaying(true)}><HandCoins aria-hidden className="size-4" /> Record Payment</Button>
                  {outstanding.length > 0 && <Button variant="tinted" onClick={() => setConfirmSettleAll(true)}><Check aria-hidden className="size-4" /> Settle All</Button>}
                  {([1, -1] as const).map((dir) => (dir > 0 ? credit.in : credit.out) > 0 && creditDebts(dir).length > 0 && (
                    <Button key={dir} variant="secondary" loading={busy === `credit${dir}`} onClick={() => run(`credit${dir}`, () => {
                      const plan = autoAllocate(dir > 0 ? credit.in : credit.out, creditDebts(dir));
                      return recordSettlement(planApplyCredit(person, dir, plan, "RM", new Date().toISOString(), input));
                    }, "Credit applied")}><Wallet aria-hidden className="size-4" /> Apply credit</Button>
                  ))}
                </div>
                <section aria-labelledby="outstanding-heading">
                  <SectionHeader id="outstanding-heading">Outstanding transactions</SectionHeader>
                  <Card className="overflow-hidden p-0">
                    {outstanding.length === 0 ? <p className="p-4 text-sm text-label-2">Nothing outstanding.</p> : outstanding.map((d, i) => (
                      <div key={d.id}>{i > 0 && <Divider inset={16} />}
                        <div className="flex min-h-14 items-center gap-3 px-4 py-2.5">
                          <div className="min-w-0 flex-1">
                            <Link href={d.source.type === "expense" ? `/transactions/${d.source.id}` : `/transactions/m/${d.source.id}`} className="block truncate font-semibold hover:underline">{d.title}</Link>
                            <p className="text-xs text-label-2">{formatDate(d.date)} · {d.detail}{d.settledMinor > 0 ? ` · ${formatMoney(d.settledMinor)} paid` : ""}</p>
                          </div>
                          <span className={cx("tabular font-bold", d.direction > 0 ? "text-green" : "text-orange")}>{formatMoney(d.outstandingMinor, d.currency)}</span>
                          <Button size="sm" variant="tinted" aria-label={`Mark ${d.title} as paid`} loading={busy === d.id}
                            onClick={() => run(d.id, () => recordSettlement(planMarkPaid(d, person, new Date().toISOString())), "Marked as paid")}>Paid</Button>
                        </div>
                      </div>
                    ))}
                  </Card>
                  <p className="mt-1.5 px-1 text-xs text-label-2">+ means {person.name} owes you more; − means you owe {person.name} more (or they owe you less).</p>
                </section>
                <section aria-labelledby="history-heading">
                  <SectionHeader id="history-heading">History</SectionHeader>
                  <Card className="overflow-hidden p-0">
                    {data.entries.length === 0 ? <p className="p-4 text-sm text-label-2">No shared transactions yet.</p> : data.entries.map((e, i) => (
                      <div key={e.id}>{i > 0 && <Divider inset={16} />}
                        <Link href={e.href} className="flex min-h-12 items-center gap-3 px-4 py-2 hover:bg-card-2">
                          <div className="min-w-0 flex-1"><p className="truncate font-medium">{e.title}</p><p className="text-xs text-label-2">{formatDate(e.date)} · {e.detail}</p></div>
                          <span className={cx("tabular text-sm font-semibold", e.effect > 0 ? "text-green" : e.effect < 0 ? "text-orange" : "text-label-2")}>{e.effect > 0 ? "+" : e.effect < 0 ? "−" : ""}{formatMoney(Math.abs(e.effect))}</span>
                        </Link>
                      </div>
                    ))}
                  </Card>
                </section>
              </div>
              <div className="flex flex-col gap-5">
                <section aria-labelledby="methods-heading">
                  <SectionHeader id="methods-heading" action={<Button size="sm" variant="plain" onClick={() => setMethodSheet("new")}><Plus aria-hidden className="size-4" /> Add</Button>}>Payment accounts</SectionHeader>
                  <Card className="overflow-hidden p-0">
                    {data.methods.length === 0 ? (
                      <EmptyState icon={Wallet} title="No Payment Accounts" message={`Add bank accounts, e-wallets, or payment IDs for ${person.name}.`} />
                    ) : data.methods.map((m, i) => (
                      <div key={m.id}>{i > 0 && <Divider inset={16} />}
                        <div className="flex min-h-14 items-center gap-2 px-4 py-2">
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-semibold">{m.provider}{m.label ? ` · ${m.label}` : ""}</p>
                            <p className="tabular truncate text-sm text-label-2">{m.paymentType} · {m.accountIdentifier}</p>
                          </div>
                          <Button size="sm" variant="plain" aria-label={`Copy ${m.provider} details`} onClick={async () => {
                            try { await navigator.clipboard.writeText(`${person.name}\n${m.provider}\n${m.accountIdentifier}`); toast("Copied"); } catch { toast("Couldn't copy on this browser", { tone: "error" }); }
                          }}><Copy aria-hidden className="size-4" /></Button>
                          <Button size="sm" variant="plain" aria-label={`Edit ${m.provider} details`} onClick={() => setMethodSheet(m)}><Pencil aria-hidden className="size-4" /></Button>
                          <Button size="sm" variant="plain" aria-label={`Delete ${m.provider} details`} className="text-red" onClick={() => run(m.id, () => deleteRecord("paymentMethods", m), "Payment details deleted")}><Trash2 aria-hidden className="size-4" /></Button>
                        </div>
                      </div>
                    ))}
                  </Card>
                </section>
                {data.groups.length > 0 && (
                  <section aria-labelledby="settlements-heading">
                    <SectionHeader id="settlements-heading">Settlement history</SectionHeader>
                    <Card className="overflow-hidden p-0">
                      {data.groups.map((g, i) => (
                        <div key={g.id}>{i > 0 && <Divider inset={16} />}
                          <div className="flex min-h-12 items-center gap-3 px-4 py-2">
                            <div className="flex-1 text-sm">
                              <p className="font-medium">{g.direction > 0 ? `${person.name} paid you` : g.direction < 0 ? `You paid ${person.name}` : "Debts offset"} · {formatMoney(g.totalMinor || g.offsetMinor, g.currency)}</p>
                              <p className="text-xs text-label-2">{formatDate(g.date)} · {g.allocations.length} transaction{g.allocations.length === 1 ? "" : "s"}{g.offsetMinor > 0 && g.totalMinor > 0 ? ` · ${formatMoney(g.offsetMinor)} offset` : ""}</p>
                            </div>
                            <Button size="sm" variant="plain" loading={busy === g.id} onClick={() => run(g.id, () => undoSettlement(g.id), "Undone")}><Undo2 aria-hidden className="size-4" /> Undo</Button>
                          </div>
                        </div>
                      ))}
                    </Card>
                  </section>
                )}
                {settled.length > 0 && <p className="px-1 text-xs text-label-2">{settled.length} settled transaction{settled.length === 1 ? "" : "s"} with {person.name}.</p>}
                {person.notes && <Card><p className="section-header mb-1">Notes</p><p className="whitespace-pre-wrap text-sm">{person.notes}</p></Card>}
                <Button variant="secondary" className="self-start" loading={busy === "archive"}
                  onClick={() => run("archive", () => saveRecords("people", [{ ...person, isArchived: !person.isArchived, updatedAt: new Date().toISOString() }]), person.isArchived ? "Restored" : "Archived")}>
                  <Archive aria-hidden className="size-4" /> {person.isArchived ? "Restore person" : "Archive person"}
                </Button>
              </div>
            </Page>
            {editing && <PersonSheet open={editing} onClose={() => setEditing(false)} person={person} />}
            {methodSheet && <MethodSheet open onClose={() => setMethodSheet(null)} person={person} method={methodSheet === "new" ? undefined : methodSheet} />}
            {paying && <PaymentSheet open onClose={() => setPaying(false)} person={person} debts={data.debts} />}
            <Sheet open={confirmSettleAll} onClose={() => setConfirmSettleAll(false)} title={`Settle all with ${person.name}?`}
              footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirmSettleAll(false)}>Cancel</Button>
                <Button loading={busy === "all"} onClick={() => run("all", async () => { await recordSettlement(planSettleAll(person, "RM", new Date().toISOString(), input)); setConfirmSettleAll(false); }, `Settled with ${person.name}`)}>Settle All</Button></div>}>
              {preview && (
                <div className="flex flex-col gap-2 text-[15px]">
                  {preview.allocations.some((a) => a.kind === "assign") && <p>Earlier payments not yet linked are applied first.</p>}
                  {preview.allocations.some((a) => a.kind === "offset") && <p>Opposite debts cancel each other: {formatMoney(preview.allocations.filter((a) => a.kind === "offset" && a.direction > 0).reduce((s, a) => s + a.amountMinor, 0))} (no money moves).</p>}
                  {preview.payments.map((p) => <p key={p.id} className="font-semibold">{p.kind === "repaymentReceived" ? `${person.name} pays you ${formatMoney(p.amountMinor)}` : `You pay ${person.name} ${formatMoney(p.amountMinor)}`}</p>)}
                  <p className="text-sm text-label-2">One action — Undo restores everything exactly. The original transactions are never changed.</p>
                </div>
              )}
            </Sheet>
          </>
        );
      })()}
    </RecordGate>
  );
}

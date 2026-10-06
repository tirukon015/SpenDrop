"use client";

import { Camera, ChevronDown, ImageUp, LoaderCircle, Sparkles, Trash2, TriangleAlert, Users } from "lucide-react";
import { useRouter } from "next/navigation";
import { useMemo, useRef, useState } from "react";
import { CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { SplitEditor } from "@/components/split-editor";
import { Button, Card, Field, Input, Segmented, Select, Sheet, TextArea, Toggle, cx, tintText, tintVar } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { CATEGORIES, COMMON_FUNDING_ACCOUNTS, MOVEMENT_KINDS, PAYMENT_CHANNELS, channelInfo, kindInfo } from "@/lib/domain/constants";
import { formatDate, fromInputs, toDateInput, toTimeInput } from "@/lib/domain/dates";
import { formatMoney, minorToInput, parseMinor } from "@/lib/domain/money";
import * as S from "@/lib/domain/split";
import type { Account, AccountType, CategoryId, ClassificationRule, ChannelRule, Expense, ID, MoneyMovement, MovementKind, PaymentChannelId, Person } from "@/lib/domain/types";
import { fundingKey, learnedCategory, learnedChannel, merchantKey, ruleKey, suggestCategory, type Suggestion } from "@/lib/ocr/classify";
import { parseReceipt } from "@/lib/ocr/parse";

export type EntryType = "expense" | "moneyIn" | "moneyOut" | "transfer";
const ENTRY_TYPES: { id: EntryType; label: string }[] = [
  { id: "expense", label: "Expense" }, { id: "moneyIn", label: "Money In" }, { id: "moneyOut", label: "Money Out" }, { id: "transfer", label: "Transfer" },
];

const nowIso = () => new Date().toISOString();
const uuid = () => crypto.randomUUID();
const normalized = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");
const guessAccountType = (name: string): AccountType =>
  /^cash$/i.test(name) ? "cash" : /touch|tng|grabpay|boost|shopeepay|e-?wallet|wallet/i.test(name) ? "eWallet" : "bank";

function Hint({ suggestion }: { suggestion: Suggestion<unknown> | null }) {
  if (!suggestion || !suggestion.reason) return null;
  return (
    <p className={cx("flex items-start gap-1.5 px-1 text-xs", suggestion.needsReview ? "text-orange" : "text-label-2")}>
      {suggestion.needsReview ? <TriangleAlert aria-hidden className="mt-0.5 size-3.5 shrink-0" /> : <Sparkles aria-hidden className="mt-0.5 size-3.5 shrink-0" />}
      <span>{suggestion.needsReview ? "Suggested · please check. " : ""}{suggestion.reason}</span>
    </p>
  );
}

interface Props {
  /** Editing an existing expense or movement; omitted for a new transaction. */
  expense?: Expense;
  movement?: MoneyMovement;
}

export function TransactionForm({ expense, movement }: Props) {
  const router = useRouter();
  const toast = useToast();
  const { live, dataset, source, saveExpense, saveRecords } = useData();
  const editing = Boolean(expense || movement);
  const initialType: EntryType = movement
    ? kindInfo(movement.kind).direction === "in" ? "moneyIn" : kindInfo(movement.kind).direction === "out" ? "moneyOut" : "transfer"
    : "expense";

  const [type, setType] = useState<EntryType>(initialType);
  const [amountText, setAmountText] = useState(expense ? minorToInput(expense.amountMinor) : movement ? minorToInput(movement.amountMinor) : "");
  const [merchant, setMerchant] = useState(expense?.merchant ?? "");
  const [category, setCategory] = useState<CategoryId>(expense?.category ?? "Other");
  const [categoryTouched, setCategoryTouched] = useState(editing);
  /** Category evidence from a scanned receipt (the merchant name alone is used otherwise). */
  const [ocrCategory, setOcrCategory] = useState<Suggestion<CategoryId> | null>(null);
  const [funding, setFunding] = useState(expense?.fundingAccount ?? "Unknown");
  const [customFunding, setCustomFunding] = useState(false);
  const [channel, setChannel] = useState<PaymentChannelId>(expense?.paymentChannel ?? movement?.paymentChannel ?? "UNKNOWN");
  const [channelTouched, setChannelTouched] = useState(editing);
  /** Channel evidence from a scanned receipt. */
  const [ocrChannel, setOcrChannel] = useState<Suggestion<PaymentChannelId> | null>(null);
  const initialDate = new Date(expense?.date ?? movement?.date ?? nowIso());
  const [date, setDate] = useState(toDateInput(initialDate));
  const [time, setTime] = useState(toTimeInput(initialDate));
  const [notes, setNotes] = useState(expense?.notes ?? "");
  const [reference, setReference] = useState(expense?.transactionReference ?? movement?.transactionReference ?? "");
  const [showMore, setShowMore] = useState(Boolean(expense?.transactionReference || expense?.notes));
  const [split, setSplit] = useState<S.SplitDraft | null>(() => {
    if (!expense) return null;
    const rows = live.shares.get(expense.id) ?? [];
    return S.draftFromShares(expense, rows, (id) => live.people.find((p) => p.id === id)?.name);
  });
  const [newPeople, setNewPeople] = useState<Person[]>([]);
  // Money movement fields
  const [kind, setKind] = useState<MovementKind>(movement?.kind ?? "income");
  const [accountId, setAccountId] = useState<ID | "">(movement?.accountId ?? "");
  const [counterAccountId, setCounterAccountId] = useState<ID | "">(movement?.counterAccountId ?? "");
  const [personId, setPersonId] = useState<ID | "">(movement?.personId ?? "");
  const [note, setNote] = useState(movement?.note ?? "");
  // Receipt
  const [receipt, setReceipt] = useState<Blob | null>(null);
  const [receiptPreview, setReceiptPreview] = useState<string | null>(null);
  const [removeReceipt, setRemoveReceipt] = useState(false);
  const [scanning, setScanning] = useState<number | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const cameraInput = useRef<HTMLInputElement>(null);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [duplicate, setDuplicate] = useState<Expense | null>(null);

  const amountMinor = parseMinor(amountText) ?? 0;
  const people = useMemo(() => [...live.people, ...newPeople].sort((a, b) => a.name.localeCompare(b.name)), [live.people, newPeople]);
  const merchants = useMemo(() => [...new Set(live.expenses.map((e) => e.merchant))].slice(0, 200), [live.expenses]);
  const fundingOptions = useMemo(() => {
    const names = new Set<string>(COMMON_FUNDING_ACCOUNTS);
    live.accounts.forEach((a) => names.add(a.name));
    if (funding && funding !== "Unknown") names.add(funding);
    return ["Unknown", ...[...names].filter((n) => n !== "Unknown")];
  }, [live.accounts, funding]);
  const kindsForType = MOVEMENT_KINDS.filter((k) => (type === "moneyIn" ? k.direction === "in" : type === "moneyOut" ? k.direction === "out" : k.direction === "internal"));
  const needsPerson = kindInfo(kind).personBalanceSign !== 0;

  function changeType(next: EntryType) {
    setType(next);
    if (next === "transfer") setKind("ownTransfer");
    else if (next !== "expense" && kindInfo(kind).direction !== (next === "moneyIn" ? "in" : "out")) setKind(next === "moneyIn" ? "income" : "loanGiven");
  }

  // Suggestions are derived (never stored over the user's choice): evidence + what the user chose before.
  const suggestedCategory = useMemo(() => {
    if (type !== "expense" || categoryTouched || !merchant.trim()) return null;
    return learnedCategory(merchant, ocrCategory ?? suggestCategory(merchant, merchant), dataset.classificationRules);
  }, [type, categoryTouched, merchant, ocrCategory, dataset.classificationRules]);
  const category_ = categoryTouched ? category : suggestedCategory?.value ?? category;
  const suggestedChannel = useMemo(() => {
    if (type !== "expense" || channelTouched) return null;
    if (ocrChannel && ocrChannel.value !== "UNKNOWN") return ocrChannel;
    return learnedChannel(merchant, funding, "UNKNOWN", dataset.channelRules) ?? ocrChannel;
  }, [type, channelTouched, ocrChannel, merchant, funding, dataset.channelRules]);
  const channel_ = type === "expense" && !channelTouched ? suggestedChannel?.value ?? channel : channel;

  const splitProblem = type === "expense" && split ? S.problem(split, amountMinor) : null;
  const transferProblem = type === "transfer" && (!accountId || !counterAccountId) ? "Choose both accounts." : type === "transfer" && accountId === counterAccountId ? "Choose two different accounts." : null;
  const personProblem = type !== "expense" && type !== "transfer" && needsPerson && !personId ? "Choose who this was with." : null;
  const amountProblem = amountText && !(amountMinor > 0) ? "Enter an amount greater than zero." : null;
  const canSave = amountMinor > 0 && !splitProblem && !transferProblem && !personProblem && !busy;

  async function onPickImage(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) { setError("Choose an image (screenshot or photo of the receipt)."); return; }
    setError(null);
    setScanning(0);
    try {
      const { compressImage, recognizeText } = await import("@/lib/ocr/recognize");
      const compressed = await compressImage(file);
      setReceipt(compressed);
      setRemoveReceipt(false);
      setReceiptPreview((old) => { if (old) URL.revokeObjectURL(old); return URL.createObjectURL(compressed); });
      const lines = await recognizeText(compressed, (p) => setScanning(p));
      const parsed = parseReceipt(lines);
      changeType("expense");
      if (parsed.amountMinor && !amountText) setAmountText(minorToInput(parsed.amountMinor));
      if (parsed.merchant && !merchant) setMerchant(parsed.merchant);
      if (parsed.date) { const d = new Date(parsed.date); setDate(toDateInput(d)); setTime(toTimeInput(d)); }
      if (parsed.reference && !reference) { setReference(parsed.reference); setShowMore(true); }
      if (parsed.funding !== "Unknown" && (funding === "Unknown" || !funding)) setFunding(parsed.funding);
      setOcrChannel(parsed.channel);
      setOcrCategory(parsed.category);
      toast(parsed.amountMinor ? "Receipt read — please check the details before saving." : "Couldn't find an amount — please type it in.", { tone: parsed.amountMinor ? "success" : "error" });
    } catch {
      setError("Couldn't read that image. You can still type the details yourself.");
    } finally {
      setScanning(null);
    }
  }

  function createPerson(name: string): Person {
    const now = nowIso();
    const person: Person = { id: uuid(), name: name.slice(0, 80), notes: null, isFrequent: false, isArchived: false, createdAt: now, updatedAt: now, deletedAt: null };
    setNewPeople((list) => [...list, person]);
    return person;
  }

  /** Same as iOS AccountLinker: an expense's funding account links to (or creates) an Account with that name. */
  function resolveAccount(name: string): { account: Account | null; created: Account | null } {
    if (!name || ["unknown", "other"].includes(normalized(name))) return { account: null, created: null };
    const existing = live.accounts.find((a) => normalized(a.name) === normalized(name));
    if (existing) return { account: existing, created: null };
    const now = nowIso();
    const created: Account = { id: uuid(), name: name.trim().slice(0, 80), type: guessAccountType(name), currency: "RM", icon: null, isArchived: false,
      sortIndex: live.accounts.length, createdAt: now, updatedAt: now, deletedAt: null };
    return { account: created, created };
  }

  function findDuplicate(): Expense | null {
    const ref = reference.trim();
    const day = date;
    return live.expenses.find((e) => e.id !== expense?.id && (
      (ref && e.transactionReference && e.transactionReference.trim() === ref) ||
      (e.amountMinor === amountMinor && toDateInput(new Date(e.date)) === day && normalized(e.merchant) === normalized(merchant || "Unknown"))
    )) ?? null;
  }

  async function learn(finalMerchant: string) {
    const now = nowIso();
    const key = ruleKey(finalMerchant);
    if (!key) return;
    const rules: ClassificationRule[] = [];
    const current = dataset.classificationRules.find((r) => !r.deletedAt && (r.merchantKey === key || r.merchantKey === merchantKey(finalMerchant)));
    rules.push(current
      ? { ...current, category: category_, hitCount: current.category === category_ ? current.hitCount + 1 : 1, updatedAt: now }
      : { id: uuid(), merchantKey: key, category: category_, suggestedType: "expense", accountId: null, hitCount: 1, createdAt: now, updatedAt: now, deletedAt: null });
    await saveRecords("classificationRules", rules);
    if (channel_ !== "UNKNOWN") {
      const fk = fundingKey(funding);
      const existing = dataset.channelRules.find((r) => !r.deletedAt && r.merchantKey === key && r.fundingKey === fk);
      const rule: ChannelRule = existing
        ? { ...existing, channel: channel_, hitCount: existing.channel === channel_ ? existing.hitCount + 1 : 1, updatedAt: now }
        : { id: uuid(), merchantKey: key, fundingKey: fk, channel: channel_, hitCount: 1, createdAt: now, updatedAt: now, deletedAt: null };
      await saveRecords("channelRules", [rule]);
    }
  }

  async function save(skipDuplicateCheck = false) {
    if (!canSave || !source) return;
    setError(null);
    if (type === "expense" && !skipDuplicateCheck) {
      const dup = findDuplicate();
      if (dup) { setDuplicate(dup); return; }
    }
    setBusy(true);
    try {
      const now = nowIso();
      const when = fromInputs(date, time);
      // People created inside the split are saved first (the split refers to them).
      const usedNew = newPeople.filter((p) => split?.participants.some((x) => x.personId === p.id) || split?.payerId === p.id);
      if (usedNew.length) await saveRecords("people", usedNew);

      if (type === "expense") {
        const { account, created } = resolveAccount(funding);
        if (created) await saveRecords("accounts", [created]);
        const id = expense?.id ?? uuid();
        let receiptPath = removeReceipt ? null : expense?.receiptPath ?? null;
        if (receipt) {
          receiptPath = await source.uploadReceipt(receipt, id);
          if (expense?.receiptPath) await source.removeReceipt(expense.receiptPath).catch(() => undefined);
        } else if (removeReceipt && expense?.receiptPath) {
          await source.removeReceipt(expense.receiptPath).catch(() => undefined);
        }
        const rows = split ? S.shareRows(split, amountMinor) : [];
        if (split && !rows) throw new Error("The split doesn't add up to the amount.");
        const existingShares = expense ? live.shares.get(expense.id) ?? [] : [];
        const shares = (rows ?? []).map((r) => {
          const match = existingShares.find((s) => (r.isMe ? s.isMe : s.personId === r.personId));
          return { ...r, id: match?.id ?? uuid(), createdAt: match?.createdAt ?? now, updatedAt: now };
        });
        const finalMerchant = merchant.trim() || "Unknown";
        const record: Expense = {
          id, amountMinor, currency: expense?.currency ?? "RM", merchant: finalMerchant.slice(0, 200), category: category_, paymentChannel: channel_,
          fundingAccount: funding || "Unknown", fundingInstrument: expense?.fundingInstrument ?? null, accountId: account?.id ?? null,
          paymentSource: expense?.paymentSource ?? null, date: when, notes: notes.trim() || null, transactionReference: reference.trim() || null,
          sourceType: expense?.sourceType ?? (receipt ? "screenshot" : "manual"),
          paidByMe: !split?.payerId, payerId: split?.payerId ?? null, payerNameSnapshot: split?.payerName ?? null,
          splitMethod: split ? split.method : null, receiptPath, isSampleData: expense?.isSampleData ?? false,
          createdAt: expense?.createdAt ?? now, updatedAt: now, deletedAt: null,
        };
        await saveExpense(record, shares);
        await learn(finalMerchant).catch(() => undefined);
        toast(editing ? "Expense updated" : "Expense saved");
        router.push(`/transactions/${id}`);
      } else {
        const info = kindInfo(kind);
        const person = people.find((p) => p.id === personId);
        if (person && newPeople.some((p) => p.id === person.id) && !usedNew.includes(person)) await saveRecords("people", [person]);
        const record: MoneyMovement = {
          id: movement?.id ?? uuid(), kind, direction: info.direction, amountMinor, currency: movement?.currency ?? "RM", date: when,
          personId: needsPerson ? personId || null : null, personNameSnapshot: needsPerson ? person?.name ?? null : null,
          linkedExpenseId: movement?.linkedExpenseId ?? null, linkedExpenseSnapshot: movement?.linkedExpenseSnapshot ?? null,
          accountId: accountId || null, counterAccountId: type === "transfer" ? counterAccountId || null : null, note: note.trim() || null,
          transactionReference: reference.trim() || null, sourceType: movement?.sourceType ?? "manual", paymentChannel: channel,
          createdAt: movement?.createdAt ?? now, updatedAt: now, deletedAt: null,
        };
        await saveRecords("movements", [record]);
        toast(editing ? "Saved" : `${info.label} saved`);
        router.push(`/transactions/m/${record.id}`);
      }
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  const ChannelIcon = CHANNEL_ICONS[channel_];

  return (
    <form onSubmit={(e) => { e.preventDefault(); save(); }} className="flex flex-col gap-5" noValidate>
      {!editing && (
        <Segmented label="Record type" value={type} onChange={changeType} options={ENTRY_TYPES} />
      )}

      {/* Amount */}
      <Card className="flex flex-col items-center gap-1 py-6">
        <label htmlFor="amount" className="section-header">Enter amount</label>
        <div className="flex items-baseline justify-center gap-2">
          <span className="text-[28px] font-bold text-label-2">RM</span>
          <input id="amount" inputMode="decimal" autoComplete="off" placeholder="0.00" value={amountText} autoFocus={!editing}
            onChange={(e) => setAmountText(e.target.value.replace(/[^\d.,]/g, ""))}
            aria-invalid={Boolean(amountProblem)} aria-describedby={amountProblem ? "amount-error" : undefined}
            className="tabular w-full max-w-[260px] bg-transparent text-center text-[44px] font-bold tracking-tight placeholder:text-label-3 focus:outline-none" />
        </div>
        {amountProblem && <p id="amount-error" role="alert" className="text-xs text-red">{amountProblem}</p>}
        {type === "expense" && (
          <div className="mt-3 flex flex-wrap justify-center gap-2">
            <input ref={cameraInput} type="file" accept="image/*" capture="environment" className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => onPickImage(e.target.files?.[0])} />
            <input ref={fileInput} type="file" accept="image/*" className="sr-only" tabIndex={-1} aria-hidden onChange={(e) => onPickImage(e.target.files?.[0])} />
            <Button type="button" variant="tinted" size="sm" onClick={() => cameraInput.current?.click()} disabled={scanning !== null} className="md:hidden">
              <Camera aria-hidden className="size-4" /> Scan receipt
            </Button>
            <Button type="button" variant="tinted" size="sm" onClick={() => fileInput.current?.click()} disabled={scanning !== null}>
              <ImageUp aria-hidden className="size-4" /> {receiptPreview || expense?.receiptPath ? "Replace receipt" : "Add screenshot"}
            </Button>
          </div>
        )}
        {scanning !== null && (
          <p role="status" className="mt-2 flex items-center gap-2 text-sm text-label-2"><LoaderCircle aria-hidden className="size-4 animate-spin" /> Reading receipt on this device… {Math.round(scanning * 100)}%</p>
        )}
        {(receiptPreview || (expense?.receiptPath && !removeReceipt)) && (
          <div className="mt-3 flex items-center gap-3">
            {/* eslint-disable-next-line @next/next/no-img-element -- local blob preview, not optimisable */}
            {receiptPreview && <img src={receiptPreview} alt="Receipt preview" className="h-20 w-auto rounded-lg border border-separator object-cover" />}
            {!receiptPreview && <span className="text-xs text-label-2">Receipt attached</span>}
            <Button type="button" variant="destructive" size="sm" onClick={() => { setReceipt(null); setReceiptPreview(null); setRemoveReceipt(true); }}>
              <Trash2 aria-hidden className="size-4" /> Remove
            </Button>
          </div>
        )}
      </Card>

      {type === "expense" ? (
        <>
          <Field label="Merchant / Recipient" htmlFor="merchant">
            <Input id="merchant" list="merchant-list" autoComplete="off" placeholder="e.g. Tealive, Jaya Grocer, Bijoy" value={merchant} onChange={(e) => setMerchant(e.target.value)} />
            <datalist id="merchant-list">{merchants.map((m) => <option key={m} value={m} />)}</datalist>
          </Field>

          <fieldset className="flex flex-col gap-1.5">
            <legend className="section-header mb-1.5 px-1">Category</legend>
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-6">
              {CATEGORIES.map((c) => {
                const Icon = CATEGORY_ICONS[c.id];
                const selected = category_ === c.id;
                return (
                  <button key={c.id} type="button" aria-pressed={selected} onClick={() => { setCategory(c.id); setCategoryTouched(true); }}
                    className={cx("flex min-h-[62px] flex-col items-center justify-center gap-1 rounded-[12px] border-2 bg-card px-1 text-xs font-medium shadow-card transition-colors",
                      selected ? "border-current" : "border-transparent hover:bg-card-2")}
                    style={selected ? { color: tintText(c.tint) } : undefined}>
                    <Icon aria-hidden className="size-5" style={{ color: tintVar(c.tint) }} />
                    <span className={selected ? "" : "text-label"}>{c.id}</span>
                  </button>
                );
              })}
            </div>
            {!categoryTouched && suggestedCategory && suggestedCategory.confidence > 0 && <Hint suggestion={suggestedCategory} />}
          </fieldset>

          <div className="grid gap-4 md:grid-cols-2">
            <Field label="Funding account (where money came from)" htmlFor="funding">
              {customFunding ? (
                <div className="flex gap-2">
                  <Input id="funding" autoFocus placeholder="e.g. Maybank Savings" value={funding === "Unknown" ? "" : funding} onChange={(e) => setFunding(e.target.value)} />
                  <Button type="button" variant="secondary" onClick={() => setCustomFunding(false)}>Done</Button>
                </div>
              ) : (
                <Select id="funding" value={funding} onChange={(e) => (e.target.value === "__new" ? setCustomFunding(true) : setFunding(e.target.value))}>
                  {fundingOptions.map((name) => <option key={name} value={name}>{name}</option>)}
                  <option value="__new">New account…</option>
                </Select>
              )}
            </Field>
            <Field label="Payment channel (how payment was made)" htmlFor="channel"
              hint={channel_ === "UNKNOWN" ? "Unknown is fine when the receipt doesn't say." : undefined}>
              <div className="relative">
                <ChannelIcon aria-hidden className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2" style={{ color: tintVar(channelInfo(channel_).tint) }} />
                <Select id="channel" className="pl-10" value={channel_} onChange={(e) => { setChannel(e.target.value as PaymentChannelId); setChannelTouched(true); }}>
                  {PAYMENT_CHANNELS.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
                </Select>
              </div>
              {!channelTouched && suggestedChannel && suggestedChannel.value !== "UNKNOWN" && <Hint suggestion={suggestedChannel} />}
            </Field>
          </div>
        </>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {type !== "transfer" && (
            <Field label="Type" htmlFor="kind">
              <Select id="kind" value={kind} onChange={(e) => setKind(e.target.value as MovementKind)}>
                {kindsForType.map((k) => <option key={k.id} value={k.id}>{k.label}</option>)}
              </Select>
            </Field>
          )}
          {needsPerson && type !== "transfer" && (
            <Field label={kind === "loanGiven" || kind === "repaymentMade" ? "To" : "From"} htmlFor="person" error={amountMinor > 0 ? personProblem : null}>
              <Select id="person" value={personId} onChange={(e) => setPersonId(e.target.value)}>
                <option value="">Choose a person…</option>
                {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </Select>
            </Field>
          )}
          <Field label={type === "transfer" ? "From account" : type === "moneyIn" ? "Into account" : "From account"} htmlFor="account">
            <Select id="account" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              <option value="">{type === "transfer" ? "Choose an account…" : "Not linked to an account"}</option>
              {live.accounts.filter((a) => !a.isArchived).map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </Select>
          </Field>
          {type === "transfer" && (
            <Field label="To account" htmlFor="counter" error={amountMinor > 0 ? transferProblem : null}
              hint={live.accounts.length < 2 ? "Add accounts in More → Accounts first." : "Own transfers are never counted as income or spending."}>
              <Select id="counter" value={counterAccountId} onChange={(e) => setCounterAccountId(e.target.value)}>
                <option value="">Choose an account…</option>
                {live.accounts.filter((a) => !a.isArchived).map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
              </Select>
            </Field>
          )}
          <Field label="Note" htmlFor="note">
            <Input id="note" placeholder={type === "moneyIn" ? "e.g. Salary" : "Optional"} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <Field label="Payment channel" htmlFor="m-channel">
            <Select id="m-channel" value={channel} onChange={(e) => setChannel(e.target.value as PaymentChannelId)}>
              {PAYMENT_CHANNELS.map((c) => <option key={c.id} value={c.id}>{c.label}</option>)}
            </Select>
          </Field>
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        <Field label="Date" htmlFor="date"><Input id="date" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
        <Field label="Time" htmlFor="time"><Input id="time" type="time" value={time} onChange={(e) => setTime(e.target.value)} /></Field>
      </div>

      {type === "expense" && (
        <>
          <button type="button" onClick={() => setShowMore((v) => !v)} aria-expanded={showMore} className="-mt-1 flex items-center gap-1 self-start px-1 text-sm font-medium text-[var(--sd-accent-text)]">
            <ChevronDown aria-hidden className={cx("size-4 transition-transform", showMore && "rotate-180")} /> Description & reference
          </button>
          {showMore && (
            <div className="grid gap-4 md:grid-cols-2">
              <Field label="Description" htmlFor="notes"><TextArea id="notes" placeholder="e.g. Lunch with team" value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
              <Field label="Reference" htmlFor="reference" hint="Used to spot duplicates."><Input id="reference" placeholder="Transaction / reference number" value={reference} onChange={(e) => setReference(e.target.value)} /></Field>
            </div>
          )}

          {/* Split Transaction: off = normal expense; on = split right here before saving */}
          <Card className="flex flex-col gap-3">
            <Toggle id="split-toggle" checked={split !== null} onChange={(on) => setSplit(on ? S.newDraft() : null)}
              label={<span className="flex items-center gap-2"><Users aria-hidden className="size-4 text-blue" /> Split Transaction</span>}
              description="Share this amount with people in PayBook" />
            {split && (
              <>
                <div className="h-px bg-separator" />
                {amountMinor > 0 ? (
                  <SplitEditor draft={split} onChange={setSplit} totalMinor={amountMinor} currency="RM" people={people} onCreatePerson={createPerson} />
                ) : (
                  <p className="text-sm text-label-2">Enter the amount first.</p>
                )}
              </>
            )}
          </Card>
        </>
      )}

      {error && <p role="alert" className="rounded-field bg-[color-mix(in_srgb,var(--sd-red)_10%,transparent)] p-3 text-sm">{error}</p>}

      <div className="sticky bottom-[calc(64px+env(safe-area-inset-bottom))] z-10 -mx-4 border-t border-separator bg-bg/90 px-4 py-3 backdrop-blur md:static md:mx-0 md:border-0 md:bg-transparent md:p-0">
        <Button type="submit" size="lg" className="w-full" disabled={!canSave} loading={busy}>
          {busy ? "Saving…" : editing ? "Save Changes" : type === "expense" ? `Save Expense${amountMinor > 0 ? ` · ${formatMoney(amountMinor)}` : ""}` : `Save ${ENTRY_TYPES.find((t) => t.id === type)!.label}`}
        </Button>
        {splitProblem && amountMinor > 0 && <p className="mt-1.5 text-center text-xs text-orange">Fix the split to save: {splitProblem}</p>}
      </div>

      <Sheet open={duplicate !== null} onClose={() => setDuplicate(null)} title="Possible duplicate"
        footer={<div className="flex justify-end gap-2"><Button type="button" variant="secondary" onClick={() => setDuplicate(null)}>Cancel</Button>
          <Button type="button" onClick={() => { setDuplicate(null); save(true); }}>Save Anyway</Button></div>}>
        {duplicate && (
          <p className="text-[15px]">
            {duplicate.transactionReference && duplicate.transactionReference === reference.trim()
              ? `An expense with the same reference (${duplicate.transactionReference}) is already recorded:`
              : "A matching expense is already recorded:"}{" "}
            <strong>{duplicate.merchant}</strong> · {formatMoney(duplicate.amountMinor, duplicate.currency)} on {formatDate(duplicate.date)}.
          </p>
        )}
      </Sheet>
    </form>
  );
}

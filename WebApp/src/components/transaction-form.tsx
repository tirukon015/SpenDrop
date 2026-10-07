"use client";

import { Camera, ChevronDown, ImageUp, LoaderCircle, Sparkles, Trash2, TriangleAlert, Users } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from "react";
import { CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { useData } from "@/components/providers/data-provider";
import { SplitEditor } from "@/components/split-editor";
import { Button, Card, Field, Input, Segmented, Select, Sheet, TextArea, Toggle, cx, tintText, tintVar } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { CATEGORIES, COMMON_FUNDING_ACCOUNTS, MOVEMENT_KINDS, PAYMENT_CHANNELS, channelInfo } from "@/lib/domain/constants";
import { formatDate, toDateInput, toTimeInput } from "@/lib/domain/dates";
import { formatMoney, minorToInput } from "@/lib/domain/money";
import * as S from "@/lib/domain/split";
import type { Expense, ID, MoneyMovement, MovementKind, PaymentChannelId, Person } from "@/lib/domain/types";
import type { Suggestion } from "@/lib/ocr/classify";
import { parseReceipt } from "@/lib/ocr/parse";
import { ENTRY_TYPES, deriveDraft, draftDuplicate, initialDraft, persistDraft, withType, type EntryType, type TransactionDraft } from "@/lib/transaction-draft";

export type { EntryType } from "@/lib/transaction-draft";

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
  /**
   * Draft mode (Bulk Import): the parent owns the draft. Nothing is saved, no duplicate prompt and no navigation;
   * the parent saves the draft later with persistDraft. Both must be given together.
   */
  value?: TransactionDraft;
  onChange?: Dispatch<SetStateAction<TransactionDraft>>;
  /** Draft mode: preview URL of the draft's receipt (owned and revoked by the parent). */
  receiptPreviewUrl?: string | null;
}

export function TransactionForm({ expense, movement, value, onChange, receiptPreviewUrl }: Props) {
  const router = useRouter();
  const toast = useToast();
  const { live, dataset, source, saveExpense, saveRecords } = useData();
  const editing = Boolean(expense || movement);
  const draftMode = Boolean(value && onChange);

  const [ownDraft, setOwnDraft] = useState<TransactionDraft>(() => initialDraft(live, expense, movement));
  const d = draftMode ? value! : ownDraft;
  const setDraft = draftMode ? onChange! : setOwnDraft;
  const patch = (p: Partial<TransactionDraft>) => setDraft((prev) => ({ ...prev, ...p }));
  const { type, amountText, merchant, categoryTouched, funding, channel, channelTouched, date, time, notes, reference, split,
    newPeople, kind, accountId, counterAccountId, personId, note, receipt, removeReceipt } = d;
  const setAmountText = (v: string) => patch({ amountText: v });
  const setMerchant = (v: string) => patch({ merchant: v });
  const setFunding = (v: string) => patch({ funding: v });
  const setDate = (v: string) => patch({ date: v });
  const setTime = (v: string) => patch({ time: v });
  const setNotes = (v: string) => patch({ notes: v });
  const setReference = (v: string) => patch({ reference: v });
  const setSplit = (v: S.SplitDraft | null) => patch({ split: v });
  const setKind = (v: MovementKind) => patch({ kind: v });
  const setAccountId = (v: ID | "") => patch({ accountId: v });
  const setCounterAccountId = (v: ID | "") => patch({ counterAccountId: v });
  const setPersonId = (v: ID | "") => patch({ personId: v });
  const setNote = (v: string) => patch({ note: v });

  const [customFunding, setCustomFunding] = useState(false);
  const [showMore, setShowMore] = useState(Boolean(expense?.transactionReference || expense?.notes || (draftMode && (value!.reference || value!.notes))));
  // Receipt
  const [ownPreview, setReceiptPreview] = useState<string | null>(null);
  const receiptPreview = ownPreview ?? (draftMode && receipt ? receiptPreviewUrl ?? null : null);
  const [scanning, setScanning] = useState<number | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);
  const cameraInput = useRef<HTMLInputElement>(null);
  // Our own preview URL is released when the form goes away.
  const previewRef = useRef<string | null>(null);
  useEffect(() => { previewRef.current = ownPreview; }, [ownPreview]);
  useEffect(() => () => { if (previewRef.current) URL.revokeObjectURL(previewRef.current); }, []);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [duplicate, setDuplicate] = useState<Expense | null>(null);

  const people = useMemo(() => [...live.people, ...newPeople].sort((a, b) => a.name.localeCompare(b.name)), [live.people, newPeople]);
  const merchants = useMemo(() => [...new Set(live.expenses.map((e) => e.merchant))].slice(0, 200), [live.expenses]);
  const fundingOptions = useMemo(() => {
    const names = new Set<string>(COMMON_FUNDING_ACCOUNTS);
    live.accounts.forEach((a) => names.add(a.name));
    if (funding && funding !== "Unknown") names.add(funding);
    return ["Unknown", ...[...names].filter((n) => n !== "Unknown")];
  }, [live.accounts, funding]);
  const kindsForType = MOVEMENT_KINDS.filter((k) => (type === "moneyIn" ? k.direction === "in" : type === "moneyOut" ? k.direction === "out" : k.direction === "internal"));

  function changeType(next: EntryType) {
    setDraft((prev) => withType(prev, next));
  }

  // Suggestions are derived (never stored over the user's choice): evidence + what the user chose before.
  const derived = useMemo(() => deriveDraft(d, dataset), [d, dataset]);
  const { amountMinor, suggestedCategory, suggestedChannel, needsPerson, splitProblem, transferProblem, personProblem, amountProblem } = derived;
  const category_ = derived.category;
  const channel_ = derived.channel;
  const canSave = derived.valid && !busy;

  async function onPickImage(file: File | undefined) {
    if (!file) return;
    if (!file.type.startsWith("image/")) { setError("Choose an image (screenshot or photo of the receipt)."); return; }
    setError(null);
    setScanning(0);
    try {
      const { compressImage, recognizeText } = await import("@/lib/ocr/recognize");
      const compressed = await compressImage(file);
      patch({ receipt: compressed, removeReceipt: false });
      setReceiptPreview((old) => { if (old) URL.revokeObjectURL(old); return URL.createObjectURL(compressed); });
      const lines = await recognizeText(compressed, (p) => setScanning(p));
      const parsed = parseReceipt(lines);
      changeType("expense");
      if (parsed.amountMinor && !amountText) setAmountText(minorToInput(parsed.amountMinor));
      if (parsed.merchant && !merchant) setMerchant(parsed.merchant);
      if (parsed.date) { const dt = new Date(parsed.date); patch({ date: toDateInput(dt), time: toTimeInput(dt) }); }
      if (parsed.reference && !reference) { setReference(parsed.reference); setShowMore(true); }
      if (parsed.funding !== "Unknown" && (funding === "Unknown" || !funding)) setFunding(parsed.funding);
      patch({ ocrChannel: parsed.channel, ocrCategory: parsed.category });
      toast(parsed.amountMinor ? "Receipt read — please check the details before saving." : "Couldn't find an amount — please type it in.", { tone: parsed.amountMinor ? "success" : "error" });
    } catch {
      setError("Couldn't read that image. You can still type the details yourself.");
    } finally {
      setScanning(null);
    }
  }

  function createPerson(name: string): Person {
    const now = new Date().toISOString();
    const person: Person = { id: crypto.randomUUID(), name: name.slice(0, 80), notes: null, isFrequent: false, isArchived: false, createdAt: now, updatedAt: now, deletedAt: null };
    setDraft((prev) => ({ ...prev, newPeople: [...prev.newPeople, person] }));
    return person;
  }

  async function save(skipDuplicateCheck = false) {
    if (draftMode || !canSave || !source) return;
    setError(null);
    if (type === "expense" && !skipDuplicateCheck) {
      const dup = draftDuplicate(d, live.expenses, expense?.id);
      if (dup) { setDuplicate(dup); return; }
    }
    setBusy(true);
    try {
      const result = await persistDraft(d, { live, dataset, source, saveExpense, saveRecords, expense, movement });
      if (result.kind === "expense") {
        toast(editing ? "Expense updated" : "Expense saved");
        router.push(`/transactions/${result.id}`);
      } else {
        toast(editing ? "Saved" : `${result.label} saved`);
        router.push(`/transactions/m/${result.id}`);
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
          <input id="amount" inputMode="decimal" autoComplete="off" placeholder="0.00" value={amountText} autoFocus={!editing && !draftMode}
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
            <Button type="button" variant="destructive" size="sm" onClick={() => { patch({ receipt: null, removeReceipt: true }); setReceiptPreview((old) => { if (old) URL.revokeObjectURL(old); return null; }); }}>
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
                  <button key={c.id} type="button" aria-pressed={selected} onClick={() => patch({ category: c.id, categoryTouched: true })}
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
                <Select id="channel" className="pl-10" value={channel_} onChange={(e) => patch({ channel: e.target.value as PaymentChannelId, channelTouched: true })}>
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
            <Select id="m-channel" value={channel} onChange={(e) => patch({ channel: e.target.value as PaymentChannelId })}>
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

      {!draftMode && <div className="sticky bottom-[calc(64px+env(safe-area-inset-bottom))] z-10 -mx-4 border-t border-separator bg-bg/90 px-4 py-3 backdrop-blur md:static md:mx-0 md:border-0 md:bg-transparent md:p-0">
        <Button type="submit" size="lg" className="w-full" disabled={!canSave} loading={busy}>
          {busy ? "Saving…" : editing ? "Save Changes" : type === "expense" ? `Save Expense${amountMinor > 0 ? ` · ${formatMoney(amountMinor)}` : ""}` : `Save ${ENTRY_TYPES.find((t) => t.id === type)!.label}`}
        </Button>
        {splitProblem && amountMinor > 0 && <p className="mt-1.5 text-center text-xs text-orange">Fix the split to save: {splitProblem}</p>}
      </div>}

      {!draftMode && <Sheet open={duplicate !== null} onClose={() => setDuplicate(null)} title="Possible duplicate"
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
      </Sheet>}
    </form>
  );
}

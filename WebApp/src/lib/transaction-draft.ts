// The transaction editor's state ("draft") and its save path, shared by TransactionForm (Add / Edit pages) and
// Bulk Import (one draft per detected transaction). Moved out of transaction-form.tsx without changing behaviour.
import type { DataContextValue } from "@/components/providers/data-provider";
import { kindInfo } from "@/lib/domain/constants";
import { fromInputs, toDateInput, toTimeInput } from "@/lib/domain/dates";
import { findDuplicateExpense } from "@/lib/domain/duplicates";
import { minorToInput, parseMinor } from "@/lib/domain/money";
import * as S from "@/lib/domain/split";
import type { Account, AccountType, CategoryId, ChannelRule, ClassificationRule, Dataset, Expense, ID, MoneyMovement, MovementKind, PaymentChannelId, Person } from "@/lib/domain/types";
import { fundingKey, learnedCategory, learnedChannel, merchantKey, ruleKey, suggestCategory, type Suggestion } from "@/lib/ocr/classify";

export type EntryType = "expense" | "moneyIn" | "moneyOut" | "transfer";
export const ENTRY_TYPES: { id: EntryType; label: string }[] = [
  { id: "expense", label: "Expense" }, { id: "moneyIn", label: "Money In" }, { id: "moneyOut", label: "Money Out" }, { id: "transfer", label: "Transfer" },
];

/** Everything the user can edit in the transaction editor. */
export interface TransactionDraft {
  type: EntryType;
  amountText: string;
  merchant: string;
  category: CategoryId;
  categoryTouched: boolean;
  /** Category evidence from a scanned receipt (the merchant name alone is used otherwise). */
  ocrCategory: Suggestion<CategoryId> | null;
  funding: string;
  channel: PaymentChannelId;
  channelTouched: boolean;
  /** Channel evidence from a scanned receipt. */
  ocrChannel: Suggestion<PaymentChannelId> | null;
  date: string;
  time: string;
  notes: string;
  reference: string;
  split: S.SplitDraft | null;
  /** People created inside the split (saved with the transaction). */
  newPeople: Person[];
  // Money movement fields
  kind: MovementKind;
  accountId: ID | "";
  counterAccountId: ID | "";
  personId: ID | "";
  note: string;
  // Receipt
  receipt: Blob | null;
  removeReceipt: boolean;
}

type Live = DataContextValue["live"];

const nowIso = () => new Date().toISOString();
const uuid = () => crypto.randomUUID();
const normalized = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");
const guessAccountType = (name: string): AccountType =>
  /^cash$/i.test(name) ? "cash" : /touch|tng|grabpay|boost|shopeepay|e-?wallet|wallet/i.test(name) ? "eWallet" : "bank";

/** The editor's starting state: a new transaction, or the saved expense / movement being edited. */
export function initialDraft(live: Pick<Live, "shares" | "people">, expense?: Expense, movement?: MoneyMovement): TransactionDraft {
  const editing = Boolean(expense || movement);
  const type: EntryType = movement
    ? kindInfo(movement.kind).direction === "in" ? "moneyIn" : kindInfo(movement.kind).direction === "out" ? "moneyOut" : "transfer"
    : "expense";
  const initialDate = new Date(expense?.date ?? movement?.date ?? nowIso());
  return {
    type,
    amountText: expense ? minorToInput(expense.amountMinor) : movement ? minorToInput(movement.amountMinor) : "",
    merchant: expense?.merchant ?? "",
    category: expense?.category ?? "Other",
    categoryTouched: editing,
    ocrCategory: null,
    funding: expense?.fundingAccount ?? "Unknown",
    channel: expense?.paymentChannel ?? movement?.paymentChannel ?? "UNKNOWN",
    channelTouched: editing,
    ocrChannel: null,
    date: toDateInput(initialDate),
    time: toTimeInput(initialDate),
    notes: expense?.notes ?? "",
    reference: expense?.transactionReference ?? movement?.transactionReference ?? "",
    split: expense ? S.draftFromShares(expense, live.shares.get(expense.id) ?? [], (id) => live.people.find((p) => p.id === id)?.name) : null,
    newPeople: [],
    kind: movement?.kind ?? "income",
    accountId: movement?.accountId ?? "",
    counterAccountId: movement?.counterAccountId ?? "",
    personId: movement?.personId ?? "",
    note: movement?.note ?? "",
    receipt: null,
    removeReceipt: false,
  };
}

/** Switching record type keeps a movement kind that fits the new direction (as the editor always did). */
export function withType(d: TransactionDraft, next: EntryType): TransactionDraft {
  let kind = d.kind;
  if (next === "transfer") kind = "ownTransfer";
  else if (next !== "expense" && kindInfo(kind).direction !== (next === "moneyIn" ? "in" : "out")) kind = next === "moneyIn" ? "income" : "loanGiven";
  return { ...d, type: next, kind };
}

export interface DerivedDraft {
  amountMinor: number;
  suggestedCategory: Suggestion<CategoryId> | null;
  /** The category that will be saved. */
  category: CategoryId;
  suggestedChannel: Suggestion<PaymentChannelId> | null;
  /** The payment channel that will be saved. */
  channel: PaymentChannelId;
  needsPerson: boolean;
  splitProblem: string | null;
  transferProblem: string | null;
  personProblem: string | null;
  amountProblem: string | null;
  /** All checks pass (the editor's Save button is enabled when this is true and nothing is saving). */
  valid: boolean;
}

/** Suggestions are derived (never stored over the user's choice): evidence + what the user chose before. */
export function deriveDraft(d: TransactionDraft, rules: Pick<Dataset, "classificationRules" | "channelRules">): DerivedDraft {
  const amountMinor = parseMinor(d.amountText) ?? 0;
  const suggestedCategory = d.type !== "expense" || d.categoryTouched || !d.merchant.trim()
    ? null
    : learnedCategory(d.merchant, d.ocrCategory ?? suggestCategory(d.merchant, d.merchant), rules.classificationRules);
  const category = d.categoryTouched ? d.category : suggestedCategory?.value ?? d.category;
  let suggestedChannel: Suggestion<PaymentChannelId> | null = null;
  if (d.type === "expense" && !d.channelTouched) {
    suggestedChannel = d.ocrChannel && d.ocrChannel.value !== "UNKNOWN"
      ? d.ocrChannel
      : learnedChannel(d.merchant, d.funding, "UNKNOWN", rules.channelRules) ?? d.ocrChannel;
  }
  const channel = d.type === "expense" && !d.channelTouched ? suggestedChannel?.value ?? d.channel : d.channel;
  const needsPerson = kindInfo(d.kind).personBalanceSign !== 0;
  const splitProblem = d.type === "expense" && d.split ? S.problem(d.split, amountMinor) : null;
  const transferProblem = d.type === "transfer" && (!d.accountId || !d.counterAccountId) ? "Choose both accounts." : d.type === "transfer" && d.accountId === d.counterAccountId ? "Choose two different accounts." : null;
  const personProblem = d.type !== "expense" && d.type !== "transfer" && needsPerson && !d.personId ? "Choose who this was with." : null;
  const amountProblem = d.amountText && !(amountMinor > 0) ? "Enter an amount greater than zero." : null;
  const valid = amountMinor > 0 && !splitProblem && !transferProblem && !personProblem;
  return { amountMinor, suggestedCategory, category, suggestedChannel, channel, needsPerson, splitProblem, transferProblem, personProblem, amountProblem, valid };
}

/** The existing Web duplicate check for this draft (expenses only; money movements are never checked). */
export function draftDuplicate<T extends Parameters<typeof findDuplicateExpense>[1][number]>(d: TransactionDraft, against: readonly T[], editingId?: ID | null): T | null {
  if (d.type !== "expense") return null;
  return findDuplicateExpense({ id: editingId, amountMinor: parseMinor(d.amountText) ?? 0, merchant: d.merchant, date: d.date, reference: d.reference }, against);
}

export interface SaveContext {
  live: Live;
  dataset: Dataset;
  source: NonNullable<DataContextValue["source"]>;
  saveExpense: DataContextValue["saveExpense"];
  saveRecords: DataContextValue["saveRecords"];
  /** The saved record being edited, if any. */
  expense?: Expense;
  movement?: MoneyMovement;
  /** Source type for a new money movement (expenses use "screenshot" when a receipt is attached). Default "manual". */
  movementSourceType?: string;
}

/** `createdAccount`: the Account linked from the funding name, when this save created it. */
export type SaveResult = { kind: "expense"; id: ID; createdAccount: Account | null } | { kind: "movement"; id: ID; label: string };

/** Same as iOS AccountLinker: an expense's funding account links to (or creates) an Account with that name. */
function resolveAccount(name: string, accounts: Account[]): { account: Account | null; created: Account | null } {
  if (!name || ["unknown", "other"].includes(normalized(name))) return { account: null, created: null };
  const existing = accounts.find((a) => normalized(a.name) === normalized(name));
  if (existing) return { account: existing, created: null };
  const now = nowIso();
  const created: Account = { id: uuid(), name: name.trim().slice(0, 80), type: guessAccountType(name), currency: "RM", icon: null, isArchived: false,
    sortIndex: accounts.length, createdAt: now, updatedAt: now, deletedAt: null };
  return { account: created, created };
}

async function learn(ctx: SaveContext, finalMerchant: string, category: CategoryId, channel: PaymentChannelId, funding: string) {
  const { dataset, saveRecords } = ctx;
  const now = nowIso();
  const key = ruleKey(finalMerchant);
  if (!key) return;
  const rules: ClassificationRule[] = [];
  const current = dataset.classificationRules.find((r) => !r.deletedAt && (r.merchantKey === key || r.merchantKey === merchantKey(finalMerchant)));
  rules.push(current
    ? { ...current, category, hitCount: current.category === category ? current.hitCount + 1 : 1, updatedAt: now }
    : { id: uuid(), merchantKey: key, category, suggestedType: "expense", accountId: null, hitCount: 1, createdAt: now, updatedAt: now, deletedAt: null });
  await saveRecords("classificationRules", rules);
  if (channel !== "UNKNOWN") {
    const fk = fundingKey(funding);
    const existing = dataset.channelRules.find((r) => !r.deletedAt && r.merchantKey === key && r.fundingKey === fk);
    const rule: ChannelRule = existing
      ? { ...existing, channel, hitCount: existing.channel === channel ? existing.hitCount + 1 : 1, updatedAt: now }
      : { id: uuid(), merchantKey: key, fundingKey: fk, channel, hitCount: 1, createdAt: now, updatedAt: now, deletedAt: null };
    await saveRecords("channelRules", [rule]);
  }
}

/**
 * Saves one draft through the normal save path: people created in the split, a linked account, the receipt upload,
 * then the expense with its shares (or the money movement). Throws on failure; the caller reports it.
 */
export async function persistDraft(d: TransactionDraft, ctx: SaveContext): Promise<SaveResult> {
  const { live, source, saveExpense, saveRecords, expense, movement } = ctx;
  const derived = deriveDraft(d, ctx.dataset);
  const { amountMinor, needsPerson } = derived;
  const split = d.split;
  const now = nowIso();
  const when = fromInputs(d.date, d.time);
  // People created inside the split are saved first (the split refers to them).
  const usedNew = d.newPeople.filter((p) => split?.participants.some((x) => x.personId === p.id) || split?.payerId === p.id);
  if (usedNew.length) await saveRecords("people", usedNew);

  if (d.type === "expense") {
    const { account, created } = resolveAccount(d.funding, live.accounts);
    if (created) await saveRecords("accounts", [created]);
    const id = expense?.id ?? uuid();
    let receiptPath = d.removeReceipt ? null : expense?.receiptPath ?? null;
    if (d.receipt) {
      receiptPath = await source.uploadReceipt(d.receipt, id);
      if (expense?.receiptPath) await source.removeReceipt(expense.receiptPath).catch(() => undefined);
    } else if (d.removeReceipt && expense?.receiptPath) {
      await source.removeReceipt(expense.receiptPath).catch(() => undefined);
    }
    const rows = split ? S.shareRows(split, amountMinor) : [];
    if (split && !rows) throw new Error("The split doesn't add up to the amount.");
    const existingShares = expense ? live.shares.get(expense.id) ?? [] : [];
    const shares = (rows ?? []).map((r) => {
      const match = existingShares.find((s) => (r.isMe ? s.isMe : s.personId === r.personId));
      return { ...r, id: match?.id ?? uuid(), createdAt: match?.createdAt ?? now, updatedAt: now };
    });
    const finalMerchant = d.merchant.trim() || "Unknown";
    const record: Expense = {
      id, amountMinor, currency: expense?.currency ?? "RM", merchant: finalMerchant.slice(0, 200), category: derived.category, paymentChannel: derived.channel,
      fundingAccount: d.funding || "Unknown", fundingInstrument: expense?.fundingInstrument ?? null, accountId: account?.id ?? null,
      paymentSource: expense?.paymentSource ?? null, date: when, notes: d.notes.trim() || null, transactionReference: d.reference.trim() || null,
      sourceType: expense?.sourceType ?? (d.receipt ? "screenshot" : "manual"),
      paidByMe: !split?.payerId, payerId: split?.payerId ?? null, payerNameSnapshot: split?.payerName ?? null,
      splitMethod: split ? split.method : null, receiptPath, isSampleData: expense?.isSampleData ?? false,
      createdAt: expense?.createdAt ?? now, updatedAt: now, deletedAt: null,
    };
    await saveExpense(record, shares);
    await learn(ctx, finalMerchant, derived.category, derived.channel, d.funding).catch(() => undefined);
    return { kind: "expense", id, createdAccount: created };
  }
  const info = kindInfo(d.kind);
  const people = [...live.people, ...d.newPeople];
  const person = people.find((p) => p.id === d.personId);
  if (person && d.newPeople.some((p) => p.id === person.id) && !usedNew.includes(person)) await saveRecords("people", [person]);
  const record: MoneyMovement = {
    id: movement?.id ?? uuid(), kind: d.kind, direction: info.direction, amountMinor, currency: movement?.currency ?? "RM", date: when,
    personId: needsPerson ? d.personId || null : null, personNameSnapshot: needsPerson ? person?.name ?? null : null,
    linkedExpenseId: movement?.linkedExpenseId ?? null, linkedExpenseSnapshot: movement?.linkedExpenseSnapshot ?? null,
    accountId: d.accountId || null, counterAccountId: d.type === "transfer" ? d.counterAccountId || null : null, note: d.note.trim() || null,
    transactionReference: d.reference.trim() || null, sourceType: movement?.sourceType ?? ctx.movementSourceType ?? "manual", paymentChannel: d.channel,
    createdAt: movement?.createdAt ?? now, updatedAt: now, deletedAt: null,
  };
  await saveRecords("movements", [record]);
  return { kind: "movement", id: record.id, label: info.label };
}

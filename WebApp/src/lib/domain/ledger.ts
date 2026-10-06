// Totals, PayBook balances, per-transaction debts and settlements — the same rules as iOS FinancialCalculator,
// PersonLedger, DebtLedger and SettlementService (Common/BusinessRules/balances-and-settlements.md).
// Inputs are the user's non-deleted records. Positive person balance = they owe me; negative = I owe them.
import { kindInfo } from "./constants";
import { formatMoney } from "./money";
import type { AllocationKind, Expense, ExpenseShare, ID, MoneyMovement, Person, SettlementAllocation } from "./types";

export const alive = <T extends { deletedAt: string | null }>(records: T[]) => records.filter((r) => !r.deletedAt);

/** Shares grouped by expense id (non-deleted only). */
export function sharesByExpense(shares: ExpenseShare[]): Map<ID, ExpenseShare[]> {
  const map = new Map<ID, ExpenseShare[]>();
  for (const share of shares) {
    if (share.deletedAt) continue;
    const list = map.get(share.expenseId) ?? [];
    list.push(share);
    map.set(share.expenseId, list);
  }
  for (const list of map.values()) list.sort((a, b) => a.sortIndex - b.sortIndex);
  return map;
}

export const isShared = (shares: ExpenseShare[] | undefined) => (shares?.length ?? 0) > 0;

/** My share: the full amount when not shared, otherwise the "Me" share (0 if missing). */
export function myShareMinor(expense: Expense, shares: ExpenseShare[] | undefined): number {
  if (!isShared(shares)) return expense.amountMinor;
  return shares!.find((s) => s.isMe)?.amountMinor ?? 0;
}

/** Spending: the full amount if I paid, my share if someone else paid. */
export const spendingMinor = (e: Expense, s: ExpenseShare[] | undefined) => (e.paidByMe ? e.amountMinor : myShareMinor(e, s));
/** Cash out: the full amount if I paid, nothing if someone else paid. */
export const cashOutMinor = (e: Expense) => (e.paidByMe ? e.amountMinor : 0);

export interface Summary {
  spendingMinor: number;
  refundsMinor: number;
  moneyInMinor: number;
  moneyOutMinor: number;
  netSpendingMinor: number;
  netCashFlowMinor: number;
}

/**
 * Spending = Σ expense spending; Money In = Σ inbound movements; Money Out = Σ cash out on expenses I paid +
 * outbound movements. Own transfers are excluded from everything. One currency at a time (never mixed).
 */
export function summary(expenses: Expense[], shares: Map<ID, ExpenseShare[]>, movements: MoneyMovement[], currency = "RM"): Summary {
  let spending = 0, refunds = 0, moneyIn = 0, moneyOut = 0;
  for (const e of expenses) {
    if (e.currency !== currency) continue;
    spending += spendingMinor(e, shares.get(e.id));
    moneyOut += cashOutMinor(e);
  }
  for (const m of movements) {
    if (m.currency !== currency) continue;
    const direction = kindInfo(m.kind).direction;
    if (direction === "in") {
      moneyIn += m.amountMinor;
      if (m.kind === "refund") refunds += m.amountMinor;
    } else if (direction === "out") {
      moneyOut += m.amountMinor;
    }
  }
  return {
    spendingMinor: spending, refundsMinor: refunds, moneyInMinor: moneyIn, moneyOutMinor: moneyOut,
    netSpendingMinor: spending - refunds, netCashFlowMinor: moneyIn - moneyOut,
  };
}

/** Recorded money through one funding account (NOT a bank balance). */
export function accountActivity(accountId: ID, currency: string, expenses: Expense[], movements: MoneyMovement[]) {
  let inMinor = 0, outMinor = 0;
  for (const e of expenses) if (e.accountId === accountId && e.currency === currency) outMinor += cashOutMinor(e);
  for (const m of movements) {
    if (m.currency !== currency) continue;
    if (m.accountId === accountId) {
      if (kindInfo(m.kind).direction === "in") inMinor += m.amountMinor;
      else outMinor += m.amountMinor;
    }
    if (m.counterAccountId === accountId && m.kind === "ownTransfer") inMinor += m.amountMinor;
  }
  return { inMinor, outMinor, netMinor: inMinor - outMinor };
}

/**
 * What each person owes me (positive) or I owe them (negative), keyed by person id.
 * Expense I paid: other participants' shares add to what they owe me. Expense a person paid: my share adds to what
 * I owe them. Loans/repayments by sign. Records without a person are skipped.
 */
export function personBalances(expenses: Expense[], shares: Map<ID, ExpenseShare[]>, movements: MoneyMovement[], currency = "RM"): Map<ID, number> {
  const balances = new Map<ID, number>();
  const add = (id: ID, value: number) => balances.set(id, (balances.get(id) ?? 0) + value);
  for (const e of expenses) {
    if (e.currency !== currency) continue;
    const list = shares.get(e.id);
    if (e.paidByMe) {
      for (const s of list ?? []) if (!s.isMe && s.personId) add(s.personId, s.amountMinor);
    } else if (e.payerId) {
      add(e.payerId, -myShareMinor(e, list));
    }
  }
  for (const m of movements) {
    if (m.currency !== currency) continue;
    const sign = kindInfo(m.kind).personBalanceSign;
    if (sign !== 0 && m.personId) add(m.personId, sign * m.amountMinor);
  }
  return balances;
}

/** All currencies a person has history in → balance (zero balances omitted). */
export function balancesForPerson(personId: ID, expenses: Expense[], shares: Map<ID, ExpenseShare[]>, movements: MoneyMovement[]): Map<string, number> {
  const currencies = new Set<string>([...expenses.map((e) => e.currency), ...movements.map((m) => m.currency)]);
  const result = new Map<string, number>();
  for (const currency of currencies) {
    const value = personBalances(expenses, shares, movements, currency).get(personId) ?? 0;
    if (value !== 0) result.set(currency, value);
  }
  return result;
}

export function directionText(name: string, balanceMinor: number, currency = "RM"): string {
  if (balanceMinor > 0) return `${name} owes you ${formatMoney(balanceMinor, currency)}`;
  if (balanceMinor < 0) return `You owe ${name} ${formatMoney(-balanceMinor, currency)}`;
  return `Settled with ${name}`;
}

// ------------------------------------------------------------------------------------------------------------
// Per-transaction debts
// ------------------------------------------------------------------------------------------------------------

export interface Debt {
  id: string;
  source: { type: "expense"; id: ID } | { type: "loan"; id: ID };
  personId: ID;
  personName: string;
  date: string;
  title: string;
  currency: string;
  /** +1: the person owes me. -1: I owe the person. */
  direction: 1 | -1;
  originalMinor: number;
  settledMinor: number;
  detail: string;
  outstandingMinor: number;
  isSettled: boolean;
  signedOutstandingMinor: number;
}

export const debtExpenseId = (d: Debt) => (d.source.type === "expense" ? d.source.id : null);
export const debtLoanId = (d: Debt) => (d.source.type === "loan" ? d.source.id : null);

/** Allocations that still count: offsets always; payments/assignments only while their payment exists. */
export function activeAllocations(allocations: SettlementAllocation[], movements: MoneyMovement[]): SettlementAllocation[] {
  const paymentIds = new Set(movements.filter((m) => !m.deletedAt && (m.kind === "repaymentReceived" || m.kind === "repaymentMade")).map((m) => m.id));
  return allocations.filter((a) => !a.deletedAt && (a.kind === "offset" || (a.paymentId !== null && paymentIds.has(a.paymentId))));
}

function makeDebt(base: Omit<Debt, "outstandingMinor" | "isSettled" | "signedOutstandingMinor">): Debt {
  const outstanding = Math.max(0, base.originalMinor - base.settledMinor);
  return { ...base, outstandingMinor: outstanding, isSettled: outstanding === 0, signedOutstandingMinor: base.direction * outstanding };
}

const cmpDebt = (a: Debt, b: Debt) => (a.date !== b.date ? (a.date < b.date ? -1 : 1) : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export function expenseDebt(expense: Expense, list: ExpenseShare[] | undefined, person: Person, active: SettlementAllocation[]): Debt | null {
  let direction: 1 | -1;
  let original: number;
  let detail: string;
  if (expense.paidByMe) {
    const share = (list ?? []).find((s) => !s.isMe && s.personId === person.id);
    if (!share) return null;
    direction = 1;
    original = share.amountMinor;
    detail = `You paid · their share ${formatMoney(original, expense.currency)}`;
  } else if (expense.payerId === person.id) {
    direction = -1;
    original = myShareMinor(expense, list);
    detail = `${person.name} paid · your share ${formatMoney(original, expense.currency)}`;
  } else {
    return null;
  }
  if (original <= 0) return null;
  const settled = active
    .filter((a) => a.expenseId === expense.id && a.personId === person.id && a.direction === direction)
    .reduce((s, a) => s + a.amountMinor, 0);
  return makeDebt({
    id: `expense:${expense.id}:${person.id}`, source: { type: "expense", id: expense.id }, personId: person.id, personName: person.name,
    date: expense.date, title: expense.merchant, currency: expense.currency, direction, originalMinor: original, settledMinor: settled, detail,
  });
}

export function loanDebt(loan: MoneyMovement, person: Person, active: SettlementAllocation[]): Debt | null {
  let direction: 1 | -1;
  if (loan.kind === "loanGiven") direction = 1;
  else if (loan.kind === "loanReceived") direction = -1;
  else return null;
  if (loan.amountMinor <= 0) return null;
  const settled = active.filter((a) => a.loanId === loan.id && a.direction === direction).reduce((s, a) => s + a.amountMinor, 0);
  const title = loan.note ? loan.note : direction > 0 ? "Money you gave" : "Money you received";
  return makeDebt({
    id: `loan:${loan.id}`, source: { type: "loan", id: loan.id }, personId: person.id, personName: person.name, date: loan.date, title,
    currency: loan.currency, direction, originalMinor: loan.amountMinor, settledMinor: settled,
    detail: direction > 0 ? "You gave money" : `${person.name} gave you money`,
  });
}

export interface LedgerInput {
  expenses: Expense[];
  shares: Map<ID, ExpenseShare[]>;
  movements: MoneyMovement[];
  allocations: SettlementAllocation[];
}

/** Every debt with this person (settled and outstanding), oldest first. */
export function debtsForPerson(person: Person, input: LedgerInput): Debt[] {
  const active = activeAllocations(input.allocations, input.movements).filter((a) => a.personId === person.id);
  const result: Debt[] = [];
  for (const e of input.expenses) {
    const list = input.shares.get(e.id);
    const involved = e.payerId === person.id || (list ?? []).some((s) => s.personId === person.id);
    if (!involved) continue;
    const debt = expenseDebt(e, list, person, active);
    if (debt) result.push(debt);
  }
  for (const m of input.movements) {
    if (m.personId !== person.id) continue;
    const debt = loanDebt(m, person, active);
    if (debt) result.push(debt);
  }
  return result.sort(cmpDebt);
}

/** Repayments with this person and how much of each is applied to transactions (the rest is credit). */
export function paymentUses(personId: ID, input: LedgerInput) {
  const payments = input.movements.filter((m) => m.personId === personId && (m.kind === "repaymentReceived" || m.kind === "repaymentMade"));
  const active = activeAllocations(input.allocations, input.movements).filter((a) => a.personId === personId);
  return payments
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))
    .map((payment) => {
      const allocated = active.filter((a) => a.paymentId === payment.id).reduce((s, a) => s + a.amountMinor, 0);
      return {
        payment,
        allocatedMinor: allocated,
        direction: (payment.kind === "repaymentReceived" ? 1 : -1) as 1 | -1,
        unallocatedMinor: Math.max(0, payment.amountMinor - allocated),
      };
    });
}

/** Credit: repayments (or parts) not applied to any transaction, in one direction. */
export function creditMinor(personId: ID, currency: string, direction: 1 | -1, input: LedgerInput): number {
  return paymentUses(personId, input)
    .filter((u) => u.payment.currency === currency && u.direction === direction)
    .reduce((s, u) => s + u.unallocatedMinor, 0);
}

/** Oldest first: fills each debt before moving to the next. */
export function autoAllocate(amountMinor: number, debts: Debt[]): [Debt, number][] {
  let left = amountMinor;
  const plan: [Debt, number][] = [];
  for (const debt of debts.filter((d) => d.outstandingMinor > 0).sort(cmpDebt)) {
    if (left <= 0) break;
    const amount = Math.min(left, debt.outstandingMinor);
    plan.push([debt, amount]);
    left -= amount;
  }
  return plan;
}

// ------------------------------------------------------------------------------------------------------------
// Settlements: these functions only PLAN new records; the caller saves them. Originals are never modified.
// ------------------------------------------------------------------------------------------------------------

export class SettlementError extends Error {}

export interface NewAllocation {
  groupId: ID; kind: AllocationKind; paymentId: ID | null; expenseId: ID | null; loanId: ID | null; personId: ID;
  direction: 1 | -1; amountMinor: number; currency: string; date: string;
}
export interface NewPayment {
  id: ID; kind: "repaymentReceived" | "repaymentMade"; amountMinor: number; currency: string; date: string; personId: ID;
  personName: string; accountId: ID | null; note: string | null;
}
export interface SettlementPlan { groupId: ID; payments: NewPayment[]; allocations: NewAllocation[] }

const uuid = () => crypto.randomUUID();

/** One real payment, applied to the chosen debts; any unapplied part stays as credit. Validated first. */
export function planPayment(
  person: Person, direction: 1 | -1, amountMinor: number, allocations: [Debt, number][], currency: string,
  date: string, accountId: ID | null = null, note: string | null = null,
): SettlementPlan {
  if (!(amountMinor > 0)) throw new SettlementError("Enter an amount greater than zero.");
  const applied = allocations.filter(([, a]) => a > 0);
  for (const [debt, amount] of applied) {
    if (debt.personId !== person.id || debt.direction !== direction || debt.currency !== currency)
      throw new SettlementError("These transactions can't be paid together.");
    if (amount > debt.outstandingMinor) throw new SettlementError(`That's more than what's left on ${debt.title}.`);
  }
  if (applied.reduce((s, [, a]) => s + a, 0) > amountMinor) throw new SettlementError("The amounts applied are more than the payment.");
  const groupId = uuid();
  const payment: NewPayment = {
    id: uuid(), kind: direction > 0 ? "repaymentReceived" : "repaymentMade", amountMinor, currency, date, personId: person.id,
    personName: person.name, accountId, note,
  };
  return {
    groupId,
    payments: [payment],
    allocations: applied.map(([debt, amount]) => ({
      groupId, kind: "payment", paymentId: payment.id, expenseId: debtExpenseId(debt), loanId: debtLoanId(debt), personId: person.id,
      direction, amountMinor: amount, currency, date,
    })),
  };
}

/** "Mark as Paid": one payment for exactly what's left on this debt. */
export function planMarkPaid(debt: Debt, person: Person, date: string, accountId: ID | null = null): SettlementPlan {
  if (debt.outstandingMinor <= 0) throw new SettlementError("Nothing is outstanding.");
  return planPayment(person, debt.direction, debt.outstandingMinor, [[debt, debt.outstandingMinor]], debt.currency, date, accountId, `Settled: ${debt.title}`);
}

/** Applies existing credit (oldest unlinked repayments first) to debts. No new money moves. */
export function planApplyCredit(person: Person, direction: 1 | -1, allocations: [Debt, number][], currency: string, date: string, input: LedgerInput): SettlementPlan {
  const applied = allocations.filter(([, a]) => a > 0);
  if (applied.length === 0) throw new SettlementError("Enter an amount greater than zero.");
  for (const [debt, amount] of applied) {
    if (debt.personId !== person.id || debt.direction !== direction || debt.currency !== currency)
      throw new SettlementError("These transactions can't be paid together.");
    if (amount > debt.outstandingMinor) throw new SettlementError(`That's more than what's left on ${debt.title}.`);
  }
  const available = creditMinor(person.id, currency, direction, input);
  const wanted = applied.reduce((s, [, a]) => s + a, 0);
  if (wanted > available) throw new SettlementError(`Only ${formatMoney(available, currency)} of credit is available. Apply less, or record a new payment.`);
  const groupId = uuid();
  const sources = paymentUses(person.id, input)
    .filter((u) => u.payment.currency === currency && u.direction === direction && u.unallocatedMinor > 0)
    .map((u) => ({ id: u.payment.id, free: u.unallocatedMinor }));
  const result: NewAllocation[] = [];
  let index = 0;
  for (const [debt, amount] of applied) {
    let left = amount;
    while (left > 0 && index < sources.length) {
      const take = Math.min(left, sources[index].free);
      result.push({ groupId, kind: "assign", paymentId: sources[index].id, expenseId: debtExpenseId(debt), loanId: debtLoanId(debt),
        personId: person.id, direction, amountMinor: take, currency, date });
      sources[index].free -= take;
      left -= take;
      if (sources[index].free === 0) index += 1;
    }
  }
  return { groupId, payments: [], allocations: result };
}

/**
 * Settles everything with a person in one currency: 1. earlier unlinked payments go to the oldest debts in their
 * direction; 2. opposite debts cancel (offsets, no money moves); 3. one payment for what remains. One group = one Undo.
 */
export function planSettleAll(person: Person, currency: string, date: string, input: LedgerInput, accountId: ID | null = null): SettlementPlan {
  const groupId = uuid();
  const debts = debtsForPerson(person, input).filter((d) => d.currency === currency && d.outstandingMinor > 0).sort(cmpDebt);
  if (debts.length === 0) throw new SettlementError("Nothing is outstanding.");
  const outstanding = new Map(debts.map((d) => [d.id, d.outstandingMinor]));
  const allocations: NewAllocation[] = [];
  const payments: NewPayment[] = [];
  const add = (debt: Debt, amount: number, kind: AllocationKind, paymentId: ID | null) => {
    if (amount <= 0) return;
    allocations.push({ groupId, kind, paymentId, expenseId: debtExpenseId(debt), loanId: debtLoanId(debt), personId: person.id,
      direction: debt.direction, amountMinor: amount, currency, date });
    outstanding.set(debt.id, (outstanding.get(debt.id) ?? 0) - amount);
  };
  // 1. Earlier unlinked payments
  const active = activeAllocations(input.allocations, input.movements);
  const personPayments = input.movements
    .filter((m) => m.personId === person.id && m.currency === currency && (m.kind === "repaymentReceived" || m.kind === "repaymentMade"))
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  for (const payment of personPayments) {
    const direction = payment.kind === "repaymentReceived" ? 1 : -1;
    let free = payment.amountMinor - active.filter((a) => a.paymentId === payment.id).reduce((s, a) => s + a.amountMinor, 0);
    for (const debt of debts) {
      if (debt.direction !== direction || free <= 0) continue;
      const amount = Math.min(free, outstanding.get(debt.id) ?? 0);
      add(debt, amount, "assign", payment.id);
      free -= amount;
    }
  }
  // 2. Offsets
  const total = (direction: 1 | -1) => debts.filter((d) => d.direction === direction).reduce((s, d) => s + (outstanding.get(d.id) ?? 0), 0);
  const offset = Math.min(total(1), total(-1));
  if (offset > 0) {
    for (const direction of [1, -1] as const) {
      let left = offset;
      for (const debt of debts) {
        if (debt.direction !== direction || left <= 0) continue;
        const amount = Math.min(left, outstanding.get(debt.id) ?? 0);
        add(debt, amount, "offset", null);
        left -= amount;
      }
    }
  }
  // 3. One payment for the rest
  for (const direction of [1, -1] as const) {
    const rest = total(direction);
    if (rest <= 0) continue;
    const payment: NewPayment = {
      id: uuid(), kind: direction > 0 ? "repaymentReceived" : "repaymentMade", amountMinor: rest, currency, date, personId: person.id,
      personName: person.name, accountId, note: `Settled all with ${person.name}`,
    };
    payments.push(payment);
    for (const debt of debts) if (debt.direction === direction) add(debt, outstanding.get(debt.id) ?? 0, "payment", payment.id);
  }
  return { groupId, payments, allocations };
}

export interface SettlementGroup {
  id: ID; date: string; allocations: SettlementAllocation[]; payment: MoneyMovement | null; totalMinor: number; offsetMinor: number;
  currency: string; direction: number;
}

/** Settlement actions involving a person or an expense, newest first. */
export function settlementGroups(filter: { personId?: ID; expenseId?: ID; loanId?: ID }, input: LedgerInput): SettlementGroup[] {
  const byId = new Map(input.movements.filter((m) => !m.deletedAt).map((m) => [m.id, m]));
  const all = activeAllocations(input.allocations, input.movements);
  const matching = all.filter((a) =>
    (!filter.personId || a.personId === filter.personId) && (!filter.expenseId || a.expenseId === filter.expenseId) && (!filter.loanId || a.loanId === filter.loanId));
  const groupIds = [...new Set(matching.map((a) => a.groupId))];
  return groupIds
    .map((gid) => {
      const items = all.filter((a) => a.groupId === gid);
      const shown = items.filter((a) => matching.some((m) => m.id === a.id));
      const paymentId = items.find((a) => a.kind === "payment")?.paymentId ?? null;
      const payment = paymentId ? byId.get(paymentId) ?? null : null;
      const date = shown.map((a) => a.date).sort().at(-1) ?? new Date().toISOString();
      return {
        id: gid, date, allocations: shown, payment,
        totalMinor: shown.filter((a) => a.kind !== "offset").reduce((s, a) => s + a.amountMinor, 0),
        offsetMinor: shown.filter((a) => a.kind === "offset" && a.direction > 0).reduce((s, a) => s + a.amountMinor, 0),
        currency: shown[0]?.currency ?? payment?.currency ?? "RM",
        direction: shown.find((a) => a.kind !== "offset")?.direction ?? 0,
      };
    })
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0));
}

/** Undo = tombstone the group's allocations and the payment(s) the group created. Earlier payments stay. */
export function undoTargets(groupId: ID, allocations: SettlementAllocation[]) {
  const items = allocations.filter((a) => a.groupId === groupId && !a.deletedAt);
  return { allocationIds: items.map((a) => a.id), paymentIds: [...new Set(items.filter((a) => a.kind === "payment").map((a) => a.paymentId!).filter(Boolean))] };
}

export type BalanceFilter = "all" | "theyOweMe" | "iOweThem";

/** They Owe Me / I Owe Them: decided only by the net balance (largest currency), sorted by amount then activity. */
export function outstandingPeople(people: Person[], filter: BalanceFilter, input: LedgerInput, lastActivity: (p: Person) => string) {
  if (filter === "all") return [];
  const sign = filter === "theyOweMe" ? 1 : -1;
  const rows: { person: Person; amountMinor: number; currency: string; lastActivity: string }[] = [];
  for (const person of people) {
    const balances = balancesForPerson(person.id, input.expenses, input.shares, input.movements);
    const matching = [...balances.entries()].filter(([, v]) => v * sign > 0);
    if (matching.length === 0) continue;
    const [currency, value] = matching.reduce((a, b) => (Math.abs(b[1]) > Math.abs(a[1]) ? b : a));
    rows.push({ person, amountMinor: Math.abs(value), currency, lastActivity: lastActivity(person) });
  }
  return rows.sort((a, b) =>
    a.amountMinor !== b.amountMinor ? b.amountMinor - a.amountMinor
      : a.lastActivity !== b.lastActivity ? (a.lastActivity < b.lastActivity ? 1 : -1)
        : a.person.name.localeCompare(b.person.name, undefined, { sensitivity: "base" }));
}

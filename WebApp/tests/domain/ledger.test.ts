import { describe, expect, it } from "vitest";
import * as L from "@/lib/domain/ledger";
import type { Expense, ExpenseShare, MoneyMovement, Person, SettlementAllocation } from "@/lib/domain/types";

const meta = (id: string) => ({ id, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z", deletedAt: null });
const person = (id: string, name: string): Person => ({ ...meta(id), name, notes: null, isFrequent: false, isArchived: false });
const expense = (id: string, amountMinor: number, extra: Partial<Expense> = {}): Expense => ({
  ...meta(id), amountMinor, currency: "RM", merchant: id, category: "Food", paymentChannel: "UNKNOWN", fundingAccount: "Maybank",
  fundingInstrument: null, accountId: null, paymentSource: null, date: "2026-10-0" + (extra.date ?? "1") + "T10:00:00Z", notes: null,
  transactionReference: null, sourceType: "manual", paidByMe: true, payerId: null, payerNameSnapshot: null, splitMethod: "amounts",
  receiptPath: null, isSampleData: false, ...extra, ...(extra.date ? { date: extra.date } : {}),
});
const share = (id: string, expenseId: string, personId: string | null, amountMinor: number, sortIndex: number): ExpenseShare => ({
  ...meta(id), expenseId, personId, isMe: personId === null, nameSnapshot: personId ?? "Me", amountMinor, parts: null, enteredMinor: amountMinor, sortIndex,
});
const movement = (id: string, kind: MoneyMovement["kind"], amountMinor: number, personId: string | null, extra: Partial<MoneyMovement> = {}): MoneyMovement => ({
  ...meta(id), kind, direction: kind === "ownTransfer" ? "internal" : ["income", "loanReceived", "repaymentReceived", "refund", "otherIn"].includes(kind) ? "in" : "out",
  amountMinor, currency: "RM", date: "2026-10-05T10:00:00Z", personId, personNameSnapshot: null, linkedExpenseId: null, linkedExpenseSnapshot: null,
  accountId: null, counterAccountId: null, note: null, transactionReference: null, sourceType: "manual", paymentChannel: "UNKNOWN", ...extra,
});

describe("ledger (same rules as iOS FinancialCalculator / DebtLedger / SettlementService)", () => {
  const bijoy = person("bijoy", "Bijoy");
  // Dinner RM100 I paid, my share 70 -> Bijoy owes 30. Taxi RM20 Bijoy paid for me -> I owe 20. Loan given RM50.
  const dinner = expense("dinner", 10000, { date: "2026-10-01T10:00:00Z" });
  const taxi = expense("taxi", 2000, { paidByMe: false, payerId: "bijoy", date: "2026-10-02T10:00:00Z" });
  const shares = L.sharesByExpense([
    share("s1", "dinner", null, 7000, 0), share("s2", "dinner", "bijoy", 3000, 1), share("s3", "taxi", null, 2000, 0),
  ]);
  const loan = movement("loan", "loanGiven", 5000, "bijoy");
  const input = (allocations: SettlementAllocation[] = [], extra: MoneyMovement[] = []): L.LedgerInput =>
    ({ expenses: [dinner, taxi], shares, movements: [loan, ...extra], allocations });

  it("summary: spending = full if I paid, my share otherwise; own transfers excluded", () => {
    const sum = L.summary([dinner, taxi], shares, [loan, movement("t", "ownTransfer", 99999, null), movement("i", "income", 300000, null)]);
    expect(sum).toMatchObject({ spendingMinor: 12000, moneyOutMinor: 15000, moneyInMinor: 300000 });
  });

  it("balance: +30 (dinner) − 20 (taxi) + 50 (loan) = they owe me RM60", () => {
    expect(L.personBalances([dinner, taxi], shares, [loan]).get("bijoy")).toBe(6000);
    expect(L.directionText("Bijoy", 6000)).toBe("Bijoy owes you RM 60.00");
  });

  it("debts per transaction, oldest first", () => {
    const debts = L.debtsForPerson(bijoy, input());
    expect(debts.map((d) => [d.title, d.direction, d.outstandingMinor])).toEqual([["dinner", 1, 3000], ["taxi", -1, 2000], ["Money you gave", 1, 5000]]);
  });

  const apply = (plan: L.SettlementPlan) => {
    const payments = plan.payments.map((p) => movement(p.id, p.kind, p.amountMinor, p.personId, { date: p.date, note: p.note }));
    const allocations = plan.allocations.map((a, i) => ({ ...meta(`${plan.groupId}-${i}`), ...a }));
    return { payments, allocations };
  };

  it("Mark as Paid settles only that debt; the dinner itself is unchanged", () => {
    const dinnerDebt = L.debtsForPerson(bijoy, input())[0];
    const { payments, allocations } = apply(L.planMarkPaid(dinnerDebt, bijoy, "2026-10-06T00:00:00Z"));
    const after = L.debtsForPerson(bijoy, input(allocations, payments));
    expect(after.map((d) => d.outstandingMinor)).toEqual([0, 2000, 5000]);
    expect(L.personBalances([dinner, taxi], shares, [loan, ...payments]).get("bijoy")).toBe(3000);
  });

  it("Settle All: offsets opposite debts, then one payment for the rest; balance becomes 0; undo restores", () => {
    const plan = L.planSettleAll(bijoy, "RM", "2026-10-06T00:00:00Z", input());
    expect(plan.payments.map((p) => [p.kind, p.amountMinor])).toEqual([["repaymentReceived", 6000]]);
    expect(plan.allocations.filter((a) => a.kind === "offset").reduce((s, a) => s + a.amountMinor, 0)).toBe(4000);
    const { payments, allocations } = apply(plan);
    expect(L.personBalances([dinner, taxi], shares, [loan, ...payments]).get("bijoy")).toBe(0);
    expect(L.debtsForPerson(bijoy, input(allocations, payments)).every((d) => d.isSettled)).toBe(true);
    const undo = L.undoTargets(plan.groupId, allocations);
    const tomb = <T extends { id: string; deletedAt: string | null }>(x: T): T => (undo.allocationIds.includes(x.id) || undo.paymentIds.includes(x.id) ? { ...x, deletedAt: "now" } : x);
    const undone = L.debtsForPerson(bijoy, input(allocations.map(tomb), payments.map(tomb)));
    expect(undone.map((d) => d.outstandingMinor)).toEqual([3000, 2000, 5000]);
  });

  it("validates payments: more than outstanding is refused", () => {
    const dinnerDebt = L.debtsForPerson(bijoy, input())[0];
    expect(() => L.planPayment(bijoy, 1, 5000, [[dinnerDebt, 4000]], "RM", "2026-10-06")).toThrow(/more than what's left/);
  });

  it("unlinked payments are credit and can be applied later", () => {
    const pay = movement("p", "repaymentReceived", 1000, "bijoy");
    expect(L.creditMinor("bijoy", "RM", 1, input([], [pay]))).toBe(1000);
    const dinnerDebt = L.debtsForPerson(bijoy, input([], [pay]))[0];
    const plan = L.planApplyCredit(bijoy, 1, [[dinnerDebt, 1000]], "RM", "2026-10-06", input([], [pay]));
    expect(plan.payments).toEqual([]);
    expect(plan.allocations).toMatchObject([{ kind: "assign", paymentId: "p", amountMinor: 1000 }]);
  });

  it("They Owe Me / I Owe Them is decided by the net balance only", () => {
    const alice = person("alice", "Alice");
    const lunch = expense("lunch", 3000, { paidByMe: false, payerId: "alice" });
    const s2 = L.sharesByExpense([share("a", "lunch", null, 3000, 0)]);
    const inp = { expenses: [lunch], shares: s2, movements: [], allocations: [] };
    expect(L.outstandingPeople([alice], "iOweThem", inp, () => "x").map((r) => [r.person.name, r.amountMinor])).toEqual([["Alice", 3000]]);
    expect(L.outstandingPeople([alice], "theyOweMe", inp, () => "x")).toEqual([]);
  });
});

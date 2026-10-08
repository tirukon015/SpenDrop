// Test data for SpenDrop AI: synthetic users and transactions (never real data).
import type { CategoryId, Expense, ExpenseShare, MoneyMovement, PaymentChannelId } from "@/lib/domain/types";
import { MemoryTenantStore } from "@/lib/ai/repository";
import type { AiContext } from "@/lib/ai/types";

export const USER_A = "11111111-1111-4111-8111-111111111111";
export const USER_B = "22222222-2222-4222-8222-222222222222";
export const TZ = "Asia/Kuala_Lumpur";
/** Wednesday 7 October 2026 (Malaysia). */
export const TODAY = "2026-10-07";

let seq = 0;
export const uuid = () => {
  seq += 1;
  return `00000000-0000-4000-8000-${String(seq).padStart(12, "0")}`;
};

export function exp(p: {
  merchant: string; amount: number; date: string; time?: string; category?: CategoryId; channel?: PaymentChannelId; account?: string;
  currency?: string; notes?: string; receipt?: boolean; paidByMe?: boolean; id?: string;
}): Expense {
  const iso = new Date(`${p.date}T${p.time ?? "12:00"}:00+08:00`).toISOString();
  return {
    id: p.id ?? uuid(), createdAt: iso, updatedAt: iso, deletedAt: null,
    amountMinor: Math.round(p.amount * 100), currency: p.currency ?? "RM", merchant: p.merchant, category: p.category ?? "Other",
    paymentChannel: p.channel ?? "UNKNOWN", fundingAccount: p.account ?? "Unknown", fundingInstrument: null, accountId: null, paymentSource: null,
    date: iso, notes: p.notes ?? null, transactionReference: null, sourceType: "manual", paidByMe: p.paidByMe ?? true, payerId: null,
    payerNameSnapshot: p.paidByMe === false ? "Ali" : null, splitMethod: null, receiptPath: p.receipt ? `${USER_A}/x/receipt.webp` : null, isSampleData: false,
  };
}

export function share(expense: Expense, p: { isMe: boolean; amount: number; name?: string }): ExpenseShare {
  return {
    id: uuid(), createdAt: expense.createdAt, updatedAt: expense.updatedAt, deletedAt: null, expenseId: expense.id, personId: null,
    isMe: p.isMe, nameSnapshot: p.name ?? (p.isMe ? "Me" : "Friend"), amountMinor: Math.round(p.amount * 100), parts: null, enteredMinor: null, sortIndex: p.isMe ? 0 : 1,
  };
}

export function refund(amount: number, date: string): MoneyMovement {
  const iso = new Date(`${date}T12:00:00+08:00`).toISOString();
  return {
    id: uuid(), createdAt: iso, updatedAt: iso, deletedAt: null, kind: "refund", direction: "in", amountMinor: Math.round(amount * 100), currency: "RM",
    date: iso, personId: null, personNameSnapshot: null, linkedExpenseId: null, linkedExpenseSnapshot: null, accountId: null, counterAccountId: null,
    note: null, transactionReference: null, sourceType: "manual", paymentChannel: "UNKNOWN",
  };
}

export const ctx = (userId = USER_A, today = TODAY): AiContext => ({ userId, timeZone: TZ, today, requestId: "test-request" });

/** Eight weeks of steady history for user A plus a few notable transactions this week. */
export function historyStore() {
  const expenses: Expense[] = [];
  // Weeks before this one (Mon 5 Oct 2026 starts this week): two meals, one ride, one grocery run each week.
  for (let w = 1; w <= 8; w++) {
    const monday = new Date(Date.UTC(2026, 9, 5 - 7 * w));
    const d = (offset: number) => new Date(monday.getTime() + offset * 86_400_000).toISOString().slice(0, 10);
    expenses.push(exp({ merchant: "Mamak Corner", amount: 12, date: d(0), category: "Food", channel: "QR_PAYMENT", account: "Maybank" }));
    expenses.push(exp({ merchant: "Starbucks", amount: 18.5, date: d(2), category: "Food", channel: "APPLE_PAY", account: "Maybank" }));
    expenses.push(exp({ merchant: "Grab", amount: 9, date: d(3), category: "Transport", channel: "E_WALLET", account: "Touch 'n Go" }));
    expenses.push(exp({ merchant: "Jaya Grocer", amount: 45, date: d(5), category: "Groceries", channel: "CARD", account: "CIMB" }));
  }
  // This week (5–7 Oct)
  expenses.push(exp({ merchant: "Mamak Corner", amount: 12, date: "2026-10-05", category: "Food", channel: "QR_PAYMENT", account: "Maybank" }));
  expenses.push(exp({ merchant: "Sushi King", amount: 86, date: "2026-10-06", time: "19:30", category: "Food", channel: "CARD", account: "CIMB" }));
  expenses.push(exp({ merchant: "Harvey Norman", amount: 899, date: "2026-10-06", time: "15:10", category: "Shopping", channel: "CARD", account: "CIMB" }));
  expenses.push(exp({ merchant: "Starbucks", amount: 14.9, date: "2026-10-07", time: "10:42", category: "Food", channel: "APPLE_PAY", account: "Maybank" }));
  expenses.push(exp({ merchant: "Touch 'n Go Parking", amount: 15, date: "2026-10-07", time: "18:18", category: "Transport", channel: "TNG_QR", account: "Touch 'n Go" }));
  return new MemoryTenantStore().add(USER_A, { expenses });
}

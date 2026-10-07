// The Web duplicate check for a new / edited expense, shared by the transaction form and Bulk Import.
// Unchanged from the form's original inline check: same reference, or same amount + same day + same merchant.
import { toDateInput } from "./dates";
import type { Expense, ID } from "./types";

export interface DuplicateCandidate {
  /** The record being edited (never matches itself). */
  id?: ID | null;
  amountMinor: number;
  merchant: string;
  /** Local calendar date, yyyy-MM-dd (the form's date input). */
  date: string;
  reference: string;
}

export type DuplicateTarget = Pick<Expense, "id" | "amountMinor" | "merchant" | "date" | "transactionReference">;

const normalized = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");

export function findDuplicateExpense<T extends DuplicateTarget>(candidate: DuplicateCandidate, expenses: readonly T[]): T | null {
  const ref = candidate.reference.trim();
  const day = candidate.date;
  return expenses.find((e) => e.id !== candidate.id && (
    (ref && e.transactionReference && e.transactionReference.trim() === ref) ||
    (e.amountMinor === candidate.amountMinor && toDateInput(new Date(e.date)) === day && normalized(e.merchant) === normalized(candidate.merchant || "Unknown"))
  )) ?? null;
}

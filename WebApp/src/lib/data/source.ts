import type { Expense, ExpenseShare, TableName } from "@/lib/domain/types";
import type { NewAllocation, NewPayment } from "@/lib/domain/ledger";

export interface BackupMeta {
  id: string;
  deviceName: string;
  appVersion: string;
  createdAt: string;
  objectPath: string;
  expensesCount: number;
  peopleCount: number;
  accountsCount: number;
  movementsCount: number;
  sizeBytes: number;
}

export interface PulledRows {
  rows: Record<string, unknown>[];
  /** Highest server_updated_at seen (the next pull cursor). */
  cursor: string | null;
}

/** Where the data lives. Implemented by Supabase (real accounts) and by the local demo (no account). */
export interface DataSource {
  readonly kind: "supabase" | "demo";
  readonly userId: string;
  readonly email: string | null;
  readonly provider: string | null;
  /** Rows changed since `since` (server time), oldest first, all pages. */
  pull(table: TableName, since: string | null): Promise<PulledRows>;
  /** Insert or update whole records (snake_case rows). Deleting = upsert with deleted_at set. */
  upsert(table: TableName, rows: Record<string, unknown>[]): Promise<void>;
  saveExpense(expense: Expense, shares: Omit<ExpenseShare, "expenseId" | "deletedAt">[]): Promise<void>;
  recordSettlement(payments: (NewPayment)[], allocations: (NewAllocation & { id: string })[]): Promise<void>;
  uploadReceipt(file: Blob, expenseId: string): Promise<string>;
  receiptUrl(path: string): Promise<string | null>;
  removeReceipt(path: string): Promise<void>;
  listBackups(): Promise<BackupMeta[]>;
  downloadBackup(objectPath: string): Promise<unknown>;
  signOut(): Promise<void>;
  deleteAccount(): Promise<void>;
}

export class DataError extends Error {
  constructor(message: string, readonly kind: "offline" | "auth" | "permission" | "validation" | "server" = "server") {
    super(message);
  }
}

/** Plain-language message for any failure (never a stack trace). */
export function friendlyError(error: unknown): string {
  if (typeof navigator !== "undefined" && !navigator.onLine) return "You're offline. Your changes weren't saved — connect and try again.";
  if (error instanceof DataError) return error.message;
  const message = error instanceof Error ? error.message : String(error);
  if (/JWT|session|not signed in|401/i.test(message)) return "Your session has ended. Please sign in again.";
  if (/row-level security|permission denied|403/i.test(message)) return "You don't have permission to change this record.";
  if (/add up/i.test(message)) return "The split doesn't add up to the amount. Please check the shares.";
  if (/Failed to fetch|NetworkError|network/i.test(message)) return "Couldn't reach SpenDrop. Check your connection and try again.";
  if (/relation .* does not exist|schema cache|PGRST20/i.test(message))
    return "Cloud records aren't set up on this Supabase project yet. Apply the migration in Supabase/supabase/migrations (see Docs/WebApp-Setup.md).";
  return "Something went wrong. Please try again.";
}

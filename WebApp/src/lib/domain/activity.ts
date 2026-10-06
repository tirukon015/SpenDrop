// The unified Transactions timeline (iOS ActivityFeed + TransactionFilterEngine): expenses and money movements,
// filtered and sorted in memory (records are already cached locally; lists render in pages).
import { kindInfo } from "./constants";
import { dateRange, inRange, type QuickDate } from "./dates";
import { spendingMinor } from "./ledger";
import type { CategoryId, Expense, ExpenseShare, ID, MoneyMovement, PaymentChannelId, Person } from "./types";

export type ActivityType = "all" | "expenses" | "moneyIn" | "moneyOut" | "shared" | "transfers";
export const ACTIVITY_TYPES: { id: ActivityType; label: string }[] = [
  { id: "all", label: "All" },
  { id: "expenses", label: "Expenses" },
  { id: "moneyIn", label: "Money In" },
  { id: "moneyOut", label: "Money Out" },
  { id: "shared", label: "Shared" },
  { id: "transfers", label: "Transfers" },
];

export type SortOrder = "newest" | "oldest" | "highest" | "lowest";

export interface ActivityFilters {
  search: string;
  type: ActivityType;
  date: QuickDate;
  customFrom?: string;
  customTo?: string;
  categories: CategoryId[];
  fundingAccounts: string[];
  channels: PaymentChannelId[];
  personId: ID | null;
  minMinor: number | null;
  maxMinor: number | null;
  sort: SortOrder;
}

export const defaultFilters = (): ActivityFilters => ({
  search: "", type: "all", date: "all", categories: [], fundingAccounts: [], channels: [], personId: null, minMinor: null, maxMinor: null, sort: "newest",
});

export const activeFilterCount = (f: ActivityFilters) =>
  (f.type !== "all" ? 1 : 0) + (f.date !== "all" ? 1 : 0) + f.categories.length + f.fundingAccounts.length + f.channels.length +
  (f.personId ? 1 : 0) + (f.minMinor !== null || f.maxMinor !== null ? 1 : 0);

export type ActivityItem =
  | { type: "expense"; id: ID; date: string; amountMinor: number; expense: Expense; shares: ExpenseShare[] }
  | { type: "movement"; id: ID; date: string; amountMinor: number; movement: MoneyMovement };

export function buildActivity(
  expenses: Expense[], shares: Map<ID, ExpenseShare[]>, movements: MoneyMovement[], people: Person[], f: ActivityFilters, now = new Date(),
): ActivityItem[] {
  const range = dateRange(f.date, now, { from: f.customFrom, to: f.customTo });
  const q = f.search.trim().toLowerCase();
  const names = new Map(people.map((p) => [p.id, p.name.toLowerCase()]));
  const amountOk = (minor: number) => (f.minMinor === null || minor >= f.minMinor) && (f.maxMinor === null || minor <= f.maxMinor);
  const items: ActivityItem[] = [];
  const movementOnlyFiltered = f.categories.length > 0; // categories apply to expenses only (iOS: category filter hides movements)

  if (f.type === "all" || f.type === "expenses" || f.type === "shared") {
    for (const e of expenses) {
      const list = shares.get(e.id) ?? [];
      if (f.type === "shared" && list.length === 0) continue;
      if (!inRange(e.date, range)) continue;
      if (f.categories.length && !f.categories.includes(e.category)) continue;
      if (f.fundingAccounts.length && !f.fundingAccounts.includes(e.fundingAccount)) continue;
      if (f.channels.length && !f.channels.includes(e.paymentChannel)) continue;
      if (f.personId && e.payerId !== f.personId && !list.some((s) => s.personId === f.personId)) continue;
      const shown = spendingMinor(e, list);
      if (!amountOk(e.amountMinor)) continue;
      if (q) {
        const haystack = [e.merchant, e.notes, e.transactionReference, e.category, e.fundingAccount, e.payerNameSnapshot,
          ...list.map((s) => (s.personId ? names.get(s.personId) : s.nameSnapshot))].filter(Boolean).join(" ").toLowerCase();
        if (!haystack.includes(q)) continue;
      }
      items.push({ type: "expense", id: e.id, date: e.date, amountMinor: shown, expense: e, shares: list });
    }
  }
  if (!movementOnlyFiltered && f.type !== "expenses" && f.type !== "shared") {
    for (const m of movements) {
      const direction = kindInfo(m.kind).direction;
      if (f.type === "moneyIn" && direction !== "in") continue;
      if (f.type === "moneyOut" && direction !== "out") continue;
      if (f.type === "transfers" && direction !== "internal") continue;
      if (!inRange(m.date, range)) continue;
      if (f.channels.length && !f.channels.includes(m.paymentChannel)) continue;
      if (f.fundingAccounts.length) continue; // funding account text is an expense field
      if (f.personId && m.personId !== f.personId) continue;
      if (!amountOk(m.amountMinor)) continue;
      if (q) {
        const haystack = [kindInfo(m.kind).label, m.note, m.transactionReference, m.personId ? names.get(m.personId) : m.personNameSnapshot]
          .filter(Boolean).join(" ").toLowerCase();
        if (!haystack.includes(q)) continue;
      }
      items.push({ type: "movement", id: m.id, date: m.date, amountMinor: m.amountMinor, movement: m });
    }
  }
  const byDate = (a: ActivityItem, b: ActivityItem) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.id < b.id ? -1 : 1);
  switch (f.sort) {
    case "newest": return items.sort((a, b) => byDate(b, a));
    case "oldest": return items.sort(byDate);
    case "highest": return items.sort((a, b) => b.amountMinor - a.amountMinor || byDate(b, a));
    case "lowest": return items.sort((a, b) => a.amountMinor - b.amountMinor || byDate(b, a));
  }
}

// Breakdown figures (iOS AnalyticsView / TransactionFilterEngine). Spending = what I spent (full amount if I paid,
// my share if someone else paid). One currency at a time; amounts in integer sen.
import { CATEGORIES, PAYMENT_CHANNELS, kindInfo, type Tint } from "./constants";
import { dayCount, dayKey, inRange, previousRange } from "./dates";
import { spendingMinor } from "./ledger";
import type { CategoryId, Expense, ExpenseShare, ID, MoneyMovement, MovementKind, PaymentChannelId } from "./types";

export interface Group<K extends string> { key: K; valueMinor: number; count: number }

function groupBy<K extends string>(expenses: Expense[], shares: Map<ID, ExpenseShare[]>, keyOf: (e: Expense) => K): Group<K>[] {
  const map = new Map<K, Group<K>>();
  for (const e of expenses) {
    const key = keyOf(e);
    const g = map.get(key) ?? { key, valueMinor: 0, count: 0 };
    g.valueMinor += spendingMinor(e, shares.get(e.id));
    g.count += 1;
    map.set(key, g);
  }
  return [...map.values()].filter((g) => g.valueMinor > 0).sort((a, b) => b.valueMinor - a.valueMinor);
}

export const byCategory = (e: Expense[], s: Map<ID, ExpenseShare[]>) => groupBy<CategoryId>(e, s, (x) => x.category);
export const byChannel = (e: Expense[], s: Map<ID, ExpenseShare[]>) => groupBy<PaymentChannelId>(e, s, (x) => x.paymentChannel);
export const byFundingAccount = (e: Expense[], s: Map<ID, ExpenseShare[]>) => groupBy<string>(e, s, (x) => x.fundingAccount || "Unknown");
export const topMerchants = (e: Expense[], s: Map<ID, ExpenseShare[]>, limit = 5) =>
  groupBy<string>(e, s, (x) => x.merchant.trim().toLowerCase()).slice(0, limit).map((g) => ({
    ...g, label: e.find((x) => x.merchant.trim().toLowerCase() === g.key)?.merchant ?? g.key,
  }));

export const total = (e: Expense[], s: Map<ID, ExpenseShare[]>) => e.reduce((t, x) => t + spendingMinor(x, s.get(x.id)), 0);

/** One entry per day in the range (zeros included), oldest first. */
export function dailySpending(e: Expense[], s: Map<ID, ExpenseShare[]>, range: [Date, Date]) {
  const days: { key: string; date: Date; valueMinor: number }[] = [];
  for (let d = new Date(range[0]); d <= range[1]; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
    days.push({ key: dayKey(d.toISOString()), date: new Date(d), valueMinor: 0 });
    if (days.length > 400) break;
  }
  const index = new Map(days.map((d, i) => [d.key, i]));
  for (const x of e) {
    const i = index.get(dayKey(x.date));
    if (i !== undefined) days[i].valueMinor += spendingMinor(x, s.get(x.id));
  }
  return days;
}

export function averagePerDay(e: Expense[], s: Map<ID, ExpenseShare[]>, range: [Date, Date]) {
  return Math.round(total(e, s) / dayCount(range));
}

/** Spending in the same-length period just before (null when the range is All Time). */
export function previousPeriodTotal(all: Expense[], s: Map<ID, ExpenseShare[]>, range: [Date, Date] | null, currency: string) {
  if (!range) return null;
  const prev = previousRange(range);
  return total(all.filter((x) => x.currency === currency && inRange(x.date, prev)), s);
}

export function movementBreakdown(movements: MoneyMovement[]) {
  const map = new Map<MovementKind, { kind: MovementKind; totalMinor: number; count: number }>();
  for (const m of movements) {
    const g = map.get(m.kind) ?? { kind: m.kind, totalMinor: 0, count: 0 };
    g.totalMinor += m.amountMinor;
    g.count += 1;
    map.set(m.kind, g);
  }
  return [...map.values()].filter((g) => kindInfo(g.kind).direction !== "internal").sort((a, b) => b.totalMinor - a.totalMinor);
}

const PALETTE: Tint[] = ["blue", "orange", "green", "purple", "pink", "teal", "indigo", "yellow", "mint", "red", "cyan", "gray"];
export const categoryTintOf = (id: CategoryId): Tint => CATEGORIES.find((c) => c.id === id)?.tint ?? "gray";
export const channelTintOf = (id: PaymentChannelId): Tint => PAYMENT_CHANNELS.find((c) => c.id === id)?.tint ?? "gray";
export const paletteTint = (i: number): Tint => PALETTE[i % PALETTE.length];

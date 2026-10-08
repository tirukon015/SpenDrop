// Read-only access to ONE user's financial records for the AI tools. A repository is created per request for the
// authenticated user (AiContext.userId) and can't be pointed at anybody else: there is no user parameter on any
// method. The Supabase implementation (supabase-repository.ts) additionally runs every query under the user's own
// JWT, so Postgres Row Level Security enforces the same boundary in the database.
import { alive } from "@/lib/domain/ledger";
import type { Account, CategoryId, Dataset, Expense, ExpenseShare, MoneyMovement } from "@/lib/domain/types";

export interface InstantRange { start: Date | null; end: Date | null }

export interface ExpenseSet { expenses: Expense[]; shares: ExpenseShare[] }

/** Distinct names the planner can recognise in a question (the user's own merchants and accounts). */
export interface Vocabulary {
  merchants: string[];
  fundingAccounts: string[];
  currencies: string[];
  earliestDate: string | null;
  expenseCount: number;
}

/** A user's own rule: treat this merchant as this category (stored in ai_memories, never shared). */
export interface PersonalRule { merchant: string; merchantKey: string; category: CategoryId }

export interface FinanceRepository {
  /** The user's own personal rules (merchant → category). Empty when there are none or memory is off. */
  personalRules(): Promise<PersonalRule[]>;
  /** Non-deleted expenses in [start, end) with their non-deleted split shares. Throws TooMuchDataError above `limit`. */
  expenses(range: InstantRange, limit: number): Promise<ExpenseSet>;
  /** One non-deleted expense owned by the user, or null (also null for another user's id). */
  expense(id: string): Promise<ExpenseSet | null>;
  /** Non-deleted refunds (money movements of kind "refund") in [start, end). */
  refunds(range: InstantRange): Promise<MoneyMovement[]>;
  accounts(): Promise<Account[]>;
  vocabulary(): Promise<Vocabulary>;
}

export class TooMuchDataError extends Error {
  constructor() { super("too many records for one question"); }
}

/** A repository failure that must be reported as "couldn't access your data", never as "no data". */
export class DataUnavailableError extends Error {}

const within = (iso: string, r: InstantRange) => {
  const t = new Date(iso).getTime();
  return (!r.start || t >= r.start.getTime()) && (!r.end || t < r.end.getTime());
};

export function vocabularyOf(expenses: Pick<Expense, "merchant" | "fundingAccount" | "currency" | "date">[], accounts: Pick<Account, "name">[]): Vocabulary {
  const merchants = new Map<string, string>();
  const funding = new Map<string, string>();
  const currencies = new Set<string>();
  let earliest: string | null = null;
  for (const e of expenses) {
    const m = e.merchant?.trim();
    if (m && m.toLowerCase() !== "unknown") merchants.set(m.toLowerCase(), merchants.get(m.toLowerCase()) ?? m);
    const f = e.fundingAccount?.trim();
    if (f && f.toLowerCase() !== "unknown") funding.set(f.toLowerCase(), funding.get(f.toLowerCase()) ?? f);
    currencies.add(e.currency);
    if (!earliest || e.date < earliest) earliest = e.date;
  }
  for (const a of accounts) if (a.name.trim()) funding.set(a.name.trim().toLowerCase(), funding.get(a.name.trim().toLowerCase()) ?? a.name.trim());
  return { merchants: [...merchants.values()], fundingAccounts: [...funding.values()], currencies: [...currencies], earliestDate: earliest, expenseCount: expenses.length };
}

/**
 * In-memory repository over one user's dataset: used by the browser demo (synthetic data) and by tests. The dataset
 * must already belong to a single user — see MemoryTenantStore for the multi-user test double.
 */
export class MemoryRepository implements FinanceRepository {
  constructor(private readonly data: Pick<Dataset, "expenses" | "shares" | "movements" | "accounts">, private readonly rules: () => PersonalRule[] = () => []) {}

  async personalRules() {
    return this.rules();
  }

  private sharesFor(ids: Set<string>) {
    return this.data.shares.filter((s) => !s.deletedAt && ids.has(s.expenseId));
  }

  async expenses(range: InstantRange, limit: number): Promise<ExpenseSet> {
    const list = alive(this.data.expenses).filter((e) => within(e.date, range));
    if (list.length > limit) throw new TooMuchDataError();
    return { expenses: list, shares: this.sharesFor(new Set(list.map((e) => e.id))) };
  }

  async expense(id: string): Promise<ExpenseSet | null> {
    const e = this.data.expenses.find((x) => x.id === id && !x.deletedAt);
    return e ? { expenses: [e], shares: this.sharesFor(new Set([id])) } : null;
  }

  async refunds(range: InstantRange) {
    return alive(this.data.movements).filter((m) => m.kind === "refund" && within(m.date, range));
  }

  async accounts() {
    return alive(this.data.accounts);
  }

  async vocabulary() {
    return vocabularyOf(alive(this.data.expenses), alive(this.data.accounts));
  }
}

/** The ai_memories table isn't there yet (migration 20261010000000 not applied). */
export class MemoryNotSetUpError extends Error {}

/** Writes to the user's personal memory (AI-owned data only — never financial records). */
export interface MemoryStore {
  list(): Promise<PersonalRule[]>;
  setMerchantCategory(merchant: string, category: CategoryId): Promise<void>;
  /** Forget one merchant's rule (or all when null). Returns how many were removed. */
  forget(merchant: string | null): Promise<number>;
}

const keyOf = (merchant: string) => merchant.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
export const merchantKey = keyOf;

/** In-memory personal memory for one user (tests and the browser demo). */
export class MemoryRuleStore implements MemoryStore {
  constructor(readonly rules: PersonalRule[] = []) {}
  async list() { return [...this.rules]; }
  async setMerchantCategory(merchant: string, category: CategoryId) {
    const key = keyOf(merchant);
    const i = this.rules.findIndex((r) => r.merchantKey === key);
    const rule = { merchant: merchant.trim(), merchantKey: key, category };
    if (i >= 0) this.rules[i] = rule; else this.rules.push(rule);
  }
  async forget(merchant: string | null) {
    const before = this.rules.length;
    const key = merchant ? keyOf(merchant) : null;
    for (let i = this.rules.length - 1; i >= 0; i--) if (!key || this.rules[i].merchantKey === key) this.rules.splice(i, 1);
    return before - this.rules.length;
  }
}

/**
 * Test double for a multi-user database: every record is tagged with its owner and a repository only ever sees the
 * rows of the user it was opened for — the same guarantee RLS gives in Postgres.
 */
export class MemoryTenantStore {
  private readonly rows = new Map<string, { expenses: Expense[]; shares: ExpenseShare[]; movements: MoneyMovement[]; accounts: Account[] }>();
  private readonly memories = new Map<string, MemoryRuleStore>();

  /** The user's own memory store (each user has a separate one, like RLS on ai_memories). */
  memoryFor(userId: string): MemoryRuleStore {
    let m = this.memories.get(userId);
    if (!m) { m = new MemoryRuleStore(); this.memories.set(userId, m); }
    return m;
  }

  add(userId: string, data: Partial<{ expenses: Expense[]; shares: ExpenseShare[]; movements: MoneyMovement[]; accounts: Account[] }>) {
    const current = this.rows.get(userId) ?? { expenses: [], shares: [], movements: [], accounts: [] };
    current.expenses.push(...(data.expenses ?? []));
    current.shares.push(...(data.shares ?? []));
    current.movements.push(...(data.movements ?? []));
    current.accounts.push(...(data.accounts ?? []));
    this.rows.set(userId, current);
    return this;
  }

  forUser(userId: string): FinanceRepository {
    const memory = this.memoryFor(userId);
    return new MemoryRepository(this.rows.get(userId) ?? { expenses: [], shares: [], movements: [], accounts: [] }, () => [...memory.rules]);
  }
}

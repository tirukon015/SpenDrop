// FinanceRepository on Supabase, for the server route. Defence in depth for user isolation:
//   1. the client carries the signed-in user's own JWT (publishable key, NOT the service role), so Postgres RLS
//      only ever returns that user's rows;
//   2. every query also filters user_id = the authenticated id explicitly;
//   3. every returned row is checked to belong to that user before it is used (a mismatch is a security event).
import type { SupabaseClient } from "@supabase/supabase-js";
import { rowToRecord } from "@/lib/data/mapping";
import type { Account, Expense, ExpenseShare, MoneyMovement } from "@/lib/domain/types";
import type { CategoryId } from "@/lib/domain/types";
import { DataUnavailableError, TooMuchDataError, merchantKey, vocabularyOf, type ExpenseSet, type FinanceRepository, type InstantRange, type MemoryStore, type PersonalRule, type Vocabulary, MemoryNotSetUpError } from "./repository";

const isMissingTable = (e: { code?: string; message?: string }) => e.code === "42P01" || e.code === "PGRST205" || /does not exist|schema cache/.test(e.message ?? "");

const PAGE = 1000;
type Row = Record<string, unknown>;

export class SupabaseRepository implements FinanceRepository {
  private accountsCache: Promise<Account[]> | null = null;
  private rulesCache: Promise<PersonalRule[]> | null = null;
  private vocabularyCache: Promise<Vocabulary> | null = null;

  constructor(private readonly client: SupabaseClient, private readonly userId: string) {}

  /** Throws unless every row belongs to the authenticated user. */
  private own<T>(rows: Row[] | null): T[] {
    for (const r of rows ?? []) {
      if (r.user_id !== this.userId) {
        console.error("[ai][security] row owned by another user returned to an AI query — refusing");
        throw new DataUnavailableError("ownership check failed");
      }
    }
    return (rows ?? []).map((r) => rowToRecord<T>(r));
  }

  private fail(error: { code?: string; message?: string }): never {
    throw new DataUnavailableError(`query failed (${error.code ?? "unknown"})`);
  }

  async expenses(range: InstantRange, limit: number): Promise<ExpenseSet> {
    const rows: Row[] = [];
    for (let from = 0; ; from += PAGE) {
      let q = this.client.from("expenses").select("*").eq("user_id", this.userId).is("deleted_at", null);
      if (range.start) q = q.gte("date", range.start.toISOString());
      if (range.end) q = q.lt("date", range.end.toISOString());
      const { data, error } = await q.order("date", { ascending: false }).order("id", { ascending: true }).range(from, from + PAGE - 1);
      if (error) this.fail(error);
      rows.push(...(data ?? []));
      if (rows.length > limit) throw new TooMuchDataError();
      if (!data || data.length < PAGE) break;
    }
    const expenses = this.own<Expense>(rows);
    return { expenses, shares: await this.sharesFor(expenses.map((e) => e.id)) };
  }

  private async sharesFor(ids: string[]): Promise<ExpenseShare[]> {
    const out: ExpenseShare[] = [];
    for (let i = 0; i < ids.length; i += 150) {
      const { data, error } = await this.client.from("expense_shares").select("*").eq("user_id", this.userId).is("deleted_at", null).in("expense_id", ids.slice(i, i + 150));
      if (error) this.fail(error);
      out.push(...this.own<ExpenseShare>(data));
    }
    return out;
  }

  async expense(id: string): Promise<ExpenseSet | null> {
    const { data, error } = await this.client.from("expenses").select("*").eq("id", id).eq("user_id", this.userId).is("deleted_at", null).maybeSingle();
    if (error) this.fail(error);
    if (!data) return null;
    const [expense] = this.own<Expense>([data]);
    return { expenses: [expense], shares: await this.sharesFor([id]) };
  }

  async refunds(range: InstantRange): Promise<MoneyMovement[]> {
    let q = this.client.from("money_movements").select("*").eq("user_id", this.userId).eq("kind", "refund").is("deleted_at", null);
    if (range.start) q = q.gte("date", range.start.toISOString());
    if (range.end) q = q.lt("date", range.end.toISOString());
    const { data, error } = await q.limit(5000);
    if (error) this.fail(error);
    return this.own<MoneyMovement>(data);
  }

  /** The user's own rules. Before the memory migration is applied there simply are none. */
  personalRules(): Promise<PersonalRule[]> {
    this.rulesCache ??= (async () => {
      const { data, error } = await this.client.from("ai_memories").select("user_id, subject, label, value").eq("user_id", this.userId).eq("kind", "merchant_category").limit(500);
      if (error) {
        if (isMissingTable(error)) return [];
        this.fail(error);
      }
      for (const r of data ?? []) if (r.user_id !== this.userId) throw new DataUnavailableError("ownership check failed");
      return (data ?? []).map((r) => ({ merchant: r.label as string, merchantKey: r.subject as string, category: r.value as CategoryId }));
    })();
    return this.rulesCache;
  }

  accounts(): Promise<Account[]> {
    this.accountsCache ??= (async () => {
      const { data, error } = await this.client.from("accounts").select("*").eq("user_id", this.userId).is("deleted_at", null);
      if (error) this.fail(error);
      return this.own<Account>(data);
    })();
    return this.accountsCache;
  }

  vocabulary(): Promise<Vocabulary> {
    this.vocabularyCache ??= (async () => {
      const [recent, count, first, accounts] = await Promise.all([
        this.client.from("expenses").select("user_id, merchant, funding_account, currency, date").eq("user_id", this.userId).is("deleted_at", null).order("date", { ascending: false }).limit(5000),
        this.client.from("expenses").select("id", { count: "exact", head: true }).eq("user_id", this.userId).is("deleted_at", null),
        this.client.from("expenses").select("user_id, date").eq("user_id", this.userId).is("deleted_at", null).order("date", { ascending: true }).limit(1),
        this.accounts(),
      ]);
      for (const r of [recent, count, first]) if (r.error) this.fail(r.error);
      const rows = this.own<Pick<Expense, "merchant" | "fundingAccount" | "currency" | "date">>(recent.data);
      this.own(first.data);
      const v = vocabularyOf(rows, accounts);
      const earliest = (first.data?.[0]?.date as string | undefined) ?? v.earliestDate;
      return { ...v, earliestDate: earliest, expenseCount: count.count ?? rows.length };
    })();
    return this.vocabularyCache;
  }
}

/** The user's personal memory in Supabase (ai_memories, migration 20261010000000): user JWT + explicit user filter. */
export class SupabaseMemoryStore implements MemoryStore {
  constructor(private readonly client: SupabaseClient, private readonly userId: string) {}

  private check(error: { code?: string; message?: string } | null) {
    if (!error) return;
    if (isMissingTable(error)) throw new MemoryNotSetUpError();
    throw new DataUnavailableError(`memory query failed (${error.code ?? "unknown"})`);
  }

  async list(): Promise<PersonalRule[]> {
    const { data, error } = await this.client.from("ai_memories").select("user_id, subject, label, value").eq("user_id", this.userId).order("label");
    this.check(error);
    return (data ?? []).filter((r) => r.user_id === this.userId).map((r) => ({ merchant: r.label, merchantKey: r.subject, category: r.value as CategoryId }));
  }

  async setMerchantCategory(merchant: string, category: CategoryId) {
    const { error } = await this.client.from("ai_memories").upsert(
      { user_id: this.userId, kind: "merchant_category", subject: merchantKey(merchant), label: merchant.trim().slice(0, 80), value: category, source: "explicit", updated_at: new Date().toISOString() },
      { onConflict: "user_id,kind,subject" });
    this.check(error);
  }

  async forget(merchant: string | null) {
    let q = this.client.from("ai_memories").delete().eq("user_id", this.userId);
    if (merchant) q = q.eq("subject", merchantKey(merchant));
    const { data, error } = await q.select("id");
    this.check(error);
    return (data ?? []).length;
  }
}

"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { NewAllocation, NewPayment } from "@/lib/domain/ledger";
import type { Expense, ExpenseShare, TableName } from "@/lib/domain/types";
import { recordToRow } from "./mapping";
import { DataError, type BackupMeta, type DataSource, type PulledRows } from "./source";

const PAGE = 1000;

/** expenses.split_rule is added by migration 20261008000000_hybrid_split (may not be applied yet). */
const withoutSplitRule = (row: Record<string, unknown>) => {
  const { split_rule: _rule, ...rest } = row; // eslint-disable-line @typescript-eslint/no-unused-vars
  return rest;
};
/** Normal expenses don't send the new column at all, so they save the same before and after the migration. */
const withoutEmptySplitRule = (row: Record<string, unknown>) => (row.split_rule == null ? withoutSplitRule(row) : row);

export class SupabaseSource implements DataSource {
  readonly kind = "supabase" as const;
  constructor(
    private readonly client: SupabaseClient,
    readonly userId: string,
    readonly email: string | null,
    readonly provider: string | null,
    readonly displayName: string | null = null,
  ) {}

  async pull(table: TableName, since: string | null): Promise<PulledRows> {
    const rows: Record<string, unknown>[] = [];
    let cursor = since;
    // Keyset pagination on server_updated_at (+ id) so large data sets load in pages and nothing is skipped.
    for (;;) {
      let query = this.client.from(table).select("*").order("server_updated_at", { ascending: true }).order("id", { ascending: true }).limit(PAGE);
      if (cursor) query = query.gt("server_updated_at", cursor);
      const { data, error } = await query;
      if (error) throw error;
      rows.push(...(data ?? []));
      if (!data || data.length < PAGE) break;
      const last = data[data.length - 1].server_updated_at as string;
      // Rows sharing the exact last timestamp: fetch them with gte to avoid skipping any.
      const { data: same, error: sameError } = await this.client.from(table).select("*").eq("server_updated_at", last);
      if (sameError) throw sameError;
      const seen = new Set(rows.map((r) => r.id));
      rows.push(...(same ?? []).filter((r) => !seen.has(r.id)));
      cursor = last;
    }
    const max = rows.reduce<string | null>((m, r) => (!m || (r.server_updated_at as string) > m ? (r.server_updated_at as string) : m), since);
    return { rows, cursor: max };
  }

  async upsert(table: TableName, rows: Record<string, unknown>[]) {
    const list = table === "expenses" ? rows.map(withoutEmptySplitRule) : rows;
    for (let i = 0; i < list.length; i += 500) {
      const page = list.slice(i, i + 500);
      let { error } = await this.client.from(table).upsert(page, { onConflict: "id" });
      // Before migration 20261008000000 expenses.split_rule doesn't exist yet: save without it (the split stays a
      // plain custom-amount split, exactly like the save RPC does).
      if (error && table === "expenses" && error.message?.includes("split_rule")) {
        ({ error } = await this.client.from(table).upsert(page.map(withoutSplitRule), { onConflict: "id" }));
      }
      if (error) throw error;
    }
  }

  async saveExpense(expense: Expense, shares: Omit<ExpenseShare, "expenseId" | "deletedAt">[]) {
    const { error } = await this.client.rpc("save_expense_with_shares", {
      p_expense: recordToRow(expense),
      p_shares: shares.map((s) => recordToRow(s)),
    });
    if (error) throw error;
  }

  async recordSettlement(payments: NewPayment[], allocations: (NewAllocation & { id: string })[]) {
    const { error } = await this.client.rpc("record_settlement", {
      p_payments: payments.map((p) => ({ ...recordToRow(p), person_name_snapshot: p.personName })),
      p_allocations: allocations.map((a) => recordToRow(a)),
    });
    if (error) throw error;
  }

  async uploadReceipt(file: Blob, expenseId: string) {
    const ext = file.type === "image/jpeg" ? "jpg" : file.type === "image/png" ? "png" : "webp";
    const path = `${this.userId}/${expenseId}/${crypto.randomUUID()}.${ext}`;
    const { error } = await this.client.storage.from("receipts").upload(path, file, { contentType: file.type, upsert: false });
    if (error) throw error;
    return path;
  }

  async receiptUrl(path: string) {
    const { data } = await this.client.storage.from("receipts").createSignedUrl(path, 60 * 10);
    return data?.signedUrl ?? null;
  }

  async removeReceipt(path: string) {
    await this.client.storage.from("receipts").remove([path]);
  }

  async listBackups(): Promise<BackupMeta[]> {
    const { data, error } = await this.client.from("backups").select("*").order("created_at", { ascending: false }).limit(30);
    if (error) throw error;
    return (data ?? []).map((r) => ({
      id: r.id, deviceName: r.device_name, appVersion: r.app_version, createdAt: r.created_at, objectPath: r.object_path,
      expensesCount: r.expenses_count, peopleCount: r.people_count, accountsCount: r.accounts_count, movementsCount: r.movements_count,
      sizeBytes: r.size_bytes,
    }));
  }

  async downloadBackup(objectPath: string) {
    const { data, error } = await this.client.storage.from("backups").download(objectPath);
    if (error || !data) throw error ?? new DataError("Couldn't download that backup.");
    return JSON.parse(await data.text());
  }

  async signOut() {
    await this.client.auth.signOut();
  }

  /** Deletes the user's receipt and backup files, then the account (rows cascade in the database). */
  async deleteAccount() {
    for (const bucket of ["receipts", "backups"]) {
      const folders = await this.client.storage.from(bucket).list(this.userId, { limit: 1000 });
      for (const folder of folders.data ?? []) {
        const files = await this.client.storage.from(bucket).list(`${this.userId}/${folder.name}`, { limit: 1000 });
        const paths = (files.data ?? []).map((f) => `${this.userId}/${folder.name}/${f.name}`);
        if (paths.length) await this.client.storage.from(bucket).remove(paths);
      }
    }
    const { error } = await this.client.rpc("delete_my_account");
    if (error) throw error;
    await this.client.auth.signOut();
  }
}

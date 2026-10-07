"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { planBackupImport, type ImportSummary } from "@/lib/data/backup-import";
import { clearCache, readCache, writeCache } from "@/lib/data/cache";
import { DemoSource } from "@/lib/data/demo-source";
import { recordToRow, rowToRecord, TABLES } from "@/lib/data/mapping";
import { friendlyError, type DataSource } from "@/lib/data/source";
import { SupabaseSource } from "@/lib/data/supabase-source";
import { alive, sharesByExpense, undoTargets, type SettlementPlan } from "@/lib/domain/ledger";
import type { Account, Dataset, Expense, ExpenseShare, ID, MoneyMovement, Person, PersonPaymentMethod, TableName } from "@/lib/domain/types";
import { emptyDataset } from "@/lib/domain/types";
import { isDemoMode } from "@/lib/supabase/config";
import { useOnline } from "@/lib/use-stored";
import { createClient } from "@/lib/supabase/client";

export type SyncStatus = "loading" | "syncing" | "ready" | "offline" | "error";

export interface DataContextValue {
  source: DataSource | null;
  status: SyncStatus;
  error: string | null;
  lastSyncedAt: string | null;
  online: boolean;
  /** All records incl. tombstones (for sync); use the `live` views in screens. */
  dataset: Dataset;
  live: {
    expenses: Expense[];
    shares: Map<ID, ExpenseShare[]>;
    movements: MoneyMovement[];
    people: Person[];
    accounts: Account[];
    paymentMethods: PersonPaymentMethod[];
    allocations: Dataset["allocations"];
  };
  refresh: () => Promise<void>;
  saveExpense: (expense: Expense, shares: Omit<ExpenseShare, "expenseId" | "deletedAt">[]) => Promise<void>;
  deleteExpense: (expense: Expense) => Promise<void>;
  saveRecords: <K extends keyof Dataset>(key: K, records: Dataset[K]) => Promise<void>;
  deleteRecord: <K extends keyof Dataset>(key: K, record: Dataset[K][number]) => Promise<void>;
  recordSettlement: (plan: SettlementPlan) => Promise<void>;
  undoSettlement: (groupId: ID) => Promise<void>;
  importBackup: (payload: unknown, includeSample: boolean) => Promise<ImportSummary>;
  signOut: () => Promise<void>;
  deleteAccount: () => Promise<void>;
}

const DataContext = createContext<DataContextValue | null>(null);

export function useData() {
  const value = useContext(DataContext);
  if (!value) throw new Error("useData must be used inside <DataProvider>");
  return value;
}

const tableFor = (key: keyof Dataset): TableName => TABLES.find((t) => t.key === key)!.table;

function merge<T extends { id: ID }>(list: T[], incoming: T[]): T[] {
  if (incoming.length === 0) return list;
  const map = new Map(list.map((r) => [r.id, r]));
  for (const r of incoming) map.set(r.id, r);
  return [...map.values()];
}

export function DataProvider({ children }: { children: ReactNode }) {
  const [source, setSource] = useState<DataSource | null>(null);
  const [dataset, setDataset] = useState<Dataset>(emptyDataset);
  const [status, setStatus] = useState<SyncStatus>("loading");
  const [error, setError] = useState<string | null>(null);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const online = useOnline();
  const cursors = useRef<Partial<Record<TableName, string | null>>>({});
  const datasetRef = useRef(dataset);
  useEffect(() => {
    datasetRef.current = dataset;
  }, [dataset]);
  const syncing = useRef<Promise<void> | null>(null);

  // 1. Resolve the data source (signed-in Supabase user, or the local demo).
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (isDemoMode) {
        if (!cancelled) setSource(new DemoSource());
        return;
      }
      const client = createClient();
      const { data } = await client.auth.getUser();
      if (cancelled) return;
      if (!data.user) {
        setStatus("error");
        setError("Your session has ended. Please sign in again.");
        return;
      }
      setSource(new SupabaseSource(client, data.user.id, data.user.email ?? null, (data.user.app_metadata?.provider as string) ?? null,
        (typeof data.user.user_metadata?.full_name === "string" ? data.user.user_metadata.full_name : typeof data.user.user_metadata?.name === "string" ? data.user.user_metadata.name : null)));
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // 2. Pull changes since the last cursor for every table and merge them in.
  const sync = useCallback(async () => {
    if (!source) return;
    if (syncing.current) return syncing.current;
    const run = (async () => {
      if (typeof navigator !== "undefined" && !navigator.onLine) {
        setStatus("offline");
        return;
      }
      setStatus((s) => (s === "loading" ? "loading" : "syncing"));
      try {
        let next = datasetRef.current;
        for (const { table, key } of TABLES) {
          const pulled = await source.pull(table, cursors.current[table] ?? null);
          if (pulled.rows.length) {
            next = { ...next, [key]: merge(next[key] as { id: ID }[], pulled.rows.map((r) => rowToRecord(r))) };
          }
          cursors.current[table] = pulled.cursor;
        }
        const now = new Date().toISOString();
        datasetRef.current = next;
        setDataset(next);
        setLastSyncedAt(now);
        setError(null);
        setStatus("ready");
        await writeCache(source.userId, { dataset: next, cursors: cursors.current, lastSyncedAt: now });
      } catch (e) {
        setError(friendlyError(e));
        setStatus(datasetRef.current.expenses.length ? "ready" : "error");
      }
    })();
    syncing.current = run;
    try {
      await run;
    } finally {
      syncing.current = null;
    }
  }, [source]);

  // 3. Start: show the cached copy instantly, then sync. Re-sync on focus / reconnect / every 2 minutes.
  useEffect(() => {
    if (!source) return;
    let cancelled = false;
    (async () => {
      const cached = await readCache(source.userId);
      if (!cancelled && cached) {
        datasetRef.current = cached.dataset;
        setDataset(cached.dataset);
        cursors.current = cached.cursors;
        setLastSyncedAt(cached.lastSyncedAt);
        setStatus("syncing");
      }
      if (!cancelled) await sync();
    })();
    const onFocus = () => document.visibilityState === "visible" && sync();
    const onOnline = () => sync();
    const onOffline = () => setStatus("offline");
    document.addEventListener("visibilitychange", onFocus);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    const timer = window.setInterval(() => document.visibilityState === "visible" && sync(), 120_000);
    return () => {
      cancelled = true;
      document.removeEventListener("visibilitychange", onFocus);
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
      window.clearInterval(timer);
    };
  }, [source, sync]);

  const requireOnline = () => {
    if (typeof navigator !== "undefined" && !navigator.onLine) throw new Error("You're offline. Your changes weren't saved — connect and try again.");
  };

  const saveExpense = useCallback(async (expense: Expense, shares: Omit<ExpenseShare, "expenseId" | "deletedAt">[]) => {
    if (!source) return;
    requireOnline();
    await source.saveExpense(expense, shares);
    await sync();
  }, [source, sync]);

  const deleteExpense = useCallback(async (expense: Expense) => {
    if (!source) return;
    requireOnline();
    const now = new Date().toISOString();
    // Tombstone the expense and its shares in one atomic save (other devices learn about the deletion).
    await source.saveExpense({ ...expense, deletedAt: now, updatedAt: now }, []);
    if (expense.receiptPath) await source.removeReceipt(expense.receiptPath).catch(() => undefined);
    await sync();
  }, [source, sync]);

  const saveRecords = useCallback(async <K extends keyof Dataset>(key: K, records: Dataset[K]) => {
    if (!source || records.length === 0) return;
    requireOnline();
    await source.upsert(tableFor(key), (records as object[]).map((r) => recordToRow(r)));
    await sync();
  }, [source, sync]);

  const deleteRecord = useCallback(async <K extends keyof Dataset>(key: K, record: Dataset[K][number]) => {
    const now = new Date().toISOString();
    await saveRecords(key, [{ ...(record as object), deletedAt: now, updatedAt: now }] as Dataset[K]);
  }, [saveRecords]);

  const recordSettlement = useCallback(async (plan: SettlementPlan) => {
    if (!source) return;
    requireOnline();
    await source.recordSettlement(plan.payments, plan.allocations.map((a) => ({ ...a, id: crypto.randomUUID() })));
    await sync();
  }, [source, sync]);

  const undoSettlement = useCallback(async (groupId: ID) => {
    if (!source) return;
    requireOnline();
    const now = new Date().toISOString();
    const { allocationIds, paymentIds } = undoTargets(groupId, datasetRef.current.allocations);
    const allocations = datasetRef.current.allocations.filter((a) => allocationIds.includes(a.id)).map((a) => ({ ...a, deletedAt: now, updatedAt: now }));
    const payments = datasetRef.current.movements.filter((m) => paymentIds.includes(m.id)).map((m) => ({ ...m, deletedAt: now, updatedAt: now }));
    await source.upsert("settlement_allocations", allocations.map((r) => recordToRow(r)));
    if (payments.length) await source.upsert("money_movements", payments.map((r) => recordToRow(r)));
    await sync();
  }, [source, sync]);

  const importBackup = useCallback(async (payload: unknown, includeSample: boolean) => {
    if (!source) throw new Error("Not ready yet.");
    requireOnline();
    await sync();
    const plan = planBackupImport(payload, datasetRef.current, { includeSample });
    for (const { table, key } of TABLES) {
      const rows = (plan.records[key] as object[]).map((r) => recordToRow(r));
      if (rows.length) await source.upsert(table, rows);
    }
    await sync();
    return plan.summary;
  }, [source, sync]);

  const signOut = useCallback(async () => {
    await clearCache();
    await source?.signOut();
    // Full reload on purpose: nothing from this account may stay in memory after signing out.
    window.location.assign(`${window.location.origin}/login`); // eslint-disable-line @next/next/no-location-assign-relative-destination
  }, [source]);

  const deleteAccount = useCallback(async () => {
    if (!source) return;
    requireOnline();
    await source.deleteAccount();
    await clearCache();
    window.location.assign(`${window.location.origin}/login?deleted=1`); // eslint-disable-line @next/next/no-location-assign-relative-destination
  }, [source]);

  const live = useMemo(() => ({
    expenses: alive(dataset.expenses).sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0)),
    shares: sharesByExpense(dataset.shares),
    movements: alive(dataset.movements).sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0)),
    people: alive(dataset.people).sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" })),
    accounts: alive(dataset.accounts).sort((a, b) => a.sortIndex - b.sortIndex || a.name.localeCompare(b.name)),
    paymentMethods: alive(dataset.paymentMethods),
    allocations: alive(dataset.allocations),
  }), [dataset]);

  const value: DataContextValue = {
    source, status, error, lastSyncedAt, online, dataset, live, refresh: sync, saveExpense, deleteExpense, saveRecords, deleteRecord,
    recordSettlement, undoSettlement, importBackup, signOut, deleteAccount,
  };
  return <DataContext.Provider value={value}>{children}</DataContext.Provider>;
}

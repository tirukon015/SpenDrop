"use client";

// Per-user local cache (IndexedDB) so the app opens instantly and can be read offline. It is a cache, not a
// second source of truth: the cloud records win, and it is wiped on sign-out (shared computers).
import type { Dataset, TableName } from "@/lib/domain/types";

const DB_NAME = "spendrop";
const STORE = "cache";

export interface CachedState {
  dataset: Dataset;
  cursors: Partial<Record<TableName, string | null>>;
  lastSyncedAt: string | null;
}

function open(): Promise<IDBDatabase | null> {
  if (typeof indexedDB === "undefined") return Promise.resolve(null);
  return new Promise((resolve) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(null);
  });
}

export async function readCache(userId: string): Promise<CachedState | null> {
  const db = await open();
  if (!db) return null;
  return new Promise((resolve) => {
    const request = db.transaction(STORE, "readonly").objectStore(STORE).get(userId);
    request.onsuccess = () => resolve((request.result as CachedState) ?? null);
    request.onerror = () => resolve(null);
  });
}

export async function writeCache(userId: string, state: CachedState): Promise<void> {
  const db = await open();
  if (!db) return;
  await new Promise<void>((resolve) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put(state, userId);
    tx.oncomplete = () => resolve();
    tx.onerror = () => resolve();
  });
}

export async function clearCache(): Promise<void> {
  const db = await open();
  if (!db) return;
  await new Promise<void>((resolve) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).clear();
    tx.oncomplete = () => resolve();
    tx.onerror = () => resolve();
  });
}

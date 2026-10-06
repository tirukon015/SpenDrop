"use client";

// Browser-storage backed state via useSyncExternalStore (renders the default on the server and during hydration,
// then the stored value — no setState-in-effect, no hydration mismatch). Storage failures fall back to memory.
import { useCallback, useMemo, useSyncExternalStore } from "react";

const EVENT = "spendrop-storage";
const memory = new Map<string, string>();

function read(storage: "local" | "session", key: string): string | null {
  try {
    return (storage === "local" ? localStorage : sessionStorage).getItem(key) ?? memory.get(key) ?? null;
  } catch {
    return memory.get(key) ?? null;
  }
}

export function writeStored(storage: "local" | "session", key: string, value: string) {
  memory.set(key, value);
  try {
    (storage === "local" ? localStorage : sessionStorage).setItem(key, value);
  } catch {}
  window.dispatchEvent(new CustomEvent(EVENT, { detail: key }));
}

function subscribe(callback: () => void) {
  window.addEventListener(EVENT, callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener(EVENT, callback);
    window.removeEventListener("storage", callback);
  };
}

/** JSON value persisted in session/local storage. */
export function useStored<T>(storage: "local" | "session", key: string, fallback: T): [T, (value: T) => void] {
  const raw = useSyncExternalStore(subscribe, () => read(storage, key), () => null);
  const value = useMemo(() => {
    if (raw === null) return fallback;
    try {
      const parsed = JSON.parse(raw);
      return typeof fallback === "object" && fallback !== null && !Array.isArray(fallback) ? { ...fallback, ...parsed } : (parsed as T);
    } catch {
      return fallback;
    }
  }, [raw]); // eslint-disable-line react-hooks/exhaustive-deps -- fallback is a constant default
  const set = useCallback((next: T) => writeStored(storage, key, JSON.stringify(next)), [storage, key]);
  return [value, set];
}

function subscribeOnline(callback: () => void) {
  window.addEventListener("online", callback);
  window.addEventListener("offline", callback);
  return () => {
    window.removeEventListener("online", callback);
    window.removeEventListener("offline", callback);
  };
}

/** navigator.onLine as React state. */
export function useOnline() {
  return useSyncExternalStore(subscribeOnline, () => navigator.onLine, () => true);
}

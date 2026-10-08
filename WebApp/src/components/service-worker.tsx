"use client";

import { useEffect } from "react";

/** Registers /sw.js in production only (offline page + app shell; never caches financial data or API calls). */
export function ServiceWorker() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    if (process.env.NODE_ENV !== "production") {
      // A worker left over from a production build on the same localhost port would serve stale dev chunks
      // (dev chunk names aren't content-hashed): remove it and its cache in development.
      navigator.serviceWorker.getRegistrations().then((regs) => regs.forEach((r) => r.unregister())).catch(() => undefined);
      if ("caches" in window) caches.keys().then((keys) => keys.forEach((k) => caches.delete(k))).catch(() => undefined);
      return;
    }
    navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" }).catch(() => undefined);
  }, []);
  return null;
}

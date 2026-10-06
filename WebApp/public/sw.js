// SpenDrop service worker. Deliberately small: it only makes the installed app open when offline by serving
// cached static assets and an offline page. It never caches Supabase/API responses or any financial data —
// the app's own per-user IndexedDB cache handles offline reading and is cleared on sign-out.
const CACHE = "spendrop-shell-v1";
const OFFLINE_URL = "/offline";

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll([OFFLINE_URL, "/icon.svg"])).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Supabase and other origins: never touched
  if (url.pathname.startsWith("/_next/static/")) {
    // Immutable build assets: cache first.
    event.respondWith(
      caches.match(request).then((hit) => hit || fetch(request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(request, copy));
        return response;
      })),
    );
    return;
  }
  if (request.mode === "navigate") {
    // Pages: always network (they need the session); offline → offline page.
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)));
  }
});

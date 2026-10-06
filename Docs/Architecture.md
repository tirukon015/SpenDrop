# SpenDrop platform architecture

> **One SpenDrop account. One financial data set. Every device.**

```
            ┌──────────────── Common/ (contracts) ────────────────┐
            │ constants · data model · business rules · tokens     │
            └───────────────┬───────────────────┬─────────────────┘
                            │ same rules         │ same rules
   ┌────────────────────────▼──────┐   ┌─────────▼───────────────────────┐
   │ iOS (SwiftUI, SwiftData)      │   │ Web (Next.js, React, TS)         │
   │ local-first; Apple Vision OCR │   │ IndexedDB cache; tesseract.js OCR│
   │ Share Extension, Apple Pay    │   │ PWA; Web Share API               │
   └───────────────┬───────────────┘   └─────────────┬───────────────────┘
       backup JSON │ (today)              records     │ (today, RLS)
                   ▼                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ Supabase: Auth (Google, email) · Postgres + RLS · private Storage │
   │ backups (iOS snapshots) · cloud records (accounts … channel_rules)│
   └──────────────────────────────────────────────────────────────────┘
```

## Clients

| | iOS | Web |
|---|---|---|
| Source of truth on device | SwiftData store (local-first, works signed out) | Cloud records; per-user IndexedDB cache for instant load and offline reading |
| OCR | Apple Vision, on device | tesseract.js, in the browser (free, open source; the image never leaves the device) |
| Sharing | iOS share sheet + Share Extension | Web Share API, clipboard fallback; never public links |
| Money | integer sen (`Money.swift`) | integer sen (`lib/domain/money.ts`) |
| Rules | `SplitDraft`, `SplitCalculator`, `FinancialCalculator`, `PersonLedger` | ports in `lib/domain/{split,ledger,analytics}.ts`, tested against `Common/BusinessRules/*.json` |

## Accounts — three different things

1. **SpenDrop account** — the login (Supabase Auth: Google or email/password). Owns all data via `user_id`.
2. **Funding account** — where money came from (Maybank, CIMB, RHB, Wise, Touch 'n Go, Cash). `accounts` table +
   the `funding_account` text on each expense (as on iOS).
3. **Payment channel** — how it was paid (Apple Pay, DuitNow QR, Card, Bank Transfer…). An enum, never an account.
   `UNKNOWN` is a valid, explicit value; nothing guesses a channel without evidence.

## Backend

- **Auth**: Supabase Auth. Web uses `@supabase/ssr` cookies; `proxy.ts` refreshes the session with `getClaims()` and
  sends signed-out visitors to `/login`. OAuth/PKCE callback: `/auth/callback`; email links: `/auth/confirm`.
- **Data**: `Supabase/supabase/migrations/20261007000000_spendrop_cloud_records.sql` (additive). Nine tables, all with
  RLS (owner-only select/insert/update; no client DELETE), composite foreign keys `(id, user_id)` so rows can never
  point at another user's records, CHECK constraints for money/enums, server-maintained `server_updated_at`.
- **Atomic writes**: `save_expense_with_shares` and `record_settlement` (SECURITY INVOKER — RLS still applies)
  save an expense with its split, or a payment with its allocations, as one transaction; the split must add up.
- **Storage**: private `receipts` bucket (owner folder only, ≤3 MB, images); existing private `backups` bucket.
- **Keys**: only the public URL + publishable/anon key are in clients. No service-role key, no database password,
  anywhere in the apps or the repo.

## Web App structure (`WebApp/src`)

```
app/                 routes (App Router). (app)/ = signed-in area, streamed behind Suspense
  page.tsx           Home        transactions/  list, [id] detail/edit, m/[id] money movement
  add/               Add         paybook/       list, [id] person
  breakdown/         Breakdown   more/          account, accounts, import, reference
  login/, auth/      sign-in, callbacks, password update     offline/, manifest, icons
components/          app shell (sidebar/rail/tab bar), UI kit, split editor, transaction form, charts
lib/domain/          money, split, ledger, analytics, dates, activity, constants, types (pure, unit-tested)
lib/data/            DataSource (Supabase | demo), sync/cache, backup import, mapping
lib/ocr/             known merchants, evidence-first classification, receipt parser, browser OCR
lib/supabase/        browser/server clients, session proxy
proxy.ts             session refresh + route protection
```

Rendering: Cache Components are on; signed-in screens are client components streamed behind a Suspense boundary
(never prerendered with user data). Data is read through a `DataProvider` that pulls changed rows per table
(cursor = `server_updated_at`), merges them, and caches them per user in IndexedDB (wiped on sign-out).

## Security summary

RLS on every table and storage bucket; no client hard deletes; no public financial URLs (receipts via 10-minute
signed URLs); open-redirect-safe callbacks; security headers (HSTS, frame-deny, nosniff, referrer, permissions);
the service worker never caches API responses or financial data. See `Docs/Sync-Architecture.md` for data safety.

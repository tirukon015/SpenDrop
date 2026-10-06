# Web App setup, deployment and operations

## Run locally

```bash
cd WebApp
npm install
cp .env.example .env.local      # fill in the PUBLIC Supabase URL + publishable/anon key
npm run dev                     # http://localhost:3000
```

Without a Supabase project you can explore the full UI with synthetic data kept only in your browser:

```bash
NEXT_PUBLIC_SPENDROP_DEMO=1 npm run dev
```

## Checks

```bash
npm run typecheck     # TypeScript
npm run lint          # ESLint (Next.js + React rules)
npm test              # 81 unit tests: domain rules, Common contract vectors, OCR parsing,
                      #   and the real Supabase migrations on in-memory Postgres (RLS, cross-user, tombstones)
npm run build         # production build
npm run test:e2e      # Playwright: phone/tablet/laptop/desktop, flows + axe accessibility (demo mode)
```

## One-time Supabase setup (production project)

The Web App stores data in **cloud records** tables. They are added by an **additive** migration — it creates new
tables, policies, two functions and a private `receipts` bucket; it does not modify or drop anything that exists
(the iOS `backups` table/bucket and `delete_my_account()` are untouched). It is idempotent (safe to run twice).

1. Supabase Dashboard → your project → **SQL Editor** → New query.
2. Paste the contents of `Supabase/supabase/migrations/20261007000000_spendrop_cloud_records.sql` → **Run**.
   (Or with the CLI: `cd Supabase && supabase link --project-ref <ref> && supabase db push`.)
3. Database → **Advisors**: there should be no new security warnings for these tables.

> The migration was verified on an in-memory Postgres (PGlite) by `WebApp/tests/db/supabase-migrations.test.ts`
> (12+ security/data checks). It was **not** applied to production automatically: that needs your Supabase access.

## Sign-in redirect URLs (Supabase → Authentication → URL Configuration)

Add these to **Redirect URLs** (keep the existing iOS `spendrop://auth-callback`):

```
https://<your-vercel-domain>/auth/callback
https://<your-vercel-domain>/auth/confirm
http://localhost:3000/auth/callback
```

Google sign-in uses the Google provider you already enabled for iOS; no Google Cloud change is needed because
Google redirects to Supabase, and Supabase redirects to the URLs above.

Optional: set **Site URL** to the Web App's production URL if you want email links (confirm, reset) to open the
Web App by default. Leave it as is to keep the iOS behaviour unchanged.

## Deploy (Vercel)

- Project root directory: **`WebApp`** (framework: Next.js, build: `npm run build`).
- Environment variables (Production + Preview), public values only:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (or `NEXT_PUBLIC_SUPABASE_ANON_KEY`)
- Never add a service-role key or database password to Vercel for this app — nothing in it needs them.
- Do **not** set `NEXT_PUBLIC_SPENDROP_DEMO` in production.

## Security checklist

- RLS on every table and the `receipts` bucket (owner folder only); anon role has no access.
- Clients cannot hard-delete; tombstones only; account deletion cascades.
- Composite foreign keys prevent linking to another user's rows.
- Receipts are only reachable through short-lived signed URLs.
- `proxy.ts` uses `getClaims()` (validated JWT) for route protection; data access is authorised by RLS, not the UI.
- Callback `next` parameters only accept same-site paths (no open redirects).

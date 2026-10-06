# Supabase (shared backend)

Standard Supabase CLI layout: `Supabase/supabase/migrations/`.

| Migration | What it does |
|---|---|
| `20260929000000_spendrop_cloud_backup.sql` | iOS cloud backup: `backups` table, private `backups` bucket, `delete_my_account()` (already applied in production) |
| `20261007000000_spendrop_cloud_records.sql` | **Additive.** Cloud records for the Web App and future sync: 9 tables with RLS, composite owner foreign keys, tombstones, `server_updated_at` cursors, `save_expense_with_shares` / `record_settlement` (SECURITY INVOKER), private `receipts` bucket. **Not yet applied in production** — see `Docs/WebApp-Setup.md`. |

Apply: SQL Editor (paste & run) or `cd Supabase && supabase link --project-ref <ref> && supabase db push`.
Tested locally on in-memory Postgres: `cd WebApp && npm test` (tests/db).

Never commit secrets here: no service-role key, no database password, no `.env`.

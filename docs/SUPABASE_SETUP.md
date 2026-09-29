# SpenDrop — Account & Cloud Backup Setup (Supabase, free tier)

SpenDrop is local-first. Without this setup the app works fully; More → Account just says cloud backup isn't set up.
Everything below uses free tiers only. No secret key is ever put in the app.

## What you need
- A Supabase project (free plan).
- A Google Cloud project (free) for "Continue with Google".

## 1. Create the Supabase project
1. https://supabase.com → New project (free plan). Pick a region close to you (e.g. Singapore).
2. Project Settings → API. Note:
   - **Project URL** (`https://<ref>.supabase.co`)
   - **anon / public key** (safe for apps; access is enforced by Row Level Security)
   - Do NOT use the `service_role` key anywhere in the app.

## 2. Create the backup table, storage bucket and policies
1. Supabase → SQL Editor → New query.
2. Paste the whole file `supabase/migrations/20260929000000_spendrop_cloud_backup.sql` and Run.
   It creates: table `public.backups` (RLS: owner only), private bucket `backups` (owner-only folder policies,
   no public URLs, no overwrite), and function `delete_my_account()` (a user can delete only their own account).
3. Check: Table Editor → `backups` shows "RLS enabled"; Storage → `backups` is **Private**.


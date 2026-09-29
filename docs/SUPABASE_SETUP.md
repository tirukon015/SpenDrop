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

## 3. Google OAuth client (Google Cloud Console)
1. https://console.cloud.google.com → create/select a project.
2. APIs & Services → OAuth consent screen: External, app name "SpenDrop", your support email; add your
   Google account as a test user while in Testing mode.
3. APIs & Services → Credentials → Create credentials → OAuth client ID → **Web application**.
   - Authorized redirect URI: `https://<ref>.supabase.co/auth/v1/callback`
4. Copy the **Client ID** and **Client secret** (the secret goes ONLY into Supabase, never into the app).

## 4. Supabase auth settings
1. Authentication → Sign In / Providers → **Google**: enable, paste Client ID and Client secret, Save.
2. Authentication → Sign In / Providers → **Email**: enabled. Choose whether "Confirm email" is on
   (the app handles both: with confirmation it asks the user to check their email, then sign in).
3. Authentication → URL Configuration → Redirect URLs → add: `spendrop://auth-callback`

## 5. App configuration (Xcode)
1. Copy `SpenDrop/Resources/CloudConfig/SupabaseConfig.example.plist` to
   `SpenDrop/Resources/CloudConfig/SupabaseConfig.plist` (this file is git-ignored).
2. Fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` (public values from step 1).
3. The URL scheme `spendrop` is already registered in `SpenDrop/Resources/Info.plist` (CFBundleURLTypes);
   the Google sign-in sheet returns to `spendrop://auth-callback`. Nothing else to add.
4. Build and run.


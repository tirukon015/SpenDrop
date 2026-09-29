-- SpenDrop cloud backup (Supabase free tier).
-- Run once in the Supabase SQL editor (or `supabase db push`). Every rule is enforced on the server:
-- a signed-in user can only read, add or delete their OWN backups. No service-role key is used by the app.

-- 1. Backup metadata (one row per uploaded backup file)
create table if not exists public.backups (
    id              uuid primary key,
    user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
    device_id       text not null,
    device_name     text not null default '',
    app_version     text not null default '',
    schema_version  text not null default '',
    backup_version  integer not null,
    created_at      timestamptz not null default now(),
    object_path     text not null,
    expenses_count  integer not null default 0,
    people_count    integer not null default 0,
    accounts_count  integer not null default 0,
    movements_count integer not null default 0,
    size_bytes      integer not null default 0,
    -- the file must live in the owner's own folder
    constraint backups_object_path_owner check (split_part(object_path, '/', 1) = user_id::text)
);

create index if not exists backups_user_created_idx on public.backups (user_id, created_at desc);

alter table public.backups enable row level security;

drop policy if exists "backups: owner can read" on public.backups;
create policy "backups: owner can read" on public.backups
    for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "backups: owner can insert" on public.backups;
create policy "backups: owner can insert" on public.backups
    for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists "backups: owner can delete" on public.backups;
create policy "backups: owner can delete" on public.backups
    for delete to authenticated using (user_id = (select auth.uid()));
-- no UPDATE policy: backups are append-only.

-- 2. Private storage bucket for the backup files (no public URLs)
insert into storage.buckets (id, name, public)
values ('backups', 'backups', false)
on conflict (id) do update set public = false;

drop policy if exists "backup files: owner can read" on storage.objects;
create policy "backup files: owner can read" on storage.objects
    for select to authenticated
    using (bucket_id = 'backups' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "backup files: owner can upload" on storage.objects;
create policy "backup files: owner can upload" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'backups' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "backup files: owner can delete" on storage.objects;
create policy "backup files: owner can delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'backups' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- no UPDATE policy: files are never overwritten.


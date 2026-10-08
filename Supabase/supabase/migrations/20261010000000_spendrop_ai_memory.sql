-- SpenDrop AI personal memory (additive). A user's OWN rules for how SpenDrop AI reads their data, e.g.
-- "Grab is Transport for me". Nothing existing is changed.
--
-- Rules (see Docs/AI-Architecture.md → Personal memory):
--   * Strictly per user: owner-only RLS for select/insert/update/delete; anon gets nothing. One user's rule can
--     never affect another user (there is no global rule table and no service-role path).
--   * Memory is not financial data: a rule changes how answers group spending, never the stored transactions.
--   * Only explicit statements are stored (source = 'explicit'); the user can list and delete them at any time,
--     and deleting the account deletes them (cascade).
--   * Never used to train any model.

create table if not exists public.ai_memories (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    kind        text not null default 'merchant_category' check (kind in ('merchant_category')),
    -- normalised merchant name ("grab"), as the app matches it; `label` keeps the user's spelling ("Grab")
    subject     text not null check (char_length(subject) between 1 and 80 and subject = lower(subject)),
    label       text not null check (char_length(label) between 1 and 80),
    value       text not null check (value in ('Food', 'Groceries', 'Transport', 'Shopping', 'Bills', 'Entertainment',
                                               'Education', 'Health', 'Travel', 'Personal', 'Subscription', 'Other')),
    source      text not null default 'explicit' check (source in ('explicit')),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    unique (user_id, kind, subject)
);

alter table public.ai_memories enable row level security;
revoke all on table public.ai_memories from anon, authenticated;
grant select, insert, update, delete on table public.ai_memories to authenticated;

drop policy if exists "ai_memories: owner can read" on public.ai_memories;
create policy "ai_memories: owner can read" on public.ai_memories
    for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "ai_memories: owner can insert" on public.ai_memories;
create policy "ai_memories: owner can insert" on public.ai_memories
    for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "ai_memories: owner can update" on public.ai_memories;
create policy "ai_memories: owner can update" on public.ai_memories
    for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "ai_memories: owner can delete" on public.ai_memories;
create policy "ai_memories: owner can delete" on public.ai_memories
    for delete to authenticated using (user_id = (select auth.uid()));

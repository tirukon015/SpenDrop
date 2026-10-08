-- SpenDrop AI (additive). Conversation history for "Ask SpenDrop". Nothing existing is changed.
--
-- Rules (see Docs/AI-Architecture.md):
--   * Every row belongs to one user (user_id, default auth.uid()); RLS: a signed-in user can only read, add and
--     delete their own rows. anon gets nothing. There is no service-role path: the AI route uses the user's JWT.
--   * A message can only point at a conversation of the SAME user (composite foreign key (id, user_id)), so a
--     forged conversation_id from another user is rejected by the database itself.
--   * Messages are append-only (no UPDATE). Users can delete their conversations (messages cascade); deleting the
--     account deletes everything (cascade from auth.users).
--   * No financial record is stored here except what an answer showed the user (its text and evidence blocks).
--     The AI never trains on this data.

create table if not exists public.ai_conversations (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
    title       text not null default 'New conversation' check (char_length(title) between 1 and 120),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    unique (id, user_id)
);

create table if not exists public.ai_messages (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
    conversation_id  uuid not null,
    role             text not null check (role in ('user', 'assistant')),
    content          text not null check (char_length(content) between 1 and 8000),
    -- assistant answers: status, evidence blocks, follow-ups, conversation focus and safe diagnostics (no secrets)
    metadata         jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object' and pg_column_size(metadata) <= 131072),
    created_at       timestamptz not null default now(),
    foreign key (conversation_id, user_id) references public.ai_conversations (id, user_id) on delete cascade
);

create index if not exists ai_conversations_user_updated_idx on public.ai_conversations (user_id, updated_at desc);
create index if not exists ai_messages_conversation_idx     on public.ai_messages (conversation_id, created_at);
-- rate limiting counts a user's recent questions
create index if not exists ai_messages_user_questions_idx   on public.ai_messages (user_id, created_at desc) where role = 'user';

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;

revoke all on table public.ai_conversations from anon, authenticated;
revoke all on table public.ai_messages from anon, authenticated;
grant select, insert, update, delete on table public.ai_conversations to authenticated;
grant select, insert, delete on table public.ai_messages to authenticated;

drop policy if exists "ai_conversations: owner can read" on public.ai_conversations;
create policy "ai_conversations: owner can read" on public.ai_conversations
    for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "ai_conversations: owner can insert" on public.ai_conversations;
create policy "ai_conversations: owner can insert" on public.ai_conversations
    for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "ai_conversations: owner can update" on public.ai_conversations;
create policy "ai_conversations: owner can update" on public.ai_conversations
    for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists "ai_conversations: owner can delete" on public.ai_conversations;
create policy "ai_conversations: owner can delete" on public.ai_conversations
    for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists "ai_messages: owner can read" on public.ai_messages;
create policy "ai_messages: owner can read" on public.ai_messages
    for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "ai_messages: owner can insert" on public.ai_messages;
create policy "ai_messages: owner can insert" on public.ai_messages
    for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "ai_messages: owner can delete" on public.ai_messages;
create policy "ai_messages: owner can delete" on public.ai_messages
    for delete to authenticated using (user_id = (select auth.uid()));

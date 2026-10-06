-- SpenDrop cloud records (additive). Live, per-record copies of the user's financial data so the Web App
-- (and later iOS sync / Android) can read and write the same data set. Nothing existing is changed or dropped:
-- the `backups` table, the `backups` bucket and `delete_my_account()` from 20260929000000 stay as they are.
--
-- Rules (see Docs/Sync-Architecture.md):
--   * Every record keeps the stable UUID it was created with (on iOS or Web) -> no duplicates when syncing.
--   * Money is stored in integer minor units (sen): amount_minor bigint. Never floating point.
--   * Nothing is hard-deleted by clients: deleting sets deleted_at (a tombstone) so other devices learn about it.
--     Rows disappear for real only when the user deletes their account (cascade from auth.users).
--   * updated_at is the CLIENT's edit time (last-writer-wins); server_updated_at is set by the server on every
--     write and is the pull cursor ("give me everything changed since X").
--   * Every table has RLS: a signed-in user can read/insert/update ONLY their own rows. anon gets nothing.
--     Composite foreign keys (id, user_id) make it impossible to link to another user's records.

-- ---------------------------------------------------------------------------------------------------------
-- 0. Helper: server_updated_at maintained by the server, never trusted from the client
-- ---------------------------------------------------------------------------------------------------------
create or replace function public.spendrop_touch_server_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    new.server_updated_at := now();
    return new;
end;
$$;

revoke all on function public.spendrop_touch_server_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------
-- 1. Funding accounts (Maybank, CIMB, Touch 'n Go, Cash…). NOT payment channels, NOT the login account.
-- ---------------------------------------------------------------------------------------------------------
create table if not exists public.accounts (
    id                uuid primary key,
    user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name              text not null check (length(btrim(name)) between 1 and 80),
    type              text not null default 'bank' check (type in ('bank', 'eWallet', 'cash', 'other')),
    currency          text not null default 'RM' check (length(currency) between 1 and 8),
    icon              text,
    is_archived       boolean not null default false,
    sort_index        integer not null default 0,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    unique (id, user_id)
);

-- ---------------------------------------------------------------------------------------------------------
-- 2. PayBook people (the iOS PayBookProfile). Photos are not synced (see Docs/Sync-Architecture.md).
-- ---------------------------------------------------------------------------------------------------------
create table if not exists public.people (
    id                uuid primary key,
    user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name              text not null check (length(btrim(name)) between 1 and 80),
    notes             text check (notes is null or length(notes) <= 2000),
    is_frequent       boolean not null default false,
    is_archived       boolean not null default false,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    unique (id, user_id)
);

create table if not exists public.person_payment_methods (
    id                   uuid primary key,
    user_id              uuid not null default auth.uid() references auth.users (id) on delete cascade,
    person_id            uuid not null,
    payment_type         text not null default 'Bank Account'
                         check (payment_type in ('Bank Account', 'E-Wallet', 'Payment ID', 'Other')),
    provider             text not null default '',
    custom_provider_name text,
    account_identifier   text not null default '' check (length(account_identifier) <= 120),
    label                text,
    notes                text,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    deleted_at           timestamptz,
    server_updated_at    timestamptz not null default now(),
    foreign key (person_id, user_id) references public.people (id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------------------------------------------
-- 3. Expenses. funding_account = where the money came from (text snapshot, like iOS) + optional account link.
--    payment_channel = how it was paid. 'UNKNOWN' is a valid, explicit value.
-- ---------------------------------------------------------------------------------------------------------
create table if not exists public.expenses (
    id                    uuid primary key,
    user_id               uuid not null default auth.uid() references auth.users (id) on delete cascade,
    amount_minor          bigint not null check (amount_minor > 0 and amount_minor <= 100000000000),
    currency              text not null default 'RM' check (length(currency) between 1 and 8),
    merchant              text not null default 'Unknown' check (length(merchant) <= 200),
    category              text not null default 'Other'
                          check (category in ('Food', 'Groceries', 'Transport', 'Shopping', 'Bills', 'Entertainment',
                                              'Education', 'Health', 'Travel', 'Personal', 'Subscription', 'Other')),
    payment_channel       text not null default 'UNKNOWN'
                          check (payment_channel in ('APPLE_PAY', 'QR_PAYMENT', 'BANK_TRANSFER', 'CARD', 'CASH',
                                                     'DUITNOW_QR', 'TNG_QR', 'ONLINE_BANKING', 'E_WALLET', 'OTHER',
                                                     'UNKNOWN')),
    funding_account       text not null default 'Unknown' check (length(funding_account) <= 80),
    funding_instrument    text,
    account_id            uuid,
    payment_source        text,
    date                  timestamptz not null,
    notes                 text check (notes is null or length(notes) <= 4000),
    transaction_reference text check (transaction_reference is null or length(transaction_reference) <= 120),
    source_type           text not null default 'manual',
    paid_by_me            boolean not null default true,
    payer_id              uuid,
    payer_name_snapshot   text,
    split_method          text check (split_method is null or split_method in ('equal', 'parts', 'amounts')),
    receipt_path          text,
    is_sample_data        boolean not null default false,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    deleted_at            timestamptz,
    server_updated_at     timestamptz not null default now(),
    unique (id, user_id),
    foreign key (account_id, user_id) references public.accounts (id, user_id) on delete set null (account_id),
    foreign key (payer_id, user_id) references public.people (id, user_id) on delete set null (payer_id),
    -- someone else paid -> a payer is named; I paid -> no payer
    constraint expenses_payer_consistent check (paid_by_me or payer_id is not null or payer_name_snapshot is not null),
    -- receipts live in the owner's own folder of the private `receipts` bucket
    constraint expenses_receipt_owner check (receipt_path is null or split_part(receipt_path, '/', 1) = user_id::text)
);

-- Split shares: one row per participant (incl. "Me"). The amounts of a split add up to the expense amount
-- (enforced by the clients, which use the shared rules in Common/BusinessRules).
create table if not exists public.expense_shares (
    id                uuid primary key,
    user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    expense_id        uuid not null,
    person_id         uuid,
    is_me             boolean not null default false,
    name_snapshot     text not null default '',
    amount_minor      bigint not null check (amount_minor >= 0),
    parts             integer check (parts is null or parts between 1 and 99),
    entered_minor     bigint check (entered_minor is null or entered_minor >= 0),
    sort_index        integer not null default 0,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    foreign key (expense_id, user_id) references public.expenses (id, user_id) on delete cascade,
    foreign key (person_id, user_id) references public.people (id, user_id) on delete set null (person_id),
    constraint expense_shares_me_has_no_person check (not is_me or person_id is null)
);

-- ---------------------------------------------------------------------------------------------------------
-- 4. Money movements (income, refunds, loans, repayments, own transfers)
-- ---------------------------------------------------------------------------------------------------------
create table if not exists public.money_movements (
    id                      uuid primary key,
    user_id                 uuid not null default auth.uid() references auth.users (id) on delete cascade,
    kind                    text not null check (kind in ('income', 'loanReceived', 'repaymentReceived', 'refund', 'otherIn',
                                                          'loanGiven', 'repaymentMade', 'otherOut', 'ownTransfer')),
    direction               text not null check (direction in ('in', 'out', 'internal')),
    amount_minor            bigint not null check (amount_minor > 0 and amount_minor <= 100000000000),
    currency                text not null default 'RM' check (length(currency) between 1 and 8),
    date                    timestamptz not null,
    person_id               uuid,
    person_name_snapshot    text,
    linked_expense_id       uuid,
    linked_expense_snapshot text,
    account_id              uuid,
    counter_account_id      uuid,
    note                    text check (note is null or length(note) <= 4000),
    transaction_reference   text,
    source_type             text not null default 'manual',
    payment_channel         text not null default 'UNKNOWN',
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz,
    server_updated_at       timestamptz not null default now(),
    unique (id, user_id),
    foreign key (person_id, user_id) references public.people (id, user_id) on delete set null (person_id),
    foreign key (linked_expense_id, user_id) references public.expenses (id, user_id) on delete set null (linked_expense_id),
    foreign key (account_id, user_id) references public.accounts (id, user_id) on delete set null (account_id),
    foreign key (counter_account_id, user_id) references public.accounts (id, user_id) on delete set null (counter_account_id),
    constraint money_movements_direction_matches_kind check (
        (kind in ('income', 'loanReceived', 'repaymentReceived', 'refund', 'otherIn') and direction = 'in') or
        (kind in ('loanGiven', 'repaymentMade', 'otherOut') and direction = 'out') or
        (kind = 'ownTransfer' and direction = 'internal'))
);

-- Which payment settled which debt (iOS SettlementAllocation). Append-mostly; undo = tombstone.
create table if not exists public.settlement_allocations (
    id                uuid primary key,
    user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    group_id          uuid not null,
    kind              text not null default 'payment' check (kind in ('payment', 'assign', 'offset')),
    payment_id        uuid,
    expense_id        uuid,
    loan_id           uuid,
    person_id         uuid not null,
    direction         smallint not null check (direction in (-1, 1)),
    amount_minor      bigint not null check (amount_minor > 0),
    currency          text not null default 'RM',
    date              timestamptz not null,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    foreign key (person_id, user_id) references public.people (id, user_id) on delete cascade,
    foreign key (payment_id, user_id) references public.money_movements (id, user_id) on delete set null (payment_id),
    foreign key (expense_id, user_id) references public.expenses (id, user_id) on delete set null (expense_id),
    foreign key (loan_id, user_id) references public.money_movements (id, user_id) on delete set null (loan_id)
);

-- ---------------------------------------------------------------------------------------------------------
-- 5. Learned classification (user corrections). Keys are normalised merchant names, never transaction data.
-- ---------------------------------------------------------------------------------------------------------
create table if not exists public.classification_rules (
    id                 uuid primary key,
    user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
    merchant_key       text not null,
    category           text,
    suggested_type     text,
    account_id         uuid,
    hit_count          integer not null default 1 check (hit_count >= 0),
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    deleted_at         timestamptz,
    server_updated_at  timestamptz not null default now(),
    unique (user_id, merchant_key)
);

create table if not exists public.channel_rules (
    id                uuid primary key,
    user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
    merchant_key      text not null,
    funding_key       text not null default '',
    channel           text not null,
    hit_count         integer not null default 1 check (hit_count >= 0),
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz,
    server_updated_at timestamptz not null default now(),
    unique (user_id, merchant_key, funding_key)
);

-- ---------------------------------------------------------------------------------------------------------
-- 6. Indexes (per-user reads, date-ordered lists, sync cursors, foreign keys)
-- ---------------------------------------------------------------------------------------------------------
create index if not exists expenses_user_date_idx            on public.expenses (user_id, date desc) where deleted_at is null;
create index if not exists expenses_user_sync_idx            on public.expenses (user_id, server_updated_at);
create index if not exists expenses_account_idx              on public.expenses (account_id) where account_id is not null;
create index if not exists expenses_payer_idx                on public.expenses (payer_id) where payer_id is not null;
create index if not exists expense_shares_expense_idx        on public.expense_shares (expense_id);
create index if not exists expense_shares_person_idx         on public.expense_shares (person_id) where person_id is not null;
create index if not exists expense_shares_user_sync_idx      on public.expense_shares (user_id, server_updated_at);
create index if not exists money_movements_user_date_idx     on public.money_movements (user_id, date desc) where deleted_at is null;
create index if not exists money_movements_user_sync_idx     on public.money_movements (user_id, server_updated_at);
create index if not exists money_movements_person_idx        on public.money_movements (person_id) where person_id is not null;
create index if not exists money_movements_account_idx       on public.money_movements (account_id) where account_id is not null;
create index if not exists money_movements_counter_idx       on public.money_movements (counter_account_id) where counter_account_id is not null;
create index if not exists money_movements_linked_idx        on public.money_movements (linked_expense_id) where linked_expense_id is not null;
create index if not exists accounts_user_sync_idx            on public.accounts (user_id, server_updated_at);
create index if not exists people_user_sync_idx              on public.people (user_id, server_updated_at);
create index if not exists person_payment_methods_person_idx on public.person_payment_methods (person_id);
create index if not exists person_payment_methods_sync_idx   on public.person_payment_methods (user_id, server_updated_at);
create index if not exists settlement_allocations_person_idx on public.settlement_allocations (person_id);
create index if not exists settlement_allocations_sync_idx   on public.settlement_allocations (user_id, server_updated_at);
create index if not exists settlement_allocations_payment_idx on public.settlement_allocations (payment_id) where payment_id is not null;
create index if not exists settlement_allocations_expense_idx on public.settlement_allocations (expense_id) where expense_id is not null;
create index if not exists settlement_allocations_loan_idx   on public.settlement_allocations (loan_id) where loan_id is not null;
create index if not exists classification_rules_sync_idx     on public.classification_rules (user_id, server_updated_at);
create index if not exists channel_rules_sync_idx            on public.channel_rules (user_id, server_updated_at);

-- ---------------------------------------------------------------------------------------------------------
-- 7. Triggers, RLS, grants (same pattern for every table)
-- ---------------------------------------------------------------------------------------------------------
do $$
declare
    t text;
begin
    foreach t in array array['accounts', 'people', 'person_payment_methods', 'expenses', 'expense_shares',
                             'money_movements', 'settlement_allocations', 'classification_rules', 'channel_rules']
    loop
        execute format('drop trigger if exists %I on public.%I', t || '_server_updated_at', t);
        execute format('create trigger %I before insert or update on public.%I
                        for each row execute function public.spendrop_touch_server_updated_at()',
                       t || '_server_updated_at', t);

        execute format('alter table public.%I enable row level security', t);

        -- Explicit Data API access (new tables are not exposed automatically since 2026-10-30).
        -- No DELETE for clients: deleting = setting deleted_at. anon gets nothing.
        execute format('revoke all on table public.%I from anon, authenticated', t);
        execute format('grant select, insert, update on table public.%I to authenticated', t);

        execute format('drop policy if exists %I on public.%I', t || ': owner can read', t);
        execute format('create policy %I on public.%I for select to authenticated
                        using (user_id = (select auth.uid()))', t || ': owner can read', t);

        execute format('drop policy if exists %I on public.%I', t || ': owner can insert', t);
        execute format('create policy %I on public.%I for insert to authenticated
                        with check (user_id = (select auth.uid()))', t || ': owner can insert', t);

        execute format('drop policy if exists %I on public.%I', t || ': owner can update', t);
        execute format('create policy %I on public.%I for update to authenticated
                        using (user_id = (select auth.uid()))
                        with check (user_id = (select auth.uid()))', t || ': owner can update', t);
    end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------------------
-- 8. Private receipts bucket (Web uploads compressed images; owner-only, no public URLs)
-- ---------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 3145728, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do update
    set public = false, file_size_limit = 3145728, allowed_mime_types = array['image/webp', 'image/jpeg', 'image/png'];

drop policy if exists "receipt files: owner can read" on storage.objects;
create policy "receipt files: owner can read" on storage.objects
    for select to authenticated
    using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "receipt files: owner can upload" on storage.objects;
create policy "receipt files: owner can upload" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "receipt files: owner can delete" on storage.objects;
create policy "receipt files: owner can delete" on storage.objects
    for delete to authenticated
    using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- no UPDATE policy: a receipt file is never overwritten (a new one gets a new name).

-- ---------------------------------------------------------------------------------------------------------
-- 9. Atomic saves (run as the caller: RLS still applies; SECURITY INVOKER, nothing privileged)
--    An expense and its split shares are saved together or not at all. Last-writer-wins on updated_at:
--    a write older than what the server has is ignored (never overwrites newer data).
-- ---------------------------------------------------------------------------------------------------------
create or replace function public.save_expense_with_shares(p_expense jsonb, p_shares jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_id uuid := (p_expense->>'id')::uuid;
    v_updated timestamptz := coalesce((p_expense->>'updated_at')::timestamptz, now());
    v_existing timestamptz;
begin
    if v_user is null then
        raise exception 'not signed in';
    end if;
    select updated_at into v_existing from public.expenses where id = v_id;
    if v_existing is not null and v_existing > v_updated then
        return; -- a newer version already exists
    end if;

    insert into public.expenses (id, user_id, amount_minor, currency, merchant, category, payment_channel, funding_account,
        funding_instrument, account_id, payment_source, date, notes, transaction_reference, source_type, paid_by_me, payer_id,
        payer_name_snapshot, split_method, receipt_path, is_sample_data, created_at, updated_at, deleted_at)
    values (v_id, v_user, (p_expense->>'amount_minor')::bigint, coalesce(p_expense->>'currency', 'RM'),
        coalesce(p_expense->>'merchant', 'Unknown'), coalesce(p_expense->>'category', 'Other'),
        coalesce(p_expense->>'payment_channel', 'UNKNOWN'), coalesce(p_expense->>'funding_account', 'Unknown'),
        p_expense->>'funding_instrument', (p_expense->>'account_id')::uuid, p_expense->>'payment_source',
        (p_expense->>'date')::timestamptz, p_expense->>'notes', p_expense->>'transaction_reference',
        coalesce(p_expense->>'source_type', 'manual'), coalesce((p_expense->>'paid_by_me')::boolean, true),
        (p_expense->>'payer_id')::uuid, p_expense->>'payer_name_snapshot', p_expense->>'split_method', p_expense->>'receipt_path',
        coalesce((p_expense->>'is_sample_data')::boolean, false), coalesce((p_expense->>'created_at')::timestamptz, now()),
        v_updated, (p_expense->>'deleted_at')::timestamptz)
    on conflict (id) do update set
        amount_minor = excluded.amount_minor, currency = excluded.currency, merchant = excluded.merchant,
        category = excluded.category, payment_channel = excluded.payment_channel, funding_account = excluded.funding_account,
        funding_instrument = excluded.funding_instrument, account_id = excluded.account_id,
        payment_source = excluded.payment_source, date = excluded.date, notes = excluded.notes,
        transaction_reference = excluded.transaction_reference, source_type = excluded.source_type,
        paid_by_me = excluded.paid_by_me, payer_id = excluded.payer_id, payer_name_snapshot = excluded.payer_name_snapshot,
        split_method = excluded.split_method, receipt_path = excluded.receipt_path, is_sample_data = excluded.is_sample_data,
        updated_at = excluded.updated_at, deleted_at = excluded.deleted_at;

    -- Replace the split: shares not in the new list are tombstoned, listed ones are upserted.
    update public.expense_shares
       set deleted_at = v_updated, updated_at = v_updated
     where expense_id = v_id and deleted_at is null
       and id not in (select (s->>'id')::uuid from jsonb_array_elements(coalesce(p_shares, '[]'::jsonb)) s);

    insert into public.expense_shares (id, user_id, expense_id, person_id, is_me, name_snapshot, amount_minor, parts,
        entered_minor, sort_index, created_at, updated_at, deleted_at)
    select (s->>'id')::uuid, v_user, v_id, (s->>'person_id')::uuid, coalesce((s->>'is_me')::boolean, false),
        coalesce(s->>'name_snapshot', ''), (s->>'amount_minor')::bigint, (s->>'parts')::integer,
        (s->>'entered_minor')::bigint, coalesce((s->>'sort_index')::integer, 0),
        coalesce((s->>'created_at')::timestamptz, now()), v_updated, null
    from jsonb_array_elements(coalesce(p_shares, '[]'::jsonb)) s
    on conflict (id) do update set
        person_id = excluded.person_id, is_me = excluded.is_me, name_snapshot = excluded.name_snapshot,
        amount_minor = excluded.amount_minor, parts = excluded.parts, entered_minor = excluded.entered_minor,
        sort_index = excluded.sort_index, updated_at = excluded.updated_at, deleted_at = null;

    -- The split must add up exactly to the amount (or the expense is not shared at all).
    if exists (select 1 from public.expense_shares where expense_id = v_id and deleted_at is null)
       and (select sum(amount_minor) from public.expense_shares where expense_id = v_id and deleted_at is null)
           <> (select amount_minor from public.expenses where id = v_id) then
        raise exception 'split shares must add up to the expense amount';
    end if;
end;
$$;

revoke all on function public.save_expense_with_shares(jsonb, jsonb) from public, anon;
grant execute on function public.save_expense_with_shares(jsonb, jsonb) to authenticated;

-- A settlement (payments + allocations) is recorded as one unit.
create or replace function public.record_settlement(p_payments jsonb, p_allocations jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        raise exception 'not signed in';
    end if;
    insert into public.money_movements (id, user_id, kind, direction, amount_minor, currency, date, person_id,
        person_name_snapshot, account_id, note, source_type, payment_channel, created_at, updated_at)
    select (p->>'id')::uuid, v_user, p->>'kind',
        case when p->>'kind' = 'repaymentReceived' then 'in' else 'out' end,
        (p->>'amount_minor')::bigint, coalesce(p->>'currency', 'RM'), (p->>'date')::timestamptz, (p->>'person_id')::uuid,
        p->>'person_name_snapshot', (p->>'account_id')::uuid, p->>'note', 'manual', 'UNKNOWN', now(), now()
    from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) p
    where p->>'kind' in ('repaymentReceived', 'repaymentMade');

    insert into public.settlement_allocations (id, user_id, group_id, kind, payment_id, expense_id, loan_id, person_id,
        direction, amount_minor, currency, date, created_at, updated_at)
    select (a->>'id')::uuid, v_user, (a->>'group_id')::uuid, a->>'kind', (a->>'payment_id')::uuid, (a->>'expense_id')::uuid,
        (a->>'loan_id')::uuid, (a->>'person_id')::uuid, (a->>'direction')::smallint, (a->>'amount_minor')::bigint,
        coalesce(a->>'currency', 'RM'), (a->>'date')::timestamptz, now(), now()
    from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) a;
end;
$$;

revoke all on function public.record_settlement(jsonb, jsonb) from public, anon;
grant execute on function public.record_settlement(jsonb, jsonb) to authenticated;

-- SpenDrop: Hybrid Split (Common/BusinessRules/split-hybrid.md).
-- Additive only: one nullable text column on expenses holding the Hybrid Split rule (group fixed amounts, individual
-- fixed amounts, who shares the remaining amount) and the save RPC storing it. Shares are unchanged (final amounts),
-- existing rows stay null (a normal split). Safe to run more than once.

alter table public.expenses
    add column if not exists split_rule text check (split_rule is null or char_length(split_rule) <= 4000);

comment on column public.expenses.split_rule is
    'Hybrid Split rule as canonical JSON (see Common/BusinessRules/split-hybrid.md). Null = a normal split.';

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
        payer_name_snapshot, split_method, split_rule, receipt_path, is_sample_data, created_at, updated_at, deleted_at)
    values (v_id, v_user, (p_expense->>'amount_minor')::bigint, coalesce(p_expense->>'currency', 'RM'),
        coalesce(p_expense->>'merchant', 'Unknown'), coalesce(p_expense->>'category', 'Other'),
        coalesce(p_expense->>'payment_channel', 'UNKNOWN'), coalesce(p_expense->>'funding_account', 'Unknown'),
        p_expense->>'funding_instrument', (p_expense->>'account_id')::uuid, p_expense->>'payment_source',
        (p_expense->>'date')::timestamptz, p_expense->>'notes', p_expense->>'transaction_reference',
        coalesce(p_expense->>'source_type', 'manual'), coalesce((p_expense->>'paid_by_me')::boolean, true),
        (p_expense->>'payer_id')::uuid, p_expense->>'payer_name_snapshot', p_expense->>'split_method', p_expense->>'split_rule',
        p_expense->>'receipt_path',
        coalesce((p_expense->>'is_sample_data')::boolean, false), coalesce((p_expense->>'created_at')::timestamptz, now()),
        v_updated, (p_expense->>'deleted_at')::timestamptz)
    on conflict (id) do update set
        amount_minor = excluded.amount_minor, currency = excluded.currency, merchant = excluded.merchant,
        category = excluded.category, payment_channel = excluded.payment_channel, funding_account = excluded.funding_account,
        funding_instrument = excluded.funding_instrument, account_id = excluded.account_id,
        payment_source = excluded.payment_source, date = excluded.date, notes = excluded.notes,
        transaction_reference = excluded.transaction_reference, source_type = excluded.source_type,
        paid_by_me = excluded.paid_by_me, payer_id = excluded.payer_id, payer_name_snapshot = excluded.payer_name_snapshot,
        split_method = excluded.split_method, split_rule = excluded.split_rule, receipt_path = excluded.receipt_path, is_sample_data = excluded.is_sample_data,
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

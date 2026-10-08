-- SpenDrop AI: the signed-in user's own vocabulary in one small round trip (additive; nothing existing changes).
--
-- Before: every question downloaded up to 5,000 expense rows to build the list of the user's merchant names.
-- After: Postgres returns only the DISTINCT names (+ funding accounts, currencies, earliest date, count).
--
-- Safety:
--   * SECURITY INVOKER + `where user_id = auth.uid()`: the caller's Row Level Security applies, so a user only ever sees
--     their own names (there is no way to pass another user's id). anon cannot execute it.
--   * Read-only (STABLE, SELECT only). No table, column or row is created, changed or removed.
--   * The index is partial on live rows and only speeds up the distinct-merchant scan.

create index if not exists expenses_user_merchant_idx on public.expenses (user_id, merchant) where deleted_at is null;

create or replace function public.ai_vocabulary()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with mine as (
    select e.merchant, e.funding_account, e.currency, e.date
    from public.expenses e
    where e.user_id = (select auth.uid()) and e.deleted_at is null
  ),
  merchants as (
    -- one spelling per name (case-insensitive), most used first; "Unknown" is not a merchant
    select min(btrim(merchant)) as name, count(*) as n
    from mine
    where btrim(coalesce(merchant, '')) <> '' and lower(btrim(merchant)) <> 'unknown'
    group by lower(btrim(merchant))
    order by count(*) desc, min(btrim(merchant))
    limit 5000
  ),
  funding as (
    select lower(name) as k, min(name) as name from (
      select btrim(funding_account) as name from mine
      union all
      select btrim(a.name) from public.accounts a where a.user_id = (select auth.uid()) and a.deleted_at is null
    ) f
    where coalesce(name, '') <> '' and lower(name) <> 'unknown'
    group by lower(name)
  )
  select jsonb_build_object(
    'merchants', coalesce((select jsonb_agg(name order by n desc, name) from merchants), '[]'::jsonb),
    'fundingAccounts', coalesce((select jsonb_agg(name order by name) from funding), '[]'::jsonb),
    'currencies', coalesce((select jsonb_agg(distinct currency) from mine), '[]'::jsonb),
    'earliestDate', (select min(date) from mine),
    'expenseCount', (select count(*) from mine)
  );
$$;

revoke all on function public.ai_vocabulary() from public, anon;
grant execute on function public.ai_vocabulary() to authenticated;

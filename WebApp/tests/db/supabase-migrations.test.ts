// Runs the real Supabase migrations (Supabase/supabase/migrations/*.sql) on an in-memory Postgres (PGlite) with
// minimal stand-ins for Supabase's `auth` and `storage` schemas, then checks the security and data rules as
// real database roles: owner-only access (RLS), no cross-user links, no client deletes, valid money/enums,
// tombstones and the server sync cursor. Nothing here touches the production project.
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { beforeAll, describe, expect, it } from "vitest";

const MIGRATIONS = path.resolve(__dirname, "../../../Supabase/supabase/migrations");
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

let db: PGlite;

/** Runs `sql` as a signed-in user (role authenticated, auth.uid() = userId) or as anon. */
async function as<T = Record<string, unknown>>(who: string | "anon", sql: string, params: unknown[] = []) {
  return db.transaction(async (tx) => {
    if (who === "anon") {
      await tx.exec("set local role anon");
    } else {
      await tx.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${who}', true);`);
    }
    return (await tx.query<T>(sql, params)).rows;
  });
}

async function fails(who: string | "anon", sql: string, params: unknown[] = []): Promise<string> {
  try {
    await as(who, sql, params);
  } catch (error) {
    return (error as Error).message;
  }
  throw new Error(`expected failure: ${sql}`);
}

beforeAll(async () => {
  db = new PGlite();
  await db.exec(`
    create role anon nologin; create role authenticated nologin;
    grant usage on schema public to anon, authenticated;
    create schema auth; grant usage on schema auth to anon, authenticated;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant execute on function auth.uid() to anon, authenticated;
    create schema storage; grant usage on schema storage to anon, authenticated;
    create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id serial primary key, bucket_id text, name text);
    alter table storage.objects enable row level security;
    create function storage.foldername(name text) returns text[] language sql immutable as
      $$ select string_to_array(name, '/') $$;
    insert into auth.users values ('${A}'), ('${B}');
  `);
  for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql")).sort()) {
    await db.exec(readFileSync(path.join(MIGRATIONS, file), "utf8"));
  }
});

const expense = (id: string, extra = "") =>
  `insert into public.expenses (id, amount_minor, merchant, date${extra ? ", " + extra.split("=")[0] : ""})
   values ('${id}', 1050, 'Tealive', now()${extra ? ", " + extra.split("=")[1] : ""}) returning id`;

describe("cloud records migration", () => {
  it("applies on top of the existing backup migration without changing it", async () => {
    const tables = await db.query<{ table_name: string }>(
      "select table_name from information_schema.tables where table_schema = 'public' order by 1");
    expect(tables.rows.map((r) => r.table_name)).toEqual([
      "accounts", "ai_conversations", "ai_memories", "ai_messages", "backups", "channel_rules", "classification_rules", "expense_shares", "expenses",
      "money_movements", "people", "person_payment_methods", "settlement_allocations",
    ]);
    const buckets = await db.query<{ id: string; public: boolean }>("select id, public from storage.buckets order by id");
    expect(buckets.rows).toEqual([{ id: "backups", public: false }, { id: "receipts", public: false }]);
  });

  it("is safe to run twice (idempotent)", async () => {
    const file = readdirSync(MIGRATIONS).filter((f) => f.includes("cloud_records"))[0];
    await db.exec(readFileSync(path.join(MIGRATIONS, file), "utf8"));
  });

  it("owner can create and read; user_id defaults to the signed-in user", async () => {
    const id = "a0000000-0000-4000-8000-000000000001";
    await as(A, expense(id));
    const rows = await as<{ user_id: string; amount_minor: string }>(A, "select user_id, amount_minor from public.expenses where id = $1", [id]);
    expect(rows).toEqual([{ user_id: A, amount_minor: 1050 }]);
  });

  it("another user sees nothing and cannot update it (RLS)", async () => {
    expect(await as(B, "select * from public.expenses")).toEqual([]);
    const updated = await as(B, "update public.expenses set merchant = 'hacked' returning id");
    expect(updated).toEqual([]);
    const stillOwn = await as<{ merchant: string }>(A, "select merchant from public.expenses");
    expect(stillOwn.map((r) => r.merchant)).toEqual(["Tealive"]);
  });

  it("cannot insert rows for someone else", async () => {
    const message = await fails(B, `insert into public.expenses (id, user_id, amount_minor, date)
                                    values ('b0000000-0000-4000-8000-000000000001', '${A}', 100, now())`);
    expect(message).toMatch(/row-level security/);
  });

  it("cannot link to another user's account or person (composite foreign keys)", async () => {
    await as(A, "insert into public.accounts (id, name) values ('a0000000-0000-4000-8000-0000000000a1', 'Maybank')");
    await as(A, "insert into public.people (id, name) values ('a0000000-0000-4000-8000-0000000000b1', 'Bijoy')");
    const account = await fails(B, `insert into public.expenses (id, amount_minor, date, account_id)
      values ('b0000000-0000-4000-8000-000000000002', 100, now(), 'a0000000-0000-4000-8000-0000000000a1')`);
    expect(account).toMatch(/foreign key/);
    const share = await fails(B, `with e as (insert into public.expenses (id, amount_minor, date)
        values ('b0000000-0000-4000-8000-000000000003', 100, now()) returning id)
      insert into public.expense_shares (id, expense_id, person_id, amount_minor)
      select 'b0000000-0000-4000-8000-0000000000c1', id, 'a0000000-0000-4000-8000-0000000000b1', 100 from e`);
    expect(share).toMatch(/foreign key/);
  });

  it("anon has no access at all", async () => {
    expect(await fails("anon", "select * from public.expenses")).toMatch(/permission denied/);
    expect(await fails("anon", "select * from public.backups")).toMatch(/permission denied/);
  });

  it("clients cannot hard-delete; deleting is a tombstone (deleted_at)", async () => {
    expect(await fails(A, "delete from public.expenses")).toMatch(/permission denied/);
    const rows = await as<{ deleted_at: string | null }>(A,
      "update public.expenses set deleted_at = now(), updated_at = now() where id = 'a0000000-0000-4000-8000-000000000001' returning deleted_at");
    expect(rows[0].deleted_at).not.toBeNull();
  });

  it("enforces money and enum rules", async () => {
    expect(await fails(A, `insert into public.expenses (id, amount_minor, date) values ('a0000000-0000-4000-8000-000000000009', 0, now())`)).toMatch(/check/);
    expect(await fails(A, `insert into public.expenses (id, amount_minor, date, payment_channel)
      values ('a0000000-0000-4000-8000-00000000000a', 100, now(), 'Maybank')`)).toMatch(/check/);
    expect(await fails(A, `insert into public.money_movements (id, kind, direction, amount_minor, date)
      values ('a0000000-0000-4000-8000-00000000000b', 'income', 'out', 100, now())`)).toMatch(/direction_matches_kind/);
    expect(await fails(A, `insert into public.expenses (id, amount_minor, date, paid_by_me)
      values ('a0000000-0000-4000-8000-00000000000c', 100, now(), false)`)).toMatch(/payer_consistent/);
    // Unknown is an explicit, valid channel and the default.
    const unknown = await as<{ payment_channel: string }>(A, `insert into public.expenses (id, amount_minor, date)
      values ('a0000000-0000-4000-8000-00000000000d', 100, now()) returning payment_channel`);
    expect(unknown[0].payment_channel).toBe("UNKNOWN");
  });

  it("server_updated_at is set by the server, not the client", async () => {
    const rows = await as<{ server_updated_at: Date }>(A, `insert into public.accounts (id, name, server_updated_at)
      values ('a0000000-0000-4000-8000-0000000000a2', 'CIMB', '2000-01-01') returning server_updated_at`);
    expect(new Date(rows[0].server_updated_at).getUTCFullYear()).toBeGreaterThan(2000);
  });

  it("receipts must be stored in the owner's folder", async () => {
    expect(await fails(A, `insert into public.expenses (id, amount_minor, date, receipt_path)
      values ('a0000000-0000-4000-8000-00000000000e', 100, now(), '${B}/x.webp')`)).toMatch(/receipt_owner/);
  });

  it("save_expense_with_shares saves an expense and its split atomically", async () => {
    const e = { id: "a0000000-0000-4000-8000-0000000000e1", amount_minor: 10000, merchant: "Dinner", date: "2026-10-06T12:00:00Z",
      updated_at: "2026-10-06T12:00:00Z", split_method: "amounts" };
    const shares = [
      { id: "a0000000-0000-4000-8000-0000000000f1", is_me: true, name_snapshot: "Me", amount_minor: 7000, sort_index: 0 },
      { id: "a0000000-0000-4000-8000-0000000000f2", person_id: "a0000000-0000-4000-8000-0000000000b1", name_snapshot: "Bijoy", amount_minor: 3000, sort_index: 1 },
    ];
    await as(A, "select public.save_expense_with_shares($1::jsonb, $2::jsonb)", [JSON.stringify(e), JSON.stringify(shares)]);
    const rows = await as<{ amount_minor: number }>(A, "select amount_minor from public.expense_shares where expense_id = $1 and deleted_at is null order by sort_index", [e.id]);
    expect(rows.map((r) => Number(r.amount_minor))).toEqual([7000, 3000]);

    // Shares that don't add up are rejected and nothing changes.
    const bad = [{ ...shares[0], amount_minor: 6000 }, shares[1]];
    expect(await fails(A, "select public.save_expense_with_shares($1::jsonb, $2::jsonb)",
      [JSON.stringify({ ...e, updated_at: "2026-10-06T13:00:00Z" }), JSON.stringify(bad)])).toMatch(/add up/);
    const still = await as<{ amount_minor: number }>(A, "select amount_minor from public.expense_shares where id = $1", [shares[0].id]);
    expect(Number(still[0].amount_minor)).toBe(7000);

    // Removing a participant tombstones their share.
    await as(A, "select public.save_expense_with_shares($1::jsonb, $2::jsonb)",
      [JSON.stringify({ ...e, amount_minor: 7000, updated_at: "2026-10-06T14:00:00Z" }), JSON.stringify([shares[0]])]);
    const live = await as<{ id: string }>(A, "select id from public.expense_shares where expense_id = $1 and deleted_at is null", [e.id]);
    expect(live.map((r) => r.id)).toEqual([shares[0].id]);

    // An older write never overwrites newer data (last-writer-wins).
    await as(A, "select public.save_expense_with_shares($1::jsonb, $2::jsonb)",
      [JSON.stringify({ ...e, merchant: "Old", updated_at: "2026-10-01T00:00:00Z" }), JSON.stringify([])]);
    const merchant = await as<{ merchant: string; amount_minor: number }>(A, "select merchant, amount_minor from public.expenses where id = $1", [e.id]);
    expect(merchant[0]).toEqual({ merchant: "Dinner", amount_minor: 7000 });
  });

  it("save_expense_with_shares cannot touch another user's expense", async () => {
    const e = { id: "a0000000-0000-4000-8000-0000000000e1", amount_minor: 1, merchant: "x", date: "2026-10-06T12:00:00Z", updated_at: "2027-01-01T00:00:00Z" };
    expect(await fails(B, "select public.save_expense_with_shares($1::jsonb, '[]'::jsonb)", [JSON.stringify(e)])).toMatch(/row-level security|violates/);
    expect(await fails("anon", "select public.save_expense_with_shares('{}'::jsonb, '[]'::jsonb)")).toMatch(/permission denied/);
  });

  it("record_settlement writes the payment and its allocations together", async () => {
    const payment = { id: "a0000000-0000-4000-8000-0000000000d1", kind: "repaymentReceived", amount_minor: 3000, date: "2026-10-06T15:00:00Z",
      person_id: "a0000000-0000-4000-8000-0000000000b1" };
    const allocation = { id: "a0000000-0000-4000-8000-0000000000d2", group_id: "a0000000-0000-4000-8000-0000000000d3", kind: "payment",
      payment_id: payment.id, expense_id: "a0000000-0000-4000-8000-0000000000e1", person_id: payment.person_id, direction: 1, amount_minor: 3000,
      date: payment.date };
    await as(A, "select public.record_settlement($1::jsonb, $2::jsonb)", [JSON.stringify([payment]), JSON.stringify([allocation])]);
    const m = await as<{ direction: string }>(A, "select direction from public.money_movements where id = $1", [payment.id]);
    expect(m[0].direction).toBe("in");
    const bad = { ...allocation, id: "a0000000-0000-4000-8000-0000000000d4", payment_id: "a0000000-0000-4000-8000-0000000000ff" };
    expect(await fails(A, "select public.record_settlement('[]'::jsonb, $1::jsonb)", [JSON.stringify([bad])])).toMatch(/foreign key/);
  });

  it("deleting the user account removes all of their rows (cascade), and only theirs", async () => {
    await as(B, "insert into public.accounts (id, name) values ('b0000000-0000-4000-8000-0000000000a1', 'RHB')");
    await db.exec(`delete from auth.users where id = '${A}'`);
    const left = await db.query<{ user_id: string }>("select user_id from public.accounts");
    expect(left.rows.map((r) => r.user_id)).toEqual([B]);
    const expenses = await db.query("select 1 from public.expenses where user_id = $1", [A]);
    expect(expenses.rows).toEqual([]);
  });
});

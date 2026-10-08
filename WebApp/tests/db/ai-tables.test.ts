// SpenDrop AI tables (migration 20261009000000_spendrop_ai.sql) on an in-memory Postgres, as real database roles:
// conversations and messages are owner-only (RLS), a message can't be attached to another user's conversation,
// messages are append-only, and the financial tables stay invisible across users for the AI's read queries too.
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { beforeAll, describe, expect, it } from "vitest";

const MIGRATIONS = path.resolve(__dirname, "../../../Supabase/supabase/migrations");
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
let db: PGlite;

async function as<T = Record<string, unknown>>(who: string | "anon", sql: string, params: unknown[] = []) {
  return db.transaction(async (tx) => {
    if (who === "anon") await tx.exec("set local role anon");
    else await tx.exec(`set local role authenticated; select set_config('request.jwt.claim.sub', '${who}', true);`);
    return (await tx.query<T>(sql, params)).rows;
  });
}
async function fails(who: string | "anon", sql: string, params: unknown[] = []) {
  try { await as(who, sql, params); } catch (e) { return (e as Error).message; }
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
    create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(name, '/') $$;
    insert into auth.users values ('${A}'), ('${B}');
  `);
  for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql")).sort()) await db.exec(readFileSync(path.join(MIGRATIONS, file), "utf8"));
});

describe("AI conversation tables", () => {
  let convA = "";
  it("owner creates a conversation and messages; user_id defaults to the signed-in user", async () => {
    [{ id: convA }] = await as<{ id: string }>(A, "insert into public.ai_conversations (title) values ('Weekly summary') returning id");
    await as(A, "insert into public.ai_messages (conversation_id, role, content) values ($1, 'user', 'How much this week?')", [convA]);
    const rows = await as<{ user_id: string }>(A, "select user_id from public.ai_messages where conversation_id = $1", [convA]);
    expect(rows).toEqual([{ user_id: A }]);
  });

  it("another user can't see, change or delete them (RLS)", async () => {
    expect(await as(B, "select * from public.ai_conversations")).toEqual([]);
    expect(await as(B, "select * from public.ai_messages")).toEqual([]);
    expect(await as(B, "update public.ai_conversations set title = 'x' where id = $1 returning id", [convA])).toEqual([]);
    expect(await as(B, "delete from public.ai_conversations where id = $1 returning id", [convA])).toEqual([]);
    expect(await as(A, "select title from public.ai_conversations where id = $1", [convA])).toEqual([{ title: "Weekly summary" }]);
  });

  it("can't post into another user's conversation, even with a forged user_id", async () => {
    expect(await fails(B, "insert into public.ai_messages (conversation_id, role, content) values ($1, 'user', 'hi')", [convA])).toMatch(/foreign key/);
    expect(await fails(B, "insert into public.ai_messages (conversation_id, user_id, role, content) values ($1, $2, 'user', 'hi')", [convA, A])).toMatch(/row-level security/);
    expect(await fails(B, "insert into public.ai_conversations (user_id, title) values ($1, 'x')", [A])).toMatch(/row-level security/);
  });

  it("messages are append-only; anon gets nothing", async () => {
    expect(await fails(A, "update public.ai_messages set content = 'changed'")).toMatch(/permission denied/);
    expect(await fails("anon", "select * from public.ai_conversations")).toMatch(/permission denied/);
    expect(await fails("anon", "select * from public.ai_messages")).toMatch(/permission denied/);
  });

  it("validates role, size and metadata shape", async () => {
    expect(await fails(A, "insert into public.ai_messages (conversation_id, role, content) values ($1, 'system', 'x')", [convA])).toMatch(/check/);
    expect(await fails(A, "insert into public.ai_messages (conversation_id, role, content, metadata) values ($1, 'user', 'x', '[]')", [convA])).toMatch(/check/);
  });

  it("the AI's financial reads are owner-only too: A's RM15 Starbucks and B's RM15 McDonald's never mix", async () => {
    await as(A, "insert into public.expenses (id, amount_minor, merchant, date) values (gen_random_uuid(), 1500, 'Starbucks', now())");
    await as(B, "insert into public.expenses (id, amount_minor, merchant, date) values (gen_random_uuid(), 1500, 'McDonald''s', now())");
    // Exactly the query shape SupabaseRepository runs (explicit user filter + RLS); also without the filter.
    const q = "select merchant from public.expenses where amount_minor between 1350 and 1650 and deleted_at is null";
    expect(await as(A, q)).toEqual([{ merchant: "Starbucks" }]);
    expect(await as(B, q)).toEqual([{ merchant: "McDonald's" }]);
    expect(await as(A, `${q} and user_id = $1`, [B])).toEqual([]);
  });

  it("personal memory is owner-only: A's “Grab → Transport” is invisible and untouchable for B", async () => {
    await as(A, "insert into public.ai_memories (subject, label, value) values ('grab', 'Grab', 'Transport')");
    await as(B, "insert into public.ai_memories (subject, label, value) values ('grab', 'Grab', 'Food')");
    expect(await as(A, "select value from public.ai_memories where subject = 'grab'")).toEqual([{ value: "Transport" }]);
    expect(await as(B, "select value from public.ai_memories where subject = 'grab'")).toEqual([{ value: "Food" }]);
    expect(await as(B, "update public.ai_memories set value = 'Food' where user_id = $1 returning id", [A])).toEqual([]);
    expect(await as(B, "delete from public.ai_memories where user_id = $1 returning id", [A])).toEqual([]);
    expect(await fails(B, "insert into public.ai_memories (user_id, subject, label, value) values ($1, 'shopee', 'Shopee', 'Food')", [A])).toMatch(/row-level security/);
    expect(await fails("anon", "select * from public.ai_memories")).toMatch(/permission denied/);
  });

  it("personal memory only accepts real categories and one rule per merchant per user", async () => {
    expect(await fails(A, "insert into public.ai_memories (subject, label, value) values ('x', 'X', 'Crypto')")).toMatch(/check/);
    expect(await fails(A, "insert into public.ai_memories (subject, label, value) values ('grab', 'Grab', 'Food')")).toMatch(/unique|duplicate/);
    expect(await fails(A, "insert into public.ai_memories (subject, label, value) values ('Grab', 'Grab', 'Food')")).toMatch(/check/);
  });

  it("deleting a conversation deletes its messages; deleting the account deletes everything", async () => {
    await as(A, "delete from public.ai_conversations where id = $1", [convA]);
    expect(await as(A, "select * from public.ai_messages where conversation_id = $1", [convA])).toEqual([]);
    const [{ id }] = await as<{ id: string }>(B, "insert into public.ai_conversations (title) values ('B') returning id");
    await as(B, "insert into public.ai_messages (conversation_id, role, content) values ($1, 'user', 'x')", [id]);
    await db.query(`delete from auth.users where id = '${B}'`);
    expect((await db.query("select count(*)::int as n from public.ai_messages where user_id = $1", [B])).rows).toEqual([{ n: 0 }]);
  });
});

// Migration 20261011000000: ai_vocabulary() — the caller's own distinct names, under their own RLS.
describe("ai_vocabulary()", () => {
  const C = "33333333-3333-4333-8333-333333333333", D = "44444444-4444-4444-8444-444444444444";
  it("returns only the caller's distinct merchant names (most used first), accounts, currencies and count", async () => {
    await db.query(`insert into auth.users (id) values ('${C}'), ('${D}') on conflict do nothing`);
    for (const [m, n] of [["BIJOYSHARIARALAMIN", 3], ["Starbucks", 1], ["starbucks", 1], ["Unknown", 1]] as const)
      for (let i = 0; i < n; i++) await as(C, "insert into public.expenses (id, amount_minor, merchant, date, funding_account) values (gen_random_uuid(), 100, $1, now(), 'Maybank')", [m]);
    await as(C, "insert into public.expenses (id, amount_minor, merchant, date, deleted_at) values (gen_random_uuid(), 100, 'DELETED SHOP', now(), now())");
    await as(D, "insert into public.expenses (id, amount_minor, merchant, date) values (gen_random_uuid(), 100, 'OTHER USER SECRET', now())");
    const [{ v }] = await as<{ v: { merchants: string[]; fundingAccounts: string[]; currencies: string[]; expenseCount: number } }>(C, "select public.ai_vocabulary() as v");
    expect(v.merchants).toEqual(["BIJOYSHARIARALAMIN", "Starbucks"]);
    expect(v.fundingAccounts).toEqual(["Maybank"]);
    expect(v.expenseCount).toBe(6);
    expect(JSON.stringify(v)).not.toContain("OTHER USER");
    expect(JSON.stringify(v)).not.toContain("DELETED");
    const [{ v: dv }] = await as<{ v: { merchants: string[] } }>(D, "select public.ai_vocabulary() as v");
    expect(dv.merchants).toEqual(["OTHER USER SECRET"]);
  });
  it("anon cannot call it", async () => {
    expect(await fails("anon", "select public.ai_vocabulary()")).toMatch(/permission denied/);
  });
});

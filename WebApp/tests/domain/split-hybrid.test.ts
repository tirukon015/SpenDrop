// @vitest-environment jsdom
// Hybrid Split (Common/BusinessRules/split-hybrid.md): the shared vectors, live editing, the saved rule (canonical JSON
// on the expense), reload incl. the fallback for bad rules, the demo / Supabase data sources and backup import.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { planBackupImport } from "@/lib/data/backup-import";
import { DemoSource } from "@/lib/data/demo-source";
import { rowToRecord } from "@/lib/data/mapping";
import { SupabaseSource } from "@/lib/data/supabase-source";
import { minorToInput } from "@/lib/domain/money";
import * as s from "@/lib/domain/split";
import { emptyDataset, type Expense, type ExpenseShare } from "@/lib/domain/types";

const common = (file: string) => JSON.parse(readFileSync(path.resolve(__dirname, "../../../Common", file), "utf8"));
const idOf = (d: s.SplitDraft, who: string) => d.participants.find((p) => (who === "Me" ? p.isMe : p.name === who))!.id;
const text = (minor: number | null) => (minor == null ? "" : minorToInput(minor));

interface Vector {
  name: string; total: number; people: string[]; payer?: string;
  groups: { amount: number | null; members: string[] }[];
  individuals: { person: string | null; amount: number | null }[];
  remaining: string[];
  expect: { shares?: number[]; groupAllocation?: number; individualAllocation?: number; remaining?: number; problem?: string };
}

/** Builds the draft through the same editor operations the UI uses. */
function build(c: Pick<Vector, "people" | "payer" | "groups" | "individuals" | "remaining">): s.SplitDraft {
  let d = s.newDraft();
  for (const [i, name] of c.people.entries()) d = s.addPerson(d, { id: `person-${i}`, name });
  if (c.payer) d = s.setPayer(d, { id: `person-${c.people.indexOf(c.payer)}`, name: c.payer });
  d = s.setHybrid(d, true); // starts with one empty group (left empty when the case has no groups: it is ignored)
  c.groups.forEach((g, n) => {
    if (n > 0) d = s.addHybridGroup(d);
    const gid = d.hybrid!.groups[n].id;
    d = s.setGroupAmount(d, gid, text(g.amount));
    for (const who of g.members) d = s.setGroupMember(d, gid, idOf(d, who), true);
  });
  c.individuals.forEach((r, n) => {
    d = s.addIndividual(d);
    const rid = d.hybrid!.individuals[n].id;
    if (r.person) d = s.setIndividualPerson(d, rid, idOf(d, r.person));
    d = s.setIndividualAmount(d, rid, text(r.amount));
  });
  for (const p of d.participants) d = s.setInRemainder(d, p.id, c.remaining.includes(p.isMe ? "Me" : p.name));
  return d;
}

describe("Common/BusinessRules/split-hybrid-vectors.json", () => {
  const { cases } = common("BusinessRules/split-hybrid-vectors.json") as { cases: Vector[] };
  it("has all 29 shared cases", () => expect(cases).toHaveLength(29));
  it.each(cases.map((c) => [c.name, c] as const))("%s", (_name, c) => {
    const d = build(c);
    if (c.expect.shares) {
      expect(s.problem(d, c.total)).toBeNull();
      expect(s.shares(d, c.total)).toEqual(c.expect.shares);
      expect(c.expect.shares.reduce((a, b) => a + b, 0)).toBe(c.total);
      const b = s.hybridBreakdown(d, c.total)!;
      expect(b.groupAllocationMinor).toBe(c.expect.groupAllocation);
      expect(b.individualAllocationMinor).toBe(c.expect.individualAllocation);
      expect(b.remainingMinor).toBe(c.expect.remaining);
      // every group adds up exactly to its amount
      b.groupShares.forEach((row, n) => expect(row.reduce((x, y) => x + y, 0)).toBe(c.groups[n] ? c.groups[n].amount ?? 0 : 0));
      expect(s.remainingMinor(d, c.total)).toBe(0);
      expect(s.shareRows(d, c.total)).not.toBeNull();
      expect(s.splitRule(d, c.total)).not.toBeNull();
    }
    if (c.expect.problem) {
      expect(s.problem(d, c.total)).toBe(c.expect.problem);
      expect(s.shares(d, c.total)).toBeNull();
      expect(s.shareRows(d, c.total)).toBeNull(); // a split with a problem is never saved
      expect(s.splitRule(d, c.total)).toBeNull();
    }
  });
});

const example = () => build({
  people: ["Riad", "Bijoy"], groups: [{ amount: 10000, members: ["Riad", "Bijoy"] }], individuals: [{ person: "Bijoy", amount: 2000 }],
  remaining: ["Me", "Riad", "Bijoy"],
});

describe("Hybrid Split: layers", () => {
  const cases: [string, Parameters<typeof build>[0], number, number[] | string][] = [
    ["only a group (covers the total)", { people: ["A", "B"], groups: [{ amount: 10000, members: ["A", "B"] }], individuals: [], remaining: [] }, 10000, [0, 5000, 5000]],
    ["only individuals (cover the total)", { people: ["A", "B"], groups: [], individuals: [{ person: "A", amount: 7000 }, { person: "B", amount: 3000 }], remaining: [] }, 10000, [0, 7000, 3000]],
    ["only remaining is not a Hybrid Split", { people: ["A"], groups: [], individuals: [], remaining: ["Me", "A"] }, 10000, "Add a group fixed amount or an individual fixed amount."],
    ["group of 3+ including Me, uneven", { people: ["A", "B", "C"], groups: [{ amount: 1001, members: ["Me", "A", "B", "C"] }], individuals: [], remaining: ["A"] }, 2001, [251, 1250, 250, 250]],
    ["group + remaining", { people: ["A", "B"], groups: [{ amount: 3000, members: ["A", "B"] }], individuals: [], remaining: ["Me", "A", "B"] }, 9000, [2000, 3500, 3500]],
    ["group + individual + remaining, Me in all three", { people: ["A"], groups: [{ amount: 1000, members: ["Me", "A"] }], individuals: [{ person: "Me", amount: 300 }], remaining: ["Me", "A"] }, 2300, [1300, 1000]],
    ["individual amount box not a number", { people: ["A"], groups: [], individuals: [{ person: "A", amount: null }], remaining: ["Me", "A"] }, 1000, "Enter the individual fixed amount for A."],
  ];
  it.each(cases)("%s", (_n, c, total, expected) => {
    const d = build(c);
    if (typeof expected === "string") expect(s.problem(d, total)).toBe(expected);
    else expect(s.shares(d, total)).toEqual(expected);
  });

  it("a non-numeric amount is reported, not ignored", () => {
    let d = build({ people: ["A"], groups: [], individuals: [], remaining: ["Me", "A"] });
    d = s.setGroupAmount(d, d.hybrid!.groups[0].id, "abc");
    expect(s.problem(d, 1000)).toBe("Enter the amount for group fixed amount 1.");
  });
});

describe("Hybrid Split: editing", () => {
  it("is off by default; other methods are unchanged and save no rule", () => {
    let d = s.addPerson(s.newDraft(), { id: "a", name: "A" });
    expect(s.isHybrid(d)).toBe(false);
    expect(s.hybridBreakdown(d, 10001)).toBeNull();
    expect(s.shares(d, 10001)).toEqual([5001, 5000]);
    expect(s.splitRule(d, 10001)).toBeNull();
    d = s.setMethod(d, "parts", 10001);
    expect(s.savedMethod(d)).toBe("parts");
  });

  it("turning on: one empty group, no individuals, everyone remaining; off returns to the method before", () => {
    let d = s.setMethod(s.addPerson(s.newDraft(), { id: "a", name: "A" }), "parts", 10000);
    d = s.setHybrid(d, true);
    expect(d.hybrid!.groups).toHaveLength(1);
    expect(d.hybrid!.groups[0]).toMatchObject({ amountText: "", memberIds: [] });
    expect(d.hybrid!.individuals).toEqual([]);
    expect(d.hybrid!.remainderIds).toEqual(d.participants.map((p) => p.id));
    expect(s.savedMethod(d)).toBe("amounts");
    const off = s.setHybrid(d, false);
    expect(off.hybrid).toBeNull();
    expect(off.method).toBe("parts");
    expect(s.shares(off, 10000)).toEqual([5000, 5000]);
  });

  it("recalculates live on every change: total, group amount, members, individuals, remaining", () => {
    let d = example();
    expect(s.shares(d, 20000)).toEqual([2667, 7667, 9666]);
    expect(s.shares(d, 30000)).toEqual([6000, 11000, 13000]);
    const g = d.hybrid!.groups[0].id;
    d = s.setGroupAmount(d, g, "120");
    expect(s.shares(d, 20000)).toEqual([2000, 8000, 10000]);
    d = s.setGroupMember(d, g, idOf(d, "Me"), true);
    expect(s.shares(d, 20000)).toEqual([6000, 6000, 8000]);
    d = s.setInRemainder(d, idOf(d, "Me"), false);
    expect(s.shares(d, 20000)).toEqual([4000, 7000, 9000]);
    d = s.setIndividualAmount(d, d.hybrid!.individuals[0].id, "200");
    expect(s.problem(d, 20000)).toBe("Fixed allocations exceed the transaction total by RM 120.00.");
    expect(s.remainingMinor(d, 20000)).toBe(-12000);
  });

  it("adding a person joins the remaining group only; removing deletes them from every layer", () => {
    let d = s.addPerson(example(), { id: "l", name: "Labib" });
    const labib = idOf(d, "Labib");
    expect(d.hybrid!.remainderIds).toContain(labib);
    expect(d.hybrid!.groups[0].memberIds).not.toContain(labib);
    expect(s.shares(d, 20000)).toEqual([2000, 7000, 9000, 2000]);
    const bijoy = idOf(d, "Bijoy");
    d = s.removeParticipant(d, bijoy);
    expect(d.hybrid!.groups[0].memberIds).not.toContain(bijoy);
    expect(d.hybrid!.individuals).toEqual([]);
    expect(d.hybrid!.remainderIds).not.toContain(bijoy);
    expect(s.shares(d, 20000)).toEqual([3334, 13333, 3333]);
  });

  it("several groups and individual rows can be added and removed; empty rows are ignored", () => {
    let d = s.addHybridGroup(example());
    d = s.addIndividual(d);
    expect(s.shares(d, 20000)).toEqual([2667, 7667, 9666]); // empty group 2 + empty individual row ignored
    d = s.setGroupAmount(d, d.hybrid!.groups[1].id, "10");
    expect(s.problem(d, 20000)).toBe("Choose who shares group fixed amount 2.");
    d = s.removeHybridGroup(d, d.hybrid!.groups[1].id);
    d = s.setIndividualAmount(d, d.hybrid!.individuals[1].id, "5");
    expect(s.problem(d, 20000)).toBe("Choose a person for each individual fixed amount.");
    d = s.setIndividualPerson(d, d.hybrid!.individuals[1].id, idOf(d, "Bijoy"));
    expect(s.problem(d, 20000)).toBe("Bijoy already has an individual fixed amount.");
    d = s.removeIndividual(d, d.hybrid!.individuals[1].id);
    expect(s.problem(d, 20000)).toBeNull();
  });

  it('"Paid for someone" turns it off and it cannot be turned on there', () => {
    let d = s.setPurpose(example(), "paidFor");
    expect(d.hybrid).toBeNull();
    expect(s.setHybrid(d, true).hybrid).toBeNull();
    d = s.setPurpose(d, "shared");
    expect(s.isHybrid(d)).toBe(false);
  });
});

// ---- persistence ----

const T = "2026-10-01T12:00:00.000Z";
const expenseFor = (d: s.SplitDraft, amountMinor: number): Expense => {
  const rule = s.splitRule(d, amountMinor);
  return {
    id: "e1", amountMinor, currency: "RM", merchant: "Dinner", category: "Food", paymentChannel: "UNKNOWN", fundingAccount: "Unknown",
    fundingInstrument: null, accountId: null, paymentSource: null, date: T, notes: null, transactionReference: null,
    sourceType: "manual", paidByMe: d.payerId === null, payerId: d.payerId, payerNameSnapshot: d.payerName, splitMethod: s.savedMethod(d),
    receiptPath: null, isSampleData: false, createdAt: T, updatedAt: T, deletedAt: null, ...(rule ? { splitRule: rule } : {}),
  };
};
const sharesFor = (d: s.SplitDraft, total: number) => s.shareRows(d, total)!.map((r, i) => ({ ...r, id: `s${i}`, createdAt: T, updatedAt: T }));
const names = (id: string) => ({ "person-0": "Riad", "person-1": "Bijoy" } as Record<string, string>)[id];
const RULE = '{"type":"hybrid","version":1,"groups":[{"amountMinor":10000,"members":[1,2]}],"individuals":[{"participant":2,"amountMinor":2000}],"remaining":[0,1,2]}';

describe("Hybrid Split: saving and loading", () => {
  it("saves plain custom-amount shares and the canonical rule on the expense", () => {
    const d = example();
    expect(s.savedMethod(d)).toBe("amounts");
    expect(s.splitRule(d, 20000)).toBe(RULE);
    expect(s.shareRows(d, 20000)).toEqual([
      { personId: null, isMe: true, nameSnapshot: "Me", amountMinor: 2667, parts: null, enteredMinor: 2667, sortIndex: 0 },
      { personId: "person-0", isMe: false, nameSnapshot: "Riad", amountMinor: 7667, parts: null, enteredMinor: 7667, sortIndex: 1 },
      { personId: "person-1", isMe: false, nameSnapshot: "Bijoy", amountMinor: 9666, parts: null, enteredMinor: 9666, sortIndex: 2 },
    ]);
  });

  it("an empty starter group / empty individual row is not saved in the rule", () => {
    const d = s.addIndividual(build({ people: ["A"], groups: [], individuals: [{ person: "A", amount: 2000 }], remaining: ["Me", "A"] }));
    expect(s.splitRule(d, 10000)).toBe('{"type":"hybrid","version":1,"groups":[],"individuals":[{"participant":1,"amountMinor":2000}],"remaining":[0,1]}');
  });

  it("draft → rows + rule → reload restores Hybrid Split; a new total recalculates or is reported", () => {
    const d = example();
    const loaded = s.draftFromShares(expenseFor(d, 20000), sharesFor(d, 20000), names)!;
    expect(s.isHybrid(loaded)).toBe(true);
    const h = loaded.hybrid!;
    const nameOf = (id: string) => loaded.participants.find((p) => p.id === id)!.name;
    expect(h.groups.map((g) => [g.amountText, g.memberIds.map(nameOf)])).toEqual([["100.00", ["Riad", "Bijoy"]]]);
    expect(h.individuals.map((r) => [nameOf(r.participantId!), r.amountText])).toEqual([["Bijoy", "20.00"]]);
    expect(h.remainderIds.map(nameOf)).toEqual(["Me", "Riad", "Bijoy"]);
    expect(s.shares(loaded, 20000)).toEqual([2667, 7667, 9666]);
    expect(s.splitRule(loaded, 20000)).toBe(RULE);
    expect(s.shares(loaded, 30000)).toEqual([6000, 11000, 13000]);
    expect(s.problem(loaded, 10000)).toBe("Fixed allocations exceed the transaction total by RM 20.00.");
    expect(s.shareRows(loaded, 10000)).toBeNull();
    // Turning it off keeps the saved amounts as custom amounts.
    const off = s.setHybrid(loaded, false);
    expect(off.method).toBe("amounts");
    expect(s.shares(off, 20000)).toEqual([2667, 7667, 9666]);
  });

  it.each([
    ["bad JSON", "{not json"],
    ["unknown type", '{"type":"other","version":1,"groups":[],"individuals":[],"remaining":[0]}'],
    ["unknown version", '{"type":"hybrid","version":2,"groups":[],"individuals":[],"remaining":[0]}'],
    ["position without a share", '{"type":"hybrid","version":1,"groups":[],"individuals":[{"participant":7,"amountMinor":100}],"remaining":[0]}'],
    ["bad amount", '{"type":"hybrid","version":1,"groups":[{"amountMinor":-5,"members":[1]}],"individuals":[],"remaining":[0]}'],
  ])("a bad rule (%s) opens as the normal Custom Amount split", (_n, rule) => {
    const d = example();
    const loaded = s.draftFromShares({ ...expenseFor(d, 20000), splitRule: rule }, sharesFor(d, 20000), names)!;
    expect(loaded.hybrid).toBeNull();
    expect(loaded.method).toBe("amounts");
    expect(loaded.autoCalculate).toBe(true); // on by default, saved amounts unchanged
    expect(s.shares(loaded, 20000)).toEqual([2667, 7667, 9666]);
  });

  it("existing transactions without a rule load exactly as before", () => {
    const rows = [
      { id: "1", personId: null, isMe: true, nameSnapshot: "Me", amountMinor: 6000, parts: null, enteredMinor: 6000, sortIndex: 0 },
      { id: "2", personId: "v", isMe: false, nameSnapshot: "Vijay", amountMinor: 3000, parts: null, enteredMinor: 3000, sortIndex: 1 },
    ];
    for (const splitRule of [undefined, null]) {
      const d = s.draftFromShares({ paidByMe: true, payerId: null, payerNameSnapshot: null, splitMethod: "amounts", splitRule }, rows, () => undefined)!;
      expect(d.hybrid).toBeNull();
      expect(d.autoCalculate).toBe(true); // on by default, saved amounts unchanged
      expect(s.shares(d, 9000)).toEqual([6000, 3000]);
    }
  });

  it("demo data source: stores the rule, reloads it, and clears it when edited into a normal split", async () => {
    localStorage.clear();
    const source = new DemoSource();
    const d = example();
    await source.saveExpense(expenseFor(d, 20000), sharesFor(d, 20000));
    const expense = rowToRecord<Expense>((await source.pull("expenses", null)).rows.find((r) => r.id === "e1")!);
    expect(expense.splitRule).toBe(RULE);
    const shares = (await source.pull("expense_shares", null)).rows.filter((r) => r.expense_id === "e1" && !r.deleted_at).map((r) => rowToRecord<ExpenseShare>(r));
    const loaded = s.draftFromShares(expense, shares, names)!;
    expect(s.isHybrid(loaded)).toBe(true);
    const plain = s.setMethod(s.setHybrid(loaded, false), "equal", 20000);
    await source.saveExpense({ ...expenseFor(plain, 20000), updatedAt: "2026-10-02T00:00:00.000Z" },
      s.shareRows(plain, 20000)!.map((r, i) => ({ ...r, id: `s${i}`, createdAt: T, updatedAt: "2026-10-02T00:00:00.000Z" })));
    const after = rowToRecord<Expense>((await source.pull("expenses", null)).rows.find((r) => r.id === "e1")!);
    expect(after.splitRule).toBeNull();
  });

  it("Supabase: the save RPC gets split_rule; direct expense writes work before and after the migration", async () => {
    const rpc = vi.fn(async () => ({ error: null }));
    const d = example();
    await new SupabaseSource({ rpc } as never, "u", null, null).saveExpense(expenseFor(d, 20000), sharesFor(d, 20000));
    const [, args] = rpc.mock.calls[0] as unknown as [string, { p_expense: Record<string, unknown>; p_shares: Record<string, unknown>[] }];
    expect(args.p_expense).toMatchObject({ split_method: "amounts", split_rule: RULE });
    expect(args.p_shares.map((r) => r.entered_minor)).toEqual([2667, 7667, 9666]);

    const sent: Record<string, unknown>[][] = [];
    let migrated = false;
    const client = {
      from: () => ({
        upsert: async (rows: Record<string, unknown>[]) => {
          sent.push(rows);
          return { error: rows.some((r) => "split_rule" in r) && !migrated ? { message: 'column "split_rule" of relation "expenses" does not exist' } : null };
        },
      }),
    };
    const source = new SupabaseSource(client as never, "u", null, null);
    await source.upsert("expenses", [{ id: "a", split_rule: null }]);
    expect(sent.at(-1)).toEqual([{ id: "a" }]);
    await source.upsert("expenses", [{ id: "b", split_rule: RULE }]);
    expect(sent.at(-1)).toEqual([{ id: "b" }]); // retried without the column
    migrated = true;
    await source.upsert("expenses", [{ id: "c", split_rule: RULE }]);
    expect(sent.at(-1)).toEqual([{ id: "c", split_rule: RULE }]);
    await source.upsert("expense_shares", [{ id: "s", amount_minor: 1 }]);
    expect(sent.at(-1)).toEqual([{ id: "s", amount_minor: 1 }]);
  });
});

describe("backup import: optional splitRule on expenses", () => {
  const backup = (expense: Record<string, unknown>) => ({
    version: 4,
    paybookProfiles: [{ id: "P1", name: "Riad" }, { id: "P2", name: "Bijoy" }],
    expenses: [{
      id: "E1", amount: 200, merchant: "Dinner", splitMethodRaw: "amounts", paidByMe: true, shares: [
        { id: "S1", isMe: true, nameSnapshot: "Me", amountMinor: 2667, enteredMinor: 2667, sortIndex: 0 },
        { id: "S2", personId: "P1", nameSnapshot: "Riad", amountMinor: 7667, enteredMinor: 7667, sortIndex: 1 },
        { id: "S3", personId: "P2", nameSnapshot: "Bijoy", amountMinor: 9666, enteredMinor: 9666, sortIndex: 2 },
      ], ...expense,
    }],
  });
  const now = "2026-10-01T00:00:00.000Z";

  it("keeps the rule and the split reloads as Hybrid Split", () => {
    const plan = planBackupImport(backup({ splitRule: RULE }), emptyDataset(), { now });
    expect(plan.records.expenses[0].splitRule).toBe(RULE);
    const d = s.draftFromShares(plan.records.expenses[0], plan.records.shares, () => undefined)!;
    expect(s.isHybrid(d)).toBe(true);
    expect(s.shares(d, 20000)).toEqual([2667, 7667, 9666]);
  });

  it("older backups without the key load exactly as before (no new key on the record)", () => {
    const plan = planBackupImport(backup({}), emptyDataset(), { now });
    expect("splitRule" in plan.records.expenses[0]).toBe(false);
    expect(s.draftFromShares(plan.records.expenses[0], plan.records.shares, () => undefined)!.hybrid).toBeNull();
  });

  it("ignores a non-string rule", () => {
    const plan = planBackupImport(backup({ splitRule: { type: "hybrid" } }), emptyDataset(), { now });
    expect("splitRule" in plan.records.expenses[0]).toBe(false);
  });
});

// Personal memory and personal insights (upgrade spec §9–§15, §17, §27–§28): rules are per user and disclosed,
// records never change, insights are exact and only appear when meaningful, suggestions are evidence-based.
import { describe, expect, it } from "vitest";
import { handleChat, type ChatDeps } from "@/lib/ai/chat-handler";
import { proactiveNotices } from "@/lib/ai/compose";
import { answerDeterministic } from "@/lib/ai/core";
import { getSpendingInsights, type InsightsData } from "@/lib/ai/insights";
import { executeTool } from "@/lib/ai/registry";
import { MemoryTenantStore } from "@/lib/ai/repository";
import type { AskAnswer } from "@/lib/ai/types";
import { USER_A, USER_B, ctx, exp } from "./fixtures";

async function ask(store: MemoryTenantStore, message: string, userId = USER_A): Promise<AskAnswer> {
  const out = await answerDeterministic(message, ctx(userId), store.forUser(userId), null, store.memoryFor(userId));
  if (out.kind !== "answer") throw new Error(`not understood: ${message}`);
  return out.answer;
}

const grabA = exp({ merchant: "Grab", amount: 20, date: "2026-10-06", category: "Shopping" });
const grabB = exp({ merchant: "Grab", amount: 30, date: "2026-10-06", category: "Food" });
const world = () => new MemoryTenantStore()
  .add(USER_A, { expenses: [grabA, exp({ merchant: "LRT", amount: 5, date: "2026-10-06", category: "Transport" })] })
  .add(USER_B, { expenses: [grabB] });

describe("personal memory", () => {
  it("“Grab is transport for me” is stored for that user and changes how their spending is grouped", async () => {
    const store = world();
    const set = await ask(store, "Grab is transport for me");
    expect(set.text).toBe("Got it — I'll treat Grab as Transport for you. Your transaction records aren't changed; this only affects how I group your spending in answers. Say “forget Grab” to undo.");
    const a = await ask(store, "How much did I spend on transport this week?");
    expect(a.text).toContain("You spent RM 25.00 on Transport");
    // Always disclosed, and the record itself is untouched.
    expect(a.text).toContain("Using your personal rule: Grab counts as Transport (1 transaction). Your records themselves aren't changed.");
    expect(grabA.category).toBe("Shopping");
  });

  it("User A's rule never affects User B (§14, §75, §104)", async () => {
    const store = world();
    await ask(store, "Grab is transport for me", USER_A);
    expect(await store.memoryFor(USER_B).list()).toEqual([]);
    const b = await ask(store, "How much did I spend on transport this week?", USER_B);
    expect(b.status).toBe("no_match");
    const bFood = await ask(store, "How much did I spend on food this week?", USER_B);
    expect(bFood.text).toContain("RM 30.00");
    expect(bFood.text).not.toContain("personal rule");
  });

  it("both users can hold opposite rules for the same merchant", async () => {
    const store = world();
    await ask(store, "Grab is transport for me", USER_A);
    await ask(store, "Grab is food for me", USER_B);
    expect((await ask(store, "how much on transport this week", USER_A)).text).toContain("RM 25.00");
    expect((await ask(store, "how much on food this week", USER_B)).text).toContain("RM 30.00");
  });

  it("lists and forgets rules", async () => {
    const store = world();
    await ask(store, "Grab is transport for me");
    await ask(store, "treat Starbucks as food");
    expect((await ask(store, "what do you remember about me?")).text).toBe("Here's what I remember for you: Grab counts as Transport; Starbucks counts as Food. Say “forget Grab” to remove one.");
    expect((await ask(store, "forget Grab")).text).toBe("Done — I've forgotten your rule for grab.");
    expect(await store.memoryFor(USER_A).list()).toEqual([{ merchant: "Starbucks", merchantKey: "starbucks", category: "Food" }]);
  });

  it("a question about a rule is not stored as a rule", async () => {
    const store = world();
    await ask(store, "is grab transport?");
    expect(await store.memoryFor(USER_A).list()).toEqual([]);
  });

  it("the model can't write memory: there is no write tool", async () => {
    for (const name of ["remember", "set_memory", "save_preference", "update_transaction"]) {
      const r = await executeTool(name, { merchant: "Grab", category: "Transport" }, ctx(USER_A), world().forUser(USER_A));
      expect(!r.result.ok && r.result.error.message).toContain("Unknown tool");
    }
  });

  it("through /api/ai/chat the memory store is bound to the signed-in user", async () => {
    const store = world();
    const deps = (userId: string): ChatDeps => ({
      authenticate: async () => ({ ok: true, client: {} as never, userId }),
      repository: (a) => store.forUser(a.userId), memory: (a) => store.memoryFor(a.userId),
      store: () => ({ exists: async () => false, create: async () => crypto.randomUUID(), rename: async () => {}, append: async () => {}, messages: async () => [], questionsSince: async () => 0 }),
      provider: () => null, debug: true,
    });
    const req = (message: string) => new Request("http://localhost:3000/api/ai/chat", { method: "POST", body: JSON.stringify({ message }), headers: { "content-type": "application/json", origin: "http://localhost:3000", host: "localhost:3000" } });
    await handleChat(req("Grab is transport for me"), deps(USER_A));
    expect(await store.memoryFor(USER_A).list()).toHaveLength(1);
    expect(await store.memoryFor(USER_B).list()).toEqual([]);
  });
});

// Three earlier months with RM100 of Food on 1–7 of each month; this month (to 7 Oct) Food RM300 and Shopping RM250.
function insightWorld() {
  const expenses = ["2026-07-03", "2026-08-03", "2026-09-03"].map((date) => exp({ merchant: "Mamak Corner", amount: 100, date, category: "Food" }));
  expenses.push(exp({ merchant: "Mamak Corner", amount: 120, date: "2026-10-02", category: "Food" }), exp({ merchant: "Sushi King", amount: 180, date: "2026-10-05", category: "Food" }));
  expenses.push(exp({ merchant: "Shopee", amount: 250, date: "2026-10-04", category: "Shopping" }));
  return new MemoryTenantStore().add(USER_A, { expenses });
}

describe("personal insights", () => {
  it("“Why am I spending so much lately?” → exact change vs the user's own normal, main drivers, one suggestion", async () => {
    const a = await ask(insightWorld(), "Bro, why am I spending so much lately?");
    expect(a.meta.tools.map((t) => t.name)).toEqual(["get_spending_insights"]);
    expect(a.text).toBe("You've spent RM 450.00 more this month so far (1–7 Oct 2026) than your normal for the same days (RM 100.00, the average of the same days in your previous 3 months) — up 450%. The biggest increases: Shopping +RM 250.00, Food +RM 200.00.");
    expect(a.suggestion).toBe("If you're trying to reduce spending, Shopping is the category I'd review first — it contributed the most to the increase.");
    expect(`${a.text} ${a.insight ?? ""} ${a.suggestion}`).not.toMatch(/waste|terrible|must stop|bad with money|you should stop/i);
    expect(a.evidence[0].tool).toBe("get_spending_insights");
  });

  it("not enough history → says so, no comparison, no suggestion (§155)", async () => {
    const store = new MemoryTenantStore().add(USER_A, { expenses: [exp({ merchant: "X", amount: 50, date: "2026-10-03", category: "Food" })] });
    const a = await ask(store, "What's going wrong with my spending?");
    expect(a.text).toMatch(/^I don't have enough history yet to know your normal month/);
    expect(a.suggestion).toBeUndefined();
  });

  it("normal spending → says it's in line; no invented insight or suggestion (§12, §27)", async () => {
    const expenses = ["2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"].map((date) => exp({ merchant: "Mamak Corner", amount: 100, date, category: "Food" }));
    const a = await ask(new MemoryTenantStore().add(USER_A, { expenses }), "how am i doing this month?");
    expect(a.text).toBe("Your spending this month so far (1–7 Oct 2026) is RM 100.00 — in line with your normal for the same days (RM 100.00, the average of the same days in your previous 3 months).");
    expect(a.insight).toBeUndefined();
    expect(a.suggestion).toBeUndefined();
  });

  it("small payments that add up, computed exactly", async () => {
    const store = insightWorld();
    for (const day of ["01", "02", "03", "05", "06", "07"]) store.add(USER_A, { expenses: [exp({ merchant: "Kopi Corner", amount: 8, date: `2026-10-${day}`, category: "Food" })] });
    const r = await getSpendingInsights({ period: "this_month" }, ctx(), store.forUser(USER_A));
    expect(r.ok && r.data.smallAddUps).toEqual([{ label: "Kopi Corner", count: 6, totalMinor: 4800 }]);
  });

  it("proactive notices only when something meaningful changed", async () => {
    const r = await getSpendingInsights({ period: "this_month" }, ctx(), insightWorld().forUser(USER_A));
    const notices = proactiveNotices((r as { data: InsightsData }).data);
    expect(notices.map((n) => n.title)).toEqual(["You've spent more than usual this month", "Shopping is higher than usual"]);
    const flat = ["2026-08-03", "2026-09-03", "2026-10-03"].map((date) => exp({ merchant: "M", amount: 100, date, category: "Food" }));
    const quiet = await getSpendingInsights({ period: "this_month" }, ctx(), new MemoryTenantStore().add(USER_A, { expenses: flat }).forUser(USER_A));
    expect(proactiveNotices((quiet as { data: InsightsData }).data)).toEqual([]);
  });

  it("insights use only the asking user's history", async () => {
    const store = insightWorld().add(USER_B, { expenses: [exp({ merchant: "Huge", amount: 9999, date: "2026-10-02", category: "Shopping" })] });
    const a = await ask(store, "why am I spending so much lately?", USER_A);
    expect(JSON.stringify(a)).not.toContain("9,999");
    const b = await ask(store, "why am I spending so much lately?", USER_B);
    expect(b.text).toMatch(/^I don't have enough history yet/);
  });
});

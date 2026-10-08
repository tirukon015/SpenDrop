// Merchant / entity resolution: people refer to merchants by part of the name, a typo, other spacing or punctuation,
// in any language. The resolver is general (no merchant is special-cased): synthetic names prove it on arbitrary
// merchants, and the production case ("similar name with bijoy how much" → BIJOYSHARIARALAMIN) is checked end to end
// with exact figures. Resolution only ever sees the signed-in user's own merchants.
import { describe, expect, it } from "vitest";
import { answerDeterministic } from "@/lib/ai/core";
import { candidatesFor, matchQuality, normalizeName, resolveMerchant } from "@/lib/ai/merchant-resolver";
import { plan } from "@/lib/ai/planner";
import { MemoryTenantStore } from "@/lib/ai/repository";
import type { AskAnswer, Focus } from "@/lib/ai/types";
import { USER_A, USER_B, ctx, exp } from "./fixtures";

const MERCHANTS = [
  "BIJOYSHARIARALAMIN", "RAHIM TRADING SDN BHD", "MANGO CAFE CYBERJAYA", "ABC-MART-001", "Starbucks", "Jaya Grocer",
  "Grab", "Shopee", "Shopee Food", "KK Super Mart", "Touch 'n Go Parking", "Café Résumé",
];

describe("normalisation (comparison only — stored names never change)", () => {
  it("case, spacing, punctuation, separators and accents compare equal", () => {
    for (const v of ["BIJOY SHARIA R AL AMIN", "bijoyshariaralamin", "Bijoy-Sharia-R-Alamin", "BIJOYSHARIARALAMIN", "bijoy_sharia r.al'amin"])
      expect(normalizeName(v).replace(/ /g, "")).toBe("bijoyshariaralamin");
    expect(normalizeName("Café Résumé")).toBe("cafe resume");
  });
});

describe("matching an arbitrary merchant", () => {
  const cases: [string, string, string][] = [
    // reference, expected merchant, kind
    ["BIJOYSHARIARALAMIN", "BIJOYSHARIARALAMIN", "exact"],
    ["bijoy", "BIJOYSHARIARALAMIN", "partial"], ["sharia", "BIJOYSHARIARALAMIN", "partial"], ["alamin", "BIJOYSHARIARALAMIN", "partial"],
    ["bijoysharia", "BIJOYSHARIARALAMIN", "prefix"], ["bijoy sharia", "BIJOYSHARIARALAMIN", "spacing"], ["bijoy-sharia", "BIJOYSHARIARALAMIN", "punctuation"],
    ["bijoi", "BIJOYSHARIARALAMIN", "typo"], ["bijoyy", "BIJOYSHARIARALAMIN", "typo"], ["bijoy alamin", "BIJOYSHARIARALAMIN", "two parts"],
    ["rahim", "RAHIM TRADING SDN BHD", "word"], ["rahim trading", "RAHIM TRADING SDN BHD", "words"],
    ["mango", "MANGO CAFE CYBERJAYA", "word"], ["cyberjaya", "MANGO CAFE CYBERJAYA", "word"],
    ["abc mart", "ABC-MART-001", "spacing"], ["abcmart", "ABC-MART-001", "compact"],
    ["starbuck", "Starbucks", "prefix"], ["starbukcs", "Starbucks", "typo"], ["jaya grocr", "Jaya Grocer", "typo"],
    ["cafe resume", "Café Résumé", "accents"],
  ];
  for (const [ref, name, kind] of cases)
    it(`${kind}: “${ref}” → ${name}`, () => {
      const r = resolveMerchant(ref, MERCHANTS);
      expect(r?.kind, JSON.stringify(r)).toBe("match");
      expect(r && r.names).toEqual([name]);
    });

  it("a whole word shared by several names includes them all (and the answer discloses them)", () => {
    expect(resolveMerchant("shopee", MERCHANTS)).toMatchObject({ kind: "match", names: ["Shopee", "Shopee Food"] });
  });

  it("never matches tiny or common fragments, and a stronger match always wins", () => {
    for (const ref of ["a", "e", "i", "ab", "the", "how much", "my", "show transactions"]) expect(resolveMerchant(ref, MERCHANTS), ref).toBeNull();
    expect(matchQuality("mart", "KK Super Mart")).toBe("word");
    expect(candidatesFor("mart", MERCHANTS).map((c) => c.quality)).toEqual(["word", "word"]); // "mart" is a whole word of both names
    expect(candidatesFor("bijoysharia", MERCHANTS)).toEqual([{ name: "BIJOYSHARIARALAMIN", quality: "prefix", score: 80 }]);
    expect(resolveMerchant("zebra kopitiam", MERCHANTS)).toBeNull();
  });
});

describe("several close candidates → ask, unless the user asked for all similar names", () => {
  const close = ["BIJOY MART", "BIJOY CAFE", "BIJOYSHARIARALAMIN"];
  it("a whole word shared by names → all (disclosed); a partial reference shared by names → clarify", () => {
    expect(resolveMerchant("how much did I spend at bijoy?", close)).toMatchObject({ kind: "match", names: ["BIJOY CAFE", "BIJOY MART"] });
    expect(resolveMerchant("how much at bij?", close)).toMatchObject({ kind: "ambiguous" });
  });
  it("the planner asks which one, listing the candidates, with ready-made follow-ups", () => {
    const p = plan({ message: "how much at bijo?", today: "2026-10-07", vocabulary: vocab(close), focus: null });
    expect(p.kind).toBe("reply");
    if (p.kind !== "reply") return;
    expect(p.status).toBe("clarify");
    for (const n of close) expect(p.text).toContain(n);
    expect(p.followUps[0]).toMatch(/how much at BIJOY/i);
  });
  it("“similar names” includes every candidate", () => {
    const p = plan({ message: "similar name with bijo how much", today: "2026-10-07", vocabulary: vocab(close), focus: null });
    expect(p.kind === "tools" && p.steps[0].args.merchants).toEqual(expect.arrayContaining(close));
  });
});

function vocab(merchants: string[]) {
  return { merchants, fundingAccounts: ["Maybank", "CIMB", "Touch 'n Go"], currencies: ["RM"], earliestDate: "2026-01-01", expenseCount: 10 };
}

// ---------------------------------------------------------------------------------------------------------------
// End to end on a user's real-shaped data: exact figures, evidence, languages, follow-ups and tenant isolation.

function store() {
  const s = new MemoryTenantStore();
  s.add(USER_A, { expenses: [
    exp({ merchant: "BIJOYSHARIARALAMIN", amount: 599.32, date: "2026-10-07", time: "16:48", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
    exp({ merchant: "BIJOYSHARIARALAMIN", amount: 7, date: "2026-10-03", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
    exp({ merchant: "BIJOYSHARIARALAMIN", amount: 40, date: "2026-09-12", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
    exp({ merchant: "RAHIM TRADING SDN BHD", amount: 120, date: "2026-10-02", category: "Shopping", channel: "CARD", account: "CIMB" }),
    exp({ merchant: "MANGO CAFE CYBERJAYA", amount: 23.5, date: "2026-10-06", category: "Food", channel: "APPLE_PAY", account: "Maybank" }),
    exp({ merchant: "ABC-MART-001", amount: 15.9, date: "2026-10-05", category: "Groceries", channel: "CARD", account: "CIMB" }),
    exp({ merchant: "KK Super Mart", amount: 5.5, date: "2026-10-05", category: "Food", channel: "APPLE_PAY", account: "Maybank" }),
  ] });
  // Another user's merchant: must never become a candidate for user A.
  s.add(USER_B, { expenses: [exp({ merchant: "ZEBRA KOPITIAM", amount: 77, date: "2026-10-04", category: "Food" }), exp({ merchant: "BIJOY SECRET SUPPLIES", amount: 999, date: "2026-10-04" })] });
  return s;
}

async function chat(questions: string[], user = USER_A): Promise<AskAnswer[]> {
  const s = store();
  let focus: Focus | null = null;
  const out: AskAnswer[] = [];
  for (const q of questions) {
    const r = await answerDeterministic(q, ctx(user), s.forUser(user), focus);
    if (r.kind !== "answer") throw new Error(`no answer: ${q}`);
    out.push(r.answer);
    focus = r.answer.focus;
  }
  return out;
}
const one = async (q: string) => (await chat([q]))[0];
const listed = (a: AskAnswer) => a.blocks.flatMap((b) => (b.type === "transactions" ? b.items : []));

describe("the production case and natural / multilingual phrasings (exact figures)", () => {
  it("“similar name with bijoy how much” → BIJOYSHARIARALAMIN, RM 606.32 this month, with evidence and the match explained", async () => {
    const a = await one("similar name with bijoy how much");
    expect(a.status).toBe("answered");
    expect(a.text).toContain("RM 606.32");
    expect(a.text).toContain("BIJOYSHARIARALAMIN");
    expect(a.text).toMatch(/matched “bijoy” to BIJOYSHARIARALAMIN/);
    expect(a.evidence[0].transactionCount).toBe(2);
    const rows = listed(a);
    expect(rows.map((r) => r.merchant)).toEqual(["BIJOYSHARIARALAMIN", "BIJOYSHARIARALAMIN"]);
    expect(rows.reduce((t, r) => t + r.spendMinor, 0)).toBe(60632);
  });

  const spend = ["how much did I spend at bijoy?", "how much went to bijoy?", "how much did I spend with Bijoy?", "bijoy how much?", "bijoy te koto khoroch hoise?",
    "bijoy er jonno koto gelo?", "bijoy e koto spend korchi?", "berapa saya belanja dekat bijoy?", "how much did I spend at bijoi?", "how much did I spend at bijoy sharia?"];
  for (const q of spend)
    it(`spending: ${q}`, async () => {
      const a = await one(q);
      expect(a.status, a.text).toBe("answered");
      expect(a.text).toContain("RM 606.32");
      expect(listed(a).every((r) => r.merchant === "BIJOYSHARIARALAMIN")).toBe(true);
    });

  for (const q of ["show bijoy transactions", "show my bijoy transactions", "bijoy er transaction gula dekhao", "show transactions related to bijoy", "anything with bijoy"])
    it(`transactions: ${q}`, async () => {
      const a = await one(q);
      expect(a.status, a.text).toBe("answered");
      const rows = listed(a);
      expect(rows.length).toBeGreaterThan(0);
      expect(rows.every((r) => r.merchant === "BIJOYSHARIARALAMIN")).toBe(true);
    });

  for (const [q, name, amount] of [["how much at rahim?", "RAHIM TRADING SDN BHD", "RM 120.00"], ["how much did I spend at mango?", "MANGO CAFE CYBERJAYA", "RM 23.50"], ["abc mart koto khoroch?", "ABC-MART-001", "RM 15.90"]] as const)
    it(`any merchant: ${q} → ${name}`, async () => {
      const a = await one(q);
      expect(a.text).toContain(amount);
      expect(listed(a).every((r) => r.merchant === name)).toBe(true);
    });

  it("no match: says no merchant matches the name (never invents one)", async () => {
    const a = await one("how much did I spend at zorblax?");
    expect(a.status).toBe("no_match");
    expect(a.text).toMatch(/couldn't find a merchant matching “Zorblax”/i);
    expect(a.blocks).toEqual([]);
  });
});

describe("tenant isolation", () => {
  it("user A never resolves a merchant that only user B has", async () => {
    const a = await one("how much did I spend at zebra kopitiam?");
    expect(a.status).toBe("no_match");
    expect(JSON.stringify(a)).not.toContain("ZEBRA");
    const b = await one("similar name with bijoy how much");
    expect(JSON.stringify(b)).not.toContain("SECRET");
    expect(b.text).toContain("RM 606.32");
  });
  it("user B resolving “bijoy” only sees user B's merchant", async () => {
    const [b] = await chat(["how much did I spend at bijoy?"], USER_B);
    expect(b.text).toContain("RM 999.00");
    expect(JSON.stringify(b)).not.toContain("BIJOYSHARIARALAMIN");
  });
});

describe("follow-ups keep the resolved merchant", () => {
  it("merchant → yesterday → show transactions → why → last month", async () => {
    const [first, yesterday, shown, why, last] = await chat(["How much did I spend at bijoy?", "Yesterday?", "Show the transactions", "Why?", "Last month?"]);
    expect(first.text).toContain("RM 606.32");
    expect(yesterday.focus?.filters.merchant).toBe("BIJOYSHARIARALAMIN");
    expect(yesterday.text).toMatch(/BIJOYSHARIARALAMIN/);
    expect(shown.focus?.filters.merchant).toBe("BIJOYSHARIARALAMIN");
    expect(why.focus?.filters.merchant).toBe("BIJOYSHARIARALAMIN");
    expect(last.focus?.filters.merchant).toBe("BIJOYSHARIARALAMIN");
    expect(listed(last).map((r) => [r.merchant, r.spendMinor, r.localDate])).toEqual([["BIJOYSHARIARALAMIN", 4000, "2026-09-12"]]);
  });
});

describe("generalisation on random synthetic merchants (seeded)", () => {
  // Deterministic pseudo-random names like "KORAVI TUNESH SDN BHD" / "MELODAPRISTON" / "ZAN-KOTU-042".
  function rng(seed: number) { return () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31); }
  const word = (r: () => number, len: number) => Array.from({ length: len }, (_, i) => (i % 2 ? "aeiou" : "bdfgklmnprstvz")[Math.floor(r() * (i % 2 ? 5 : 14))]).join("");
  function names(seed: number, n: number) {
    const r = rng(seed);
    return Array.from({ length: n }, (_, i) => {
      const a = word(r, 5 + Math.floor(r() * 3)), b = word(r, 5 + Math.floor(r() * 3));
      return i % 3 === 0 ? `${a} ${b} SDN BHD`.toUpperCase() : i % 3 === 1 ? `${a}${b}`.toUpperCase() : `${a}-${b}-0${10 + i}`.toUpperCase();
    });
  }
  const typo = (w: string) => w.slice(0, 2) + (w[2] === "a" ? "e" : "a") + w.slice(3);

  it("first word, glued prefix, inner part (≥5), spacing/punctuation and one typo each resolve to the right merchant", () => {
    const all = names(2026, 300);
    let ok = 0, total = 0;
    const misses: string[] = [];
    for (const name of all) {
      const parts = name.toLowerCase().split(/[\s-]+/);
      const refs = [parts[0], name.toLowerCase().replace(/[\s-]+/g, "").slice(0, 7), `${parts[0]} ${parts[1]}`, typo(parts[0])];
      for (const ref of refs) {
        total++;
        const r = resolveMerchant(`how much at ${ref}?`, all);
        if (r && r.names.includes(name)) ok++; else misses.push(`${ref} → ${name} (${JSON.stringify(r)?.slice(0, 80)})`);
      }
    }
    if (process.env.NLU_REPORT) console.log(`synthetic merchant recall: ${ok}/${total}\n${misses.slice(0, 8).join("\n")}`);
    expect(ok / total).toBeGreaterThanOrEqual(0.97);
  });

  it("unrelated words and other users' names never resolve (precision)", () => {
    const mine = names(7, 200), theirs = names(99, 200);
    let wrong = 0;
    for (const other of theirs) {
      const first = other.toLowerCase().split(/[\s-]+/)[0];
      // Skip a generated word that genuinely occurs inside one of my names (that IS a similar name, e.g. "zosek" in FIZOSEK).
      if (mine.some((m) => m.toLowerCase().replace(/[\s-]+/g, "").includes(first))) continue;
      const r = resolveMerchant(`how much at ${first}?`, mine);
      if (r && r.kind === "match" && r.quality !== "fuzzy") wrong++;
    }
    for (const w of ["hope", "having", "good", "day", "thanks", "weather", "tomorrow", "please", "today", "money"]) if (resolveMerchant(w, mine)?.kind === "match") wrong++;
    expect(wrong).toBe(0);
  });
});

describe("one merchant, several spellings (real data: BIJOYSHARIARALAMIN and BIJOY SHARIAR AL AMIN)", () => {
  function twoSpellings() {
    const s = new MemoryTenantStore();
    s.add(USER_A, { expenses: [
      exp({ merchant: "BIJOYSHARIARALAMIN", amount: 599.32, date: "2026-10-07", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
      exp({ merchant: "BIJOYSHARIARALAMIN", amount: 7, date: "2026-10-03", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
      exp({ merchant: "BIJOY SHARIAR AL AMIN", amount: 50, date: "2026-09-20", category: "Other", channel: "QR_PAYMENT", account: "Maybank" }),
      exp({ merchant: "KK Super Mart", amount: 5.5, date: "2026-10-05", category: "Food" }),
    ] });
    return s;
  }
  const ask = async (q: string) => { const r = await answerDeterministic(q, ctx(), twoSpellings().forUser(USER_A), null); if (r.kind !== "answer") throw new Error(q); return r.answer; };

  it("spellings are one candidate (a typo is not 'ambiguous')", () => {
    expect(resolveMerchant("bijoi", ["BIJOYSHARIARALAMIN", "BIJOY SHARIAR AL AMIN"])).toMatchObject({ kind: "match" });
    expect(resolveMerchant("bijoi", ["BIJOYSHARIARALAMIN", "BIJOY SHARIAR AL AMIN"])?.names.sort()).toEqual(["BIJOY SHARIAR AL AMIN", "BIJOYSHARIARALAMIN"]);
  });
  it("all-time transactions include every spelling (3 rows), and the answer discloses both names", async () => {
    const a = await ask("show bijoy transactions");
    expect(listed(a).map((r) => r.spendMinor).sort((x, y) => x - y)).toEqual([700, 5000, 59932]);
    expect(a.text).toMatch(/2 merchant names/);
  });
  it("totals across spellings are exact", async () => {
    expect((await ask("how much did I spend at bijoi of all time?")).text).toContain("RM 656.32");
    expect((await ask("similar name with bijoy how much")).text).toContain("RM 606.32"); // this month: only the October spelling has rows
  });
});

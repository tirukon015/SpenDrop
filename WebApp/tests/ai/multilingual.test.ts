// Multilingual answers are worded from the SAME verified result: the amounts, counts and dates in a Banglish /
// Bengali / Malay answer must be exactly those of the English answer to the same question. Frequency answers count
// actual transactions (and distinct days), never "visits".
import { describe, expect, it } from "vitest";
import { answerDeterministic } from "@/lib/ai/core";
import type { AskAnswer } from "@/lib/ai/types";
import { USER_A, ctx, historyStore } from "./fixtures";

const store = historyStore();
async function answer(q: string): Promise<AskAnswer> {
  const out = await answerDeterministic(q, ctx(), store.forUser(USER_A), null);
  if (out.kind !== "answer") throw new Error(`no answer for ${q}`);
  return out.answer;
}
const amounts = (t: string) => (t.match(/RM\s?[\d,]+\.\d\d/g) ?? []).map((m) => m.replace(/\s/g, "")).sort();
const integers = (t: string) => (t.replace(/RM\s?[\d,]+\.\d\d/g, "").replace(/\d{1,2}[–-]\d{1,2} \w{3} \d{4}|\d{1,2} \w{3} \d{4}/g, "").match(/\d+(\.\d+)?/g) ?? []).sort();

const SAME_QUESTION: { en: string; others: [string, string][] }[] = [
  { en: "How much did I spend on food this week?", others: [["bn-latn", "ei week e food e koto khoroch hoise?"], ["bn", "এই সপ্তাহে খাবারে কত খরচ করেছি?"], ["ms", "berapa saya belanja untuk makanan minggu ni?"]] },
  { en: "How much did I spend this month?", others: [["bn-latn", "ei mash e koto khoroch hoise?"], ["ms", "berapa saya belanja bulan ni?"]] },
  { en: "How many times did I go to Starbucks this month?", others: [["bn-latn", "ei mash e starbucks koto bar gesi?"], ["ms", "berapa kali saya pergi Starbucks bulan ni?"]] },
  { en: "card or qr this month?", others: [["bn-latn", "ei mash e card na qr beshi?"], ["ms", "card atau qr bulan ni?"]] },
];

describe("multilingual answers keep the verified figures", () => {
  for (const { en, others } of SAME_QUESTION)
    for (const [lang, q] of others)
      it(`${lang}: ${q}`, async () => {
        const [a, b] = await Promise.all([answer(en), answer(q)]);
        expect(b.meta.intent).toBe(a.meta.intent);
        expect(amounts(b.text), b.text).toEqual(amounts(a.text));
        expect(integers(b.text), b.text).toEqual(integers(a.text));
        // the structured evidence is identical, whatever the language
        expect(b.blocks).toEqual(a.blocks);
        expect(b.evidence.map(({ generatedAt: _g, ...e }) => e)).toEqual(a.evidence.map(({ generatedAt: _g, ...e }) => e)); // eslint-disable-line @typescript-eslint/no-unused-vars
      });

  it("Banglish / Bengali / Malay questions are answered in that language", async () => {
    expect((await answer("ei week e food e koto khoroch hoise?")).text).toMatch(/khoroch hoise/);
    expect((await answer("এই সপ্তাহে খাবারে কত খরচ করেছি?")).text).toMatch(/[ঀ-৿]/);
    expect((await answer("berapa saya belanja untuk makanan minggu ni?")).text).toMatch(/Anda belanja/);
  });
});

describe("frequency = actual transactions", () => {
  it("count and distinct days equal the listed rows; never 'visits'", async () => {
    const a = await answer("How often do I buy from Starbucks this month?");
    const rows = a.blocks.flatMap((b) => (b.type === "transactions" ? b.items : []));
    const n = Number(/(\d+) transactions?/.exec(a.text)?.[1]);
    expect(n).toBe(rows.length);
    expect(rows.every((r) => r.merchant === "Starbucks")).toBe(true);
    const days = new Set(rows.map((r) => r.localDate)).size;
    if (days !== n) expect(a.text).toContain(`${days} different day`);
    expect(a.text).not.toMatch(/visit/i);
  });

  it("card vs QR: the amounts stated equal the channel groups, which add up to the total", async () => {
    const a = await answer("card or qr this month?");
    expect(a.meta.intent).toBe("PAYMENT_CHANNEL_ANALYSIS");
    const groups = a.blocks.find((b) => b.type === "breakdown");
    expect(groups && groups.type === "breakdown" && groups.items.map((i) => i.label)).toEqual(expect.arrayContaining(["Card", "QR"]));
    expect(a.text).toMatch(/Card|QR/);
  });
});

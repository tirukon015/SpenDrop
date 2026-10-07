// Bulk Screenshot Import: the shared vectors (Common/BusinessRules/bulk-import-vectors.json) and the Web draft rules.
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { draftStatus, draftsFromScreenshot, findDuplicates, manualDraft, runPool, summarize, willAdd, type BulkDraft } from "@/lib/bulk-import";
import { findDuplicateExpense } from "@/lib/domain/duplicates";
import { emptyDataset, type Expense } from "@/lib/domain/types";
import { splitScreenshot } from "@/lib/ocr/bulk";
import type { OcrLine } from "@/lib/ocr/parse";
import { initialDraft, persistDraft, type SaveContext } from "@/lib/transaction-draft";

const common = (file: string) => JSON.parse(readFileSync(path.resolve(__dirname, "../../../Common", file), "utf8"));
const rules = emptyDataset();
const lines = (texts: string[], confidence = 0.95): OcrLine[] => texts.map((text) => ({ text, confidence }));
const shot = (n: number) => new Blob([`screenshot-${n}`], { type: "image/webp" });
const taken = new Date(2026, 9, 7, 9, 0);

interface Vector {
  name: string;
  importDate: string;
  lines: string[];
  expect: { kind: "single" | "list"; items: { merchant: string; amountMinor: number; direction: string; date: string; time: string }[] };
}

describe("Common/BusinessRules/bulk-import-vectors.json", () => {
  const { cases } = common("BusinessRules/bulk-import-vectors.json") as { cases: Vector[] };
  it("has the 8 shared cases", () => expect(cases).toHaveLength(8));
  it.each(cases.map((c) => [c.name, c] as const))("%s", (_name, c) => {
    expect(splitScreenshot(c.lines, c.importDate)).toEqual(c.expect);
  });
});

const saved = (over: Partial<Expense>): Expense => ({
  id: "saved-1", amountMinor: 1050, currency: "RM", merchant: "Grab", category: "Transport", paymentChannel: "UNKNOWN", fundingAccount: "Unknown",
  fundingInstrument: null, accountId: null, paymentSource: null, date: new Date(2026, 9, 7, 12, 0).toISOString(), notes: null, transactionReference: null,
  sourceType: "manual", paidByMe: true, payerId: null, payerNameSnapshot: null, splitMethod: null, receiptPath: null, isSampleData: false,
  createdAt: "", updatedAt: "", deletedAt: null, ...over,
});

const history = ["Transaction History", "7 Oct — Grab — RM10.50", "7 Oct — McDonald's — RM12.90", "7 Oct — Starbucks — RM15.00"];

describe("screenshot → drafts", () => {
  it("a list gives one normal draft per row, with each row's own date and time and its own screenshot", () => {
    const blob = shot(1);
    const drafts = draftsFromScreenshot(lines(["Maybank2u", "06/10/2026 21:32 SHOPEE MALAYSIA -RM35.00", "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", "05/10/2026 08:10 PETRONAS -RM60.00"]), 1, blob, "2026-10-07", taken);
    expect(drafts).toHaveLength(3);
    expect(drafts.map((b) => [b.draft.type, b.draft.merchant, b.draft.amountText, b.draft.date, b.draft.time])).toEqual([
      ["expense", "SHOPEE MALAYSIA", "35.00", "2026-10-06", "21:32"],
      ["moneyIn", "DUITNOW FROM ALI", "50.00", "2026-10-06", "14:05"],
      ["expense", "PETRONAS", "60.00", "2026-10-05", "08:10"],
    ]);
    expect(drafts.every((b) => b.draft.receipt === blob && b.screenshot === 1)).toBe(true);
    expect(new Set(drafts.map((b) => b.key)).size).toBe(3);
    // Same shape as the editor's own state (no special bulk record type).
    expect(Object.keys(drafts[0].draft).sort()).toEqual(Object.keys(initialDraft({ shares: new Map(), people: [] })).sort());
  });

  it("a single receipt uses the existing parser and the screenshot's date, not the import time", () => {
    const [b] = draftsFromScreenshot(lines(["TNG eWallet", "Payment Successful", "RM18.50", "Paid to: McDonald's", "16 Sep 2026 9:42 PM", "Ref No: TNG992837194"]), 2, shot(2), "2026-10-07", taken);
    expect(b.draft).toMatchObject({ type: "expense", amountText: "18.50", merchant: "McDonald's", date: "2026-09-16", time: "21:42", reference: "TNG992837194" });
  });

  it("nothing detected gives no draft; a blank manual draft keeps the screenshot", () => {
    expect(draftsFromScreenshot(lines(["Settings", "Wi-Fi", "Bluetooth"]), 3, shot(3), "2026-10-07", taken)).toEqual([]);
    const m = manualDraft(3, shot(3), taken);
    expect(m.draft).toMatchObject({ amountText: "", date: "2026-10-07", time: "09:00" });
    expect(m.draft.receipt).not.toBeNull();
  });

  it("low OCR confidence or a failed payment needs review", () => {
    const [low] = draftsFromScreenshot(lines(history, 0.3), 1, null, "2026-10-07", taken);
    expect(draftStatus(low, undefined, rules)).toBe("review");
    const [failed] = draftsFromScreenshot(lines(["Payment Failed", "Total RM20.00", "Paid to: Tealive", "07/10/2026 10:00"]), 1, null, "2026-10-07", taken);
    expect(draftStatus(failed, undefined, rules)).toBe("review");
  });
});

describe("duplicates", () => {
  it("the extracted check behaves like the form's original one", () => {
    const e = saved({ transactionReference: "ABC123" });
    expect(findDuplicateExpense({ amountMinor: 999, merchant: "x", date: "2020-01-01", reference: " ABC123 " }, [e])).toBe(e);
    expect(findDuplicateExpense({ amountMinor: 1050, merchant: "  grab ", date: "2026-10-07", reference: "" }, [e])).toBe(e);
    expect(findDuplicateExpense({ amountMinor: 1050, merchant: "Grab", date: "2026-10-08", reference: "" }, [e])).toBeNull();
    expect(findDuplicateExpense({ id: e.id, amountMinor: 1050, merchant: "Grab", date: "2026-10-07", reference: "" }, [e])).toBeNull();
  });

  it("checks saved records, then earlier drafts in the same batch; a possible duplicate defaults to Skip", () => {
    const first = draftsFromScreenshot(lines(history), 1, shot(1), "2026-10-07", taken);
    const again = draftsFromScreenshot(lines(history), 2, shot(2), "2026-10-07", taken); // same screenshot twice
    const all = [...first, ...again];
    const dups = findDuplicates(all, [saved({})]);
    expect(dups.get(first[0].key)).toMatchObject({ kind: "saved" }); // Grab RM10.50 already recorded
    expect(dups.has(first[1].key)).toBe(false);
    expect(dups.get(again[1].key)).toMatchObject({ kind: "batch", key: first[1].key, screenshot: 1 });
    expect(dups.get(again[2].key)).toMatchObject({ kind: "batch", key: first[2].key });
    // Default Skip: not added until the user picks Add Anyway.
    expect(draftStatus(again[1], dups.get(again[1].key), rules)).toBe("duplicate");
    expect(willAdd(again[1], dups.get(again[1].key), rules)).toBe(false);
    const addAnyway = { ...again[1], decision: "add" as const };
    expect(willAdd(addAnyway, dups.get(again[1].key), rules)).toBe(true);
    expect(draftStatus(addAnyway, dups.get(again[1].key), rules)).toBe("ready");
    // Removing the earlier draft clears the batch match.
    const without = all.map((b) => (b.key === first[1].key ? { ...b, removed: true } : b));
    expect(findDuplicates(without, []).has(again[1].key)).toBe(false);
  });

  it("money in rows are never checked", () => {
    const rows = draftsFromScreenshot(lines(["Account History", "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", "06/10/2026 14:05 DUITNOW FROM ALI +RM50.00", "05/10/2026 PETRONAS -RM60.00"]), 1, null, "2026-10-07", taken);
    expect(findDuplicates(rows, []).size).toBe(0);
  });
});

describe("Add N Transactions", () => {
  it("counts drafts that are not removed, not skipped and valid; totals them", () => {
    const first = draftsFromScreenshot(lines(history), 1, null, "2026-10-07", taken);
    const again = draftsFromScreenshot(lines(history), 2, null, "2026-10-07", taken);
    const blank = manualDraft(3, null, taken); // no amount yet: invalid
    let all: BulkDraft[] = [...first, ...again, blank];
    let dups = findDuplicates(all, []);
    let s = summarize(3, all, dups, rules);
    expect(s).toMatchObject({ screenshots: 3, detected: 7, duplicates: 3, toAdd: 3, totalMinor: 1050 + 1290 + 1500 });
    expect(s.review).toBe(1);
    all = all.map((b) => (b.key === first[0].key ? { ...b, removed: true } : b.key === again[0].key ? { ...b, decision: "add" } : b.key === first[2].key ? { ...b, decision: "skip" } : b));
    dups = findDuplicates(all, []);
    s = summarize(3, all, dups, rules);
    // first[0] removed (so again[0] is no longer a duplicate), first[2] skipped; again[2] is still a duplicate of first[2].
    expect(s.toAdd).toBe(2);
    expect(s.totalMinor).toBe(1050 + 1290);
  });
});

describe("saving", () => {
  it("each draft is saved separately with its own expense, shares and receipt", async () => {
    const drafts = draftsFromScreenshot(lines(history), 1, shot(1), "2026-10-07", taken).slice(0, 2);
    const uploads: string[] = [];
    const saveExpense = vi.fn(async () => undefined);
    const ctx: SaveContext = {
      live: { expenses: [], shares: new Map(), movements: [], people: [], accounts: [], paymentMethods: [], allocations: [] },
      dataset: emptyDataset(),
      source: { uploadReceipt: async (_b: Blob, id: string) => { uploads.push(id); return `u/${id}/r.webp`; }, removeReceipt: async () => undefined } as unknown as SaveContext["source"],
      saveExpense, saveRecords: vi.fn(async () => undefined),
    };
    for (const b of drafts) await persistDraft(b.draft, ctx);
    expect(saveExpense).toHaveBeenCalledTimes(2);
    const records = saveExpense.mock.calls.map((c) => (c as unknown as [Expense])[0]);
    expect(new Set(records.map((r) => r.id)).size).toBe(2);
    expect(records.map((r) => [r.merchant, r.amountMinor, r.sourceType])).toEqual([["Grab", 1050, "screenshot"], ["McDonald's", 1290, "screenshot"]]);
    expect(records.map((r) => r.receiptPath)).toEqual(uploads.map((id) => `u/${id}/r.webp`));
    expect(records.every((r) => new Date(r.date).getDate() === 7 && new Date(r.date).getHours() === 12)).toBe(true);
  });
});

describe("runPool", () => {
  it("keeps order and never runs more than the limit at once", async () => {
    let running = 0;
    let peak = 0;
    const out = await runPool([5, 1, 3, 2, 4], 2, async (x) => {
      running++; peak = Math.max(peak, running);
      await new Promise((r) => setTimeout(r, x));
      running--;
      return x * 10;
    });
    expect(out).toEqual([50, 10, 30, 20, 40]);
    expect(peak).toBe(2);
  });
});

// Bulk Screenshot Import (Common/BusinessRules/bulk-import.md): screenshots → normal transaction drafts.
// Pure logic (no React, no OCR engine) so it can be tested; the page in app/(app)/add/bulk drives it.
import { fromInputs, toDateInput, toTimeInput } from "@/lib/domain/dates";
import type { DuplicateTarget } from "@/lib/domain/duplicates";
import { minorToInput, parseMinor } from "@/lib/domain/money";
import type { Dataset, Expense } from "@/lib/domain/types";
import { splitScreenshot } from "@/lib/ocr/bulk";
import { parseReceipt, type OcrLine } from "@/lib/ocr/parse";
import { deriveDraft, draftDuplicate, initialDraft, withType, type TransactionDraft } from "@/lib/transaction-draft";

/** At most this many screenshots per import (OCR runs in the browser). */
export const MAX_SCREENSHOTS = 30;
/** OCR jobs at a time. */
export const OCR_CONCURRENCY = 2;

export interface BulkDraft {
  key: string;
  /** 1-based number of the screenshot it came from. */
  screenshot: number;
  draft: TransactionDraft;
  /** Why this draft should be checked even when it can be saved (low confidence, failed / balance-only screenshot…). */
  reviewReason: string | null;
  removed: boolean;
  /** What to do with a possible duplicate. null = not decided, which means Skip. */
  decision: "add" | "skip" | null;
}

export type DuplicateMatch = { kind: "saved"; expense: Expense } | { kind: "batch"; key: string; screenshot: number };
export type DraftStatus = "ready" | "review" | "duplicate";

let seq = 0;
const newKey = () => (typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `d-${Date.now()}-${seq++}`);
const emptyLive = { shares: new Map(), people: [] };

const FAILED = /\b(failed|unsuccessful|declined|rejected|cancelled|canceled|reversed|tidak berjaya|gagal)\b/i;
const BALANCE = /\b(balance|baki|available)\b/i;
const LOW_CONFIDENCE = 0.6;

/** Local calendar date, yyyy-MM-dd. */
export const todayInput = (now = new Date()) => toDateInput(now);

function blank(receipt: Blob | null, fallbackDate: Date): TransactionDraft {
  return { ...initialDraft(emptyLive), date: toDateInput(fallbackDate), time: toTimeInput(fallbackDate), receipt };
}

/** A blank draft for a screenshot nothing was detected in ("Enter Manually"); keeps the screenshot as its receipt. */
export function manualDraft(screenshot: number, receipt: Blob | null, takenAt: Date): BulkDraft {
  return { key: newKey(), screenshot, draft: blank(receipt, takenAt), reviewReason: null, removed: false, decision: null };
}

/**
 * One screenshot's OCR lines → its drafts (never merged with other screenshots). A list gives one draft per row; a
 * single receipt gives the existing parseReceipt result; nothing detected gives no draft.
 * `takenAt` (the file's date) is used only when a single receipt shows no date of its own.
 */
export function draftsFromScreenshot(lines: OcrLine[], screenshot: number, receipt: Blob | null, importDate: string, takenAt: Date): BulkDraft[] {
  const text = lines.map((l) => l.text).join("\n");
  const confidence = lines.length ? lines.reduce((sum, l) => sum + l.confidence, 0) / lines.length : 0;
  const lowConfidence = confidence < LOW_CONFIDENCE ? "Text was hard to read — please check." : null;
  const failed = FAILED.test(text) ? "This screenshot may show a failed payment." : null;
  const split = splitScreenshot(lines, importDate);
  if (split.kind === "list") {
    return split.items.map((row) => {
      const base = blank(receipt, takenAt);
      const draft: TransactionDraft = row.direction === "in"
        ? { ...withType(base, "moneyIn"), amountText: minorToInput(row.amountMinor), merchant: row.merchant, note: row.merchant.slice(0, 200), date: row.date, time: row.time }
        : { ...base, amountText: minorToInput(row.amountMinor), merchant: row.merchant, date: row.date, time: row.time };
      return { key: newKey(), screenshot, draft, reviewReason: lowConfidence, removed: false, decision: null };
    });
  }
  const parsed = parseReceipt(lines);
  if (parsed.amountMinor === null && !parsed.merchant) return [];
  const base = blank(receipt, takenAt);
  const when = parsed.date ? new Date(parsed.date) : null;
  const draft: TransactionDraft = {
    ...base,
    amountText: parsed.amountMinor ? minorToInput(parsed.amountMinor) : "",
    merchant: parsed.merchant ?? "",
    date: when ? toDateInput(when) : base.date,
    time: when ? toTimeInput(when) : base.time,
    reference: parsed.reference ?? "",
    funding: parsed.funding !== "Unknown" ? parsed.funding : base.funding,
    ocrChannel: parsed.channel,
    ocrCategory: parsed.category,
  };
  const balanceOnly = BALANCE.test(text) && !parsed.merchant ? "This looks like a balance screen — please check." : null;
  const reviewReason = failed ?? balanceOnly ?? lowConfidence
    ?? (!parsed.amountConfident ? "Amount guessed — please check." : null)
    ?? (!when ? "No date on the screenshot — the file's date is used." : null);
  return [{ key: newKey(), screenshot, draft, reviewReason, removed: false, decision: null }];
}

const asTarget = (b: BulkDraft): DuplicateTarget => ({
  id: b.key, amountMinor: parseMinor(b.draft.amountText) ?? 0, merchant: b.draft.merchant.trim() || "Unknown",
  date: fromInputs(b.draft.date, b.draft.time), transactionReference: b.draft.reference.trim() || null,
});

/**
 * The existing duplicate check for every draft: first against the saved transactions, then against the drafts that
 * come before it in this batch (removed drafts don't count).
 */
export function findDuplicates(drafts: BulkDraft[], saved: readonly Expense[]): Map<string, DuplicateMatch> {
  const result = new Map<string, DuplicateMatch>();
  const earlier: BulkDraft[] = [];
  for (const b of drafts) {
    if (b.removed) continue;
    const savedMatch = draftDuplicate(b.draft, saved);
    if (savedMatch) result.set(b.key, { kind: "saved", expense: savedMatch });
    else {
      const targets = earlier.filter((e) => e.draft.type === "expense").map(asTarget);
      const batchMatch = draftDuplicate(b.draft, targets);
      if (batchMatch) result.set(b.key, { kind: "batch", key: batchMatch.id, screenshot: earlier.find((e) => e.key === batchMatch.id)!.screenshot });
    }
    earlier.push(b);
  }
  return result;
}

type Rules = Pick<Dataset, "classificationRules" | "channelRules">;

export function draftStatus(b: BulkDraft, duplicate: DuplicateMatch | undefined, rules: Rules): DraftStatus {
  if (duplicate && b.decision !== "add") return "duplicate";
  const derived = deriveDraft(b.draft, rules);
  if (!derived.valid || !b.draft.merchant.trim() || b.reviewReason) return "review";
  return "ready";
}

/** Will this draft be saved by "Add N Transactions"? Not removed, not skipped (a duplicate defaults to Skip), valid. */
export function willAdd(b: BulkDraft, duplicate: DuplicateMatch | undefined, rules: Rules): boolean {
  if (b.removed) return false;
  if (b.decision === "skip") return false;
  if (duplicate && b.decision !== "add") return false;
  return deriveDraft(b.draft, rules).valid;
}

export interface BulkSummary { screenshots: number; detected: number; ready: number; review: number; duplicates: number; toAdd: number; totalMinor: number }

export function summarize(screenshots: number, drafts: BulkDraft[], duplicates: Map<string, DuplicateMatch>, rules: Rules): BulkSummary {
  const live = drafts.filter((b) => !b.removed);
  const statuses = live.map((b) => draftStatus(b, duplicates.get(b.key), rules));
  const adding = live.filter((b) => willAdd(b, duplicates.get(b.key), rules));
  return {
    screenshots,
    detected: live.length,
    ready: statuses.filter((s) => s === "ready").length,
    review: statuses.filter((s) => s === "review").length,
    duplicates: statuses.filter((s) => s === "duplicate").length,
    toAdd: adding.length,
    totalMinor: adding.reduce((sum, b) => sum + (parseMinor(b.draft.amountText) ?? 0), 0),
  };
}

/** Runs `worker` over `items` with at most `limit` running at once; results keep the input order. */
export async function runPool<T, R>(items: readonly T[], limit: number, worker: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const lane = async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await worker(items[i], i);
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, lane));
  return results;
}

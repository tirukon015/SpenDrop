// Bulk Import: decides whether one screenshot is a single receipt or a list of transactions (a payment / bank
// history), following Common/BusinessRules/bulk-import.md and its vectors. Text only; conservative: anything that
// isn't clearly a list is a single receipt for the existing parseReceipt. Port of Android ScreenshotSplitter.
import type { OcrLine } from "./parse";

export interface BulkRow {
  merchant: string;
  /** Always positive, in sen. */
  amountMinor: number;
  /** "in" for a leading +, otherwise "out". */
  direction: "in" | "out";
  /** Local calendar date, yyyy-MM-dd. */
  date: string;
  /** HH:mm (12:00 when the row has no time). */
  time: string;
}

export type SplitResult = { kind: "single"; items: [] } | { kind: "list"; items: BulkRow[] };

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const AMOUNT = /(?<![\w.,])([+-])?\s?(?:(?:RM|MYR)\s?)?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d.])/gi;
const DATE_DMY = /\b(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})\b/;
const DATE_ISO = /\b(\d{4})-(\d{2})-(\d{2})\b/;
const DATE_DMON = /\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?(?:\s+(\d{4}))?\b/i;
const TIME = /\b(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?\b/;
const SEPARATORS = new Set(["—", "–", "-", "|", "·", "•", ":"]);
const EDGE = /^[\s—–\-|·•:]+|[\s—–\-|·•:]+$/g;
const SINGLE_MARKERS = ["payment successful", "transaction successful", "successful", "receipt", "total", "ref no", "reference"];

const pad = (n: number) => String(n).padStart(2, "0");
const iso = (y: number, m: number, d: number) => `${y}-${pad(m)}-${pad(d)}`;

/** A real calendar date (rejects 31/02 etc.), as yyyy-MM-dd; null otherwise. */
function calendarDate(y: number, m: number, d: number): string | null {
  if (m < 1 || m > 12 || d < 1) return null;
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return d <= days ? iso(y, m, d) : null;
}

function findDate(line: string, importDate: string): { date: string; text: string } | null {
  let m = DATE_ISO.exec(line);
  if (m) { const d = calendarDate(+m[1], +m[2], +m[3]); return d ? { date: d, text: m[0] } : null; }
  m = DATE_DMY.exec(line);
  if (m) {
    const y = m[3].length < 3 ? 2000 + Number(m[3]) : Number(m[3]);
    const d = calendarDate(y, +m[2], +m[1]);
    return d ? { date: d, text: m[0] } : null;
  }
  m = DATE_DMON.exec(line);
  if (m) {
    const month = MONTHS.indexOf(m[2].toLowerCase().slice(0, 3)) + 1;
    const explicit = m[3] ? Number(m[3]) : null;
    const year = explicit ?? Number(importDate.slice(0, 4));
    let d = calendarDate(year, month, +m[1]);
    if (!d) return null;
    if (explicit === null && d > importDate) d = calendarDate(year - 1, month, +m[1]);
    return d ? { date: d, text: m[0] } : null;
  }
  return null;
}

/** One OCR line → a transaction row, or null when the line isn't one (see bulk-import.md §1). */
export function parseRow(line: string, importDate: string): BulkRow | null {
  const amounts = [...line.matchAll(AMOUNT)];
  if (amounts.length !== 1) return null;
  const a = amounts[0];
  const found = findDate(line, importDate);
  if (!found) return null;
  const start = a.index ?? 0;
  let rest = (line.slice(0, start) + line.slice(start + a[0].length)).replace(found.text, " ");
  const t = TIME.exec(rest);
  let time = "12:00";
  if (t) {
    let h = Number(t[1]);
    const min = Number(t[2]);
    const ampm = (t[3] ?? "").toLowerCase();
    if (ampm === "pm" && h < 12) h += 12;
    if (ampm === "am" && h === 12) h = 0;
    if (h >= 0 && h <= 23 && min >= 0 && min <= 59) time = `${pad(h)}:${pad(min)}`;
    rest = rest.slice(0, t.index) + rest.slice(t.index + t[0].length);
  }
  const merchant = rest.split(/\s+/).filter((w) => w && !SEPARATORS.has(w)).join(" ").replace(EDGE, "").trim();
  if ((merchant.match(/\p{L}/gu) ?? []).length < 2) return null;
  const amountMinor = Number(a[2].replace(/,/g, "")) * 100 + Number(a[3]);
  if (!(amountMinor > 0)) return null;
  return { merchant, amountMinor, direction: a[1] === "+" ? "in" : "out", date: found.date, time };
}

/**
 * Classifies one screenshot's OCR lines. `importDate` (yyyy-MM-dd, local) is the reference for dates without a year.
 * "single": the existing parseReceipt handles the whole screenshot; "list": one draft per row.
 */
export function splitScreenshot(input: (OcrLine | string)[], importDate: string): SplitResult {
  const clean = input.map((l) => (typeof l === "string" ? l : l.text).trim()).filter(Boolean);
  const rows = clean.map((l) => parseRow(l, importDate)).filter((r): r is BulkRow => r !== null);
  if (rows.length < 2) return { kind: "single", items: [] };
  const lower = clean.join("\n").toLowerCase();
  if (rows.length === 2 && SINGLE_MARKERS.some((m) => lower.includes(m))) return { kind: "single", items: [] };
  return { kind: "list", items: rows };
}

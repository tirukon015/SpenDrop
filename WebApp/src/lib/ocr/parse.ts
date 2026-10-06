// Receipt / screenshot text → suggested fields. Always suggestions: the user reviews everything before saving.
import type { CategoryId, PaymentChannelId } from "@/lib/domain/types";
import { detectFunding, suggestCategory, suggestChannel, type Suggestion } from "./classify";

export interface OcrLine { text: string; confidence: number }

export interface ParsedReceipt {
  amountMinor: number | null;
  merchant: string | null;
  date: string | null;
  reference: string | null;
  funding: string;
  channel: Suggestion<PaymentChannelId>;
  category: Suggestion<CategoryId>;
  /** Overall: true when the amount was found next to a total/amount label or as the only money value. */
  amountConfident: boolean;
}

const MONEY = /(?:RM|MYR)\s*-?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))/gi;
const BARE_MONEY = /^-?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})$/;
const SKIP_AMOUNT = /balance|baki|limit|available|cashback|points|reward|fee waived|previous/i;
const TOTAL_LABEL = /total|amount|jumlah|paid|payment|grand/i;
const MERCHANT_LABEL = /^(merchant(?:\s*name)?|recipient(?:['’]s)?(?:\s*name)?|beneficiary(?:['’]s)?(?:\s*name)?|paid\s*to|to|pay\s*to|payee|receiver(?:['’]s)?(?:\s*name)?|store)\s*:?\s*(.*)$/i;
const REFERENCE_LABEL = /(reference(?:\s*(?:id|no\.?|number))?|ref(?:\.|erence)?\s*no\.?|transaction\s*(?:no\.?|id|number)|approval\s*code|receipt\s*no\.?|octo\s*reference\s*no\.?)\s*:?\s*(.*)$/i;
const NOT_MERCHANT = /^(successful|success|payment|transaction|details|receipt|rm|myr|date|time|status|approved|completed)\b/i;
const MONTHS: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };

const toMinor = (s: string) => Math.round(Number(s.replace(/,/g, "")) * 100);

function findDate(text: string): string | null {
  let m = /(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?:[ ,]+(\d{1,2}):(\d{2})\s*(am|pm)?)?/i.exec(text);
  if (m) {
    let h = m[4] ? Number(m[4]) : 12;
    if (m[6]?.toLowerCase() === "pm" && h < 12) h += 12;
    if (m[6]?.toLowerCase() === "am" && h === 12) h = 0;
    const d = new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]), h, m[5] ? Number(m[5]) : 0);
    if (!Number.isNaN(d.getTime()) && Number(m[2]) <= 12) return d.toISOString();
  }
  m = /(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{4})(?:[ ,]+(\d{1,2}):(\d{2})\s*(am|pm)?)?/i.exec(text);
  if (m) {
    let h = m[4] ? Number(m[4]) : 12;
    if (m[6]?.toLowerCase() === "pm" && h < 12) h += 12;
    if (m[6]?.toLowerCase() === "am" && h === 12) h = 0;
    return new Date(Number(m[3]), MONTHS[m[2].toLowerCase().slice(0, 3)], Number(m[1]), h, m[5] ? Number(m[5]) : 0).toISOString();
  }
  return null;
}

export function parseReceipt(input: OcrLine[] | string[]): ParsedReceipt {
  const lines: OcrLine[] = input.map((l) => (typeof l === "string" ? { text: l, confidence: 1 } : l)).map((l) => ({ ...l, text: l.text.trim() })).filter((l) => l.text);
  const fullText = lines.map((l) => l.text).join("\n");
  // Amount: prefer money next to a total/amount label; skip balances and limits.
  const candidates: { minor: number; score: number }[] = [];
  lines.forEach((line, i) => {
    if (SKIP_AMOUNT.test(line.text)) return;
    const values = [...line.text.matchAll(MONEY)].map((m) => toMinor(m[1]));
    const bare = BARE_MONEY.exec(line.text);
    if (bare) values.push(toMinor(bare[1]));
    for (const minor of values) {
      if (minor <= 0) continue;
      const near = TOTAL_LABEL.test(line.text) || (i > 0 && TOTAL_LABEL.test(lines[i - 1].text));
      candidates.push({ minor, score: (near ? 2 : 0) + (/RM|MYR/i.test(line.text) ? 1 : 0) + (i < lines.length / 2 ? 0.5 : 0) });
    }
  });
  candidates.sort((a, b) => b.score - a.score || b.minor - a.minor);
  const distinct = new Set(candidates.map((c) => c.minor));
  const amountMinor = candidates[0]?.minor ?? null;

  let merchant: string | null = null;
  let reference: string | null = null;
  lines.forEach((line, i) => {
    const m = MERCHANT_LABEL.exec(line.text);
    if (!merchant && m) {
      const value = (m[2] || lines[i + 1]?.text || "").trim();
      if (value && !NOT_MERCHANT.test(value) && !/\d{6,}/.test(value) && !MONEY.test(value)) merchant = value;
      MONEY.lastIndex = 0;
    }
    const r = REFERENCE_LABEL.exec(line.text);
    if (!reference && r) {
      const value = (r[2] || lines[i + 1]?.text || "").trim();
      if (/\d/.test(value) && value.length <= 40) reference = value.split(/\s+/)[0];
    }
  });
  // Channel evidence only from lines read with reasonable confidence (blurry text is not evidence).
  const evidence = lines.filter((l) => l.confidence >= 0.5).map((l) => l.text).join("\n");
  return {
    amountMinor,
    merchant,
    date: findDate(fullText),
    reference,
    funding: detectFunding(fullText),
    channel: suggestChannel(evidence),
    category: suggestCategory(merchant, fullText),
    amountConfident: candidates.length > 0 && (candidates[0].score >= 2 || distinct.size === 1),
  };
}

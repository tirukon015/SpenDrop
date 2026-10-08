// Grounding check for model-written answers: every amount, percentage and transaction count in the text must
// appear in a tool result from this request. If not, the model's text is discarded and SpenDrop's deterministic
// answer is shown instead (the model explains verified results; it never produces financial facts).
import { CATEGORIES } from "@/lib/domain/constants";
import type { ExecutedTool } from "./registry";
import { normalizeText } from "./tools";

const MONEY = /(?:\bRM|\bMYR|\bUSD|\bSGD|\bGBP|\bEUR|\bBDT|US\$|S\$|\$|£|€)\s?-?\d[\d,]*(?:\.\d+)?/gi;
const PERCENT = /(-?\d+(?:\.\d+)?)\s?%/g;
const COUNT = /\b(\d+)\s+(?:transactions?|payments?|purchases?)\b/gi;
const CLAIMS_DATA = /\b(i (?:checked|looked|searched|found|calculated|analy[sz]ed|reviewed)|based on your (?:data|records|transactions)|you spent|you paid|your (?:spending|total) (?:was|is))\b/i;

interface Allowed { minor: Set<number>; pct: number[]; counts: Set<number> }

function collect(value: unknown, key: string, out: Allowed) {
  if (Array.isArray(value)) {
    out.counts.add(value.length);
    for (const v of value) collect(v, key, out);
    return;
  }
  if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) collect(v, k, out);
    return;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) return;
  if (/Minor$/.test(key)) out.minor.add(Math.abs(Math.round(value)));
  else if (/pct|Pct/.test(key)) out.pct.push(Math.abs(value));
  else if (/count|Count|total|people/.test(key)) out.counts.add(value);
  else if (/^amount(Min|Max)$|^targetAmount$/.test(key)) out.minor.add(Math.round(value * 100));
}

export function allowedFigures(executed: ExecutedTool[]): Allowed {
  const out: Allowed = { minor: new Set(), pct: [], counts: new Set() };
  for (const e of executed) {
    collect(e.args, "args", out);
    if (e.result.ok) collect(e.result.data, "data", out);
  }
  return out;
}

const toMinor = (text: string) => {
  const n = Number(text.replace(/[^\d.-]/g, ""));
  return Number.isFinite(n) ? Math.abs(Math.round(n * 100)) : NaN;
};

export interface GroundingResult { ok: boolean; problems: string[] }

/**
 * @param knownNames the user's own merchant / account names: any of them mentioned in the answer must appear in a
 *   tool result or argument (stops "your Starbucks spending rose by RM 996" when the tool never looked at Starbucks).
 */
export function verifyGrounding(text: string, executed: ExecutedTool[], knownNames: string[] = []): GroundingResult {
  const allowed = allowedFigures(executed);
  const problems: string[] = [];
  const successful = executed.filter((e) => e.result.ok);
  for (const m of text.match(MONEY) ?? []) {
    if (!allowed.minor.has(toMinor(m))) problems.push(`amount ${m}`);
  }
  for (const m of text.matchAll(PERCENT)) {
    const v = Math.abs(Number(m[1]));
    if (!allowed.pct.some((p) => Math.abs(p - v) <= 0.15)) problems.push(`percentage ${m[0]}`);
  }
  for (const m of text.matchAll(COUNT)) {
    if (!allowed.counts.has(Number(m[1]))) problems.push(`count ${m[0]}`);
  }
  const evidence = ` ${normalizeText(executed.map((e) => JSON.stringify([e.args, e.result.ok ? e.result.data : null])).join(" "))} `;
  const said = ` ${normalizeText(text)} `;
  for (const name of [...knownNames, ...CATEGORIES.map((c) => c.id)]) {
    const n = normalizeText(name);
    if (n.length < 3 || !said.includes(` ${n} `)) continue;
    if (!evidence.includes(` ${n} `)) problems.push(`name “${name}” not in any tool result`);
  }
  // Claims of having looked at the data when no tool actually returned any.
  if (successful.length === 0 && CLAIMS_DATA.test(text)) problems.push("claims to have checked data without a tool call");
  return { ok: problems.length === 0, problems };
}

/** Plain text only: strip markdown emphasis/headers/links and any HTML-looking tags. */
export function toPlainText(text: string): string {
  return text
    .replace(/<[^>]*>/g, "")
    .replace(/\*\*|__|`/g, "")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, 2000);
}

// Merchant / entity resolution: which of the user's OWN merchant names does a question refer to?
//
// People rarely type a merchant exactly as it was recorded: "bijoy" for BIJOYSHARIARALAMIN, "abc mart" for ABC-MART-001,
// "mango" for MANGO CAFE CYBERJAYA, "starbuck" for Starbucks. This resolver compares the words of a question with the
// user's own merchant names (never anyone else's — the list comes from the user-scoped repository) using a
// deterministic score:
//
//   exact      the whole name, ignoring case / spacing / punctuation / accents          100
//   word       a whole word (or run of words) of the name                                 90
//   prefix     the name, or one of its words, starts with the reference (≥ 3 letters)      80
//   substring  the reference appears inside the name (≥ 5 letters)                          70
//   fuzzy      one small typo against the start of a word / the name (≥ 4 letters)          60
//
// Weaker references never match (no single letters, no common words), a stronger match always beats a weaker one,
// and several close candidates are reported as ambiguous rather than silently combined. The stored names are never
// changed: normalisation is only used for comparing.

export type MatchQuality = "exact" | "word" | "prefix" | "substring" | "fuzzy";
const SCORE: Record<MatchQuality, number> = { exact: 100, word: 90, prefix: 80, substring: 70, fuzzy: 60 };
export const MIN_SCORE = SCORE.fuzzy;

/** Lowercase, accents removed, every run of non-letters/digits → one space. "Bijoy-Sharia_R  Al'Amin" → "bijoy sharia r al amin". */
export function normalizeName(s: string): string {
  return s.normalize("NFKD").replace(/\p{M}+/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

/** Levenshtein distance, stopping early once it exceeds `max`. */
function distance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let best = i;
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      best = Math.min(best, cur[j]);
    }
    if (best > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/** How well a reference (one or more words the user typed) matches one stored merchant name; null = not at all. */
export function matchQuality(reference: string, merchant: string): MatchQuality | null {
  const ref = normalizeName(reference);
  const refC = ref.replace(/ /g, "");
  if (refC.length < 3 || /^\d+$/.test(refC)) return null;
  const name = normalizeName(merchant);
  const nameC = name.replace(/ /g, "");
  if (!nameC) return null;
  if (refC === nameC) return "exact";
  if (` ${name} `.includes(` ${ref} `)) return "word";
  const words = name.split(" ");
  if (nameC.startsWith(refC) || words.some((w) => w.length > refC.length && w.startsWith(refC))) return "prefix";
  // Inside a word only from 5 letters ("sharia", "alamin"): shorter inner fragments are noise ("hope" in "Shopee").
  if (refC.length >= 5 && nameC.includes(refC)) return "substring";
  // A small typo ("bijoi", "bijoyy", "starbuck", "jaya grocr"): compare with the start of the name and of each word.
  if (refC.length >= 4) {
    const max = refC.length >= 8 ? 2 : 1;
    const starts = [nameC, ...words.filter((w) => w.length >= 3)];
    for (const s of starts)
      for (const len of [refC.length - 1, refC.length, refC.length + 1])
        if (len >= 3 && len <= s.length && distance(refC, s.slice(0, len), max) <= max) return "fuzzy";
  }
  // Several words that each match the same name ("bijoy alamin" → BIJOY SHARIAR AL AMIN / BIJOYSHARIARALAMIN).
  const parts = ref.split(" ").filter((p) => p.length >= 3);
  if (parts.length >= 2) {
    const qs = parts.map((p) => matchQuality(p, merchant));
    if (qs.every(Boolean)) return qs.reduce((worst, q) => (SCORE[q!] < SCORE[worst!] ? q : worst))!;
  }
  return null;
}

export interface Candidate { name: string; quality: MatchQuality; score: number }

/** The user's merchants that match a reference, best first (ties: more transactions-like = shorter name first). */
export function candidatesFor(reference: string, merchants: readonly string[]): Candidate[] {
  const seen = new Set<string>();
  const out: Candidate[] = [];
  for (const name of merchants) {
    const key = normalizeName(name);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    const q = matchQuality(reference, name);
    if (q) out.push({ name, quality: q, score: SCORE[q] });
  }
  return out.sort((a, b) => b.score - a.score || a.name.length - b.name.length || a.name.localeCompare(b.name));
}

export type Resolution =
  | { kind: "match"; reference: string; names: string[]; quality: MatchQuality }
  | { kind: "ambiguous"; reference: string; names: string[] };

/**
 * Pick the merchant(s) a reference means.
 *  • exact / whole-word matches: all of them (e.g. "Shopee" → Shopee and Shopee Food — the answer discloses both)
 *  • otherwise one clear winner (one candidate, or 15+ points ahead of the next)
 *  • otherwise every candidate when the user asked for them all ("similar names", "anything with …")
 *  • otherwise ambiguous: the user is asked which one
 */
export function decide(reference: string, candidates: Candidate[], wantsAll: boolean): Resolution | null {
  if (candidates.length === 0) return null;
  const top = candidates[0];
  if (top.score >= SCORE.word) {
    const strong = candidates.filter((c) => c.score >= SCORE.word);
    return { kind: "match", reference, names: strong.map((c) => c.name), quality: top.quality };
  }
  if (candidates.length === 1 || top.score - candidates[1].score >= 15) return { kind: "match", reference, names: [top.name], quality: top.quality };
  const close = candidates.filter((c) => top.score - c.score < 15);
  if (wantsAll) return { kind: "match", reference, names: candidates.map((c) => c.name), quality: top.quality };
  return { kind: "ambiguous", reference, names: close.slice(0, 6).map((c) => c.name) };
}

/** Words in a question that are never (part of) a merchant reference on their own, in any of the supported languages. */
const STOP = new Set((
  // English
  "i me my mine you your we our it its is am are was were be been do did does have has had the a an and or but on in at of for to from with by about as " +
  "into than then that these those there here so if not no yes ok okay please can could would should will just also how much many what where when which why " +
  "who spend spent spending money total amount cost costs paid pay paying bought buy this last next week weeks month months year years today yesterday " +
  "tomorrow day days all more less lot bro now lately recently usually ever again overall show list find search transaction transactions payment payments " +
  "purchase purchases receipt receipts went gone go goes number times time compare vs normal usual average any some only really very too give tell me " +
  "similar name names named like related relating containing contains contain matching match matches anything something called merchant merchants shop " +
  "shops store stores place places seller vendor person people " +
  // Banglish
  "ami amar tumi tomar ki koto kototuku khoroch khoroc khorch hoise hoyeche hoyse gelo gese geche gesilo dilam disi diyechi korchi korsi korlam kinlam " +
  "dekhao dekhaw dekhan er e te ke r theke jonno niye shathe sathe gula gulo ta ti abar ei oi kal aaj week mash bochor naki " +
  // Malay
  "saya aku awak berapa belanja beli bayar dekat kat di untuk dengan dari ke yang ni ini itu tu semua transaksi bulan minggu hari semalam tahun kali " +
  "guna pakai habis tunjuk senarai"
).split(" "));

/** Banglish case endings glued to a name ("bijoyer", "bijoyke", "bijoyte"). */
const stems = (w: string) => [w, ...(/^(.{4,}?)(er|re|ke|te|e|r)$/.exec(w)?.slice(1, 2) ?? [])];

export interface ResolveOptions {
  /** Words already understood as something else (a category, account, channel, period). */
  exclude?: string[];
}

/**
 * Find the merchant a question refers to. Tries every run of 1–3 consecutive content words and keeps the best
 * match (longer references win ties, so "bijoy sharia" beats "bijoy"). Returns null when nothing matches.
 */
export function resolveMerchant(question: string, merchants: readonly string[], opts: ResolveOptions = {}): Resolution | null {
  if (merchants.length === 0) return null;
  const excluded = new Set((opts.exclude ?? []).flatMap((e) => normalizeName(e).split(" ")).filter(Boolean));
  const tokens = normalizeName(question).split(" ").filter(Boolean);
  const wantsAll = /\b(similar|like|related|containing|contains|anything|everything|all|any|names?|matching|kind of)\b/.test(normalizeName(question));
  type Ref = { text: string; cands: Candidate[] };
  let best: Ref | null = null;
  const better = (r: Ref) => {
    if (!best) return true;
    const a = r.cands[0].score, b = best.cands[0].score;
    return a > b || (a === b && r.text.length > best.text.length);
  };
  for (let i = 0; i < tokens.length; i++) {
    for (let n = 1; n <= 3 && i + n <= tokens.length; n++) {
      const run = tokens.slice(i, i + n);
      if (run.some((w) => excluded.has(w)) || STOP.has(run[0]) || STOP.has(run[run.length - 1])) continue;
      const variants = n === 1 ? stems(run[0]) : [run.join(" ")];
      for (const text of variants) {
        const cands = candidatesFor(text, merchants);
        // A short reference must at least start a word of the name; typos need ≥ 4 letters (enforced in matchQuality).
        if (cands.length && better({ text, cands })) best = { text, cands };
      }
    }
  }
  if (!best) {
    // A whole merchant name typed as one string of stop-words is still an exact name ("The Coffee"?) — check exact names.
    const exact = merchants.filter((m) => normalizeName(m).length >= 3 && ` ${tokens.join(" ")} `.includes(` ${normalizeName(m)} `));
    return exact.length ? { kind: "match", reference: normalizeName(exact[0]), names: exact, quality: "exact" } : null;
  }
  const b = best as Ref;
  return decide(b.text, b.cands, wantsAll);
}

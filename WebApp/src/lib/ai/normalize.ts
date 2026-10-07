// Natural-language normalisation: turns informal English, Malay, Banglish (Bengali in Latin letters), mixed
// language, slang and typos into one canonical English form the planner understands. Deterministic, local and
// free — "food e koto khoroch hoise?", "berapa saya belanja makanan minggu ni?" and "how mch i spnd on fod" all
// become "how much spent food …". The original text is kept for names (merchants) and amounts.
//
// Rules: phrases are replaced before single words; typo correction only targets SpenDrop's own vocabulary (domain
// words + the user's merchants/accounts), never ordinary English words, never words with digits, never short words.

export interface Understanding {
  /** Canonical lowercase English the planner reads. */
  text: string;
  /** Typo fixes made ("mch" → "much"). */
  corrections: { from: string; to: string }[];
  /** Words recognised from other languages or slang ("khoroch" → "spent"). */
  translations: { from: string; to: string }[];
  /** Language signals seen, for evaluation/diagnostics. */
  languages: ("en" | "ms" | "bn-latn" | "bn")[];
}

// Phrase → canonical replacement (multi-word first; matched on word boundaries, lowercase).
const PHRASES: [RegExp, string, Understanding["languages"][number]][] = [
  // Banglish
  [/\bkoto\s+taka\b/g, "how much", "bn-latn"],
  [/\b(khoroch|khorch|khoros|khorcha)\s+(hoise|hoyeche|hoyse|korchi|korsi|korlam|korechi|holo|hoilo|koresi|kortesi|kortechi)\b/g, "spent", "bn-latn"],
  [/\b(ei|ai)\s+(week|shoptah|soptah|soptahe|shoptahe)\b(\s+e\b)?/g, "this week", "bn-latn"],
  [/\b(gotho|goto|gato|ager|last)\s+(week|shoptah|soptah|soptahe)\s+e\b/g, "last week", "bn-latn"],
  [/\b(gotho|goto|gato|ager)\s+(week|shoptah|soptah|soptahe)\b/g, "last week", "bn-latn"],
  [/\b(ei|ai)\s+(mash|mashe|mas|month)\b(\s+e\b)?/g, "this month", "bn-latn"],
  [/\b(gotho|goto|gato|ager)\s+(mash|mashe|mas|month)\b/g, "last month", "bn-latn"],
  [/\bkhaoa\s+dawa\b|\bkhawa\s+dawa\b|\bkhaowa\s+dawa\b/g, "food", "bn-latn"],
  [/\b(sob|shob)\s*(cheye|chaite|theke)\s+(boro|beshi)\b/g, "biggest", "bn-latn"],
  [/\b(eto|etto|onek)\s+beshi\b/g, "so much", "bn-latn"],
  [/\bonno\s+(user|lok|manush)(er)?\b/g, "other users", "bn-latn"],
  [/\b(er\s+)?(pichone|pichhone|jonno|jonne)\b/g, " on ", "bn-latn"],
  // Frequency ("koto bar", "kotobar", "berapa kali") → "how many times"
  [/\b(koto|koy|kato)\s*bar\b|\bkotobar\b|\bkoybar\b/g, "how many times", "bn-latn"],
  [/\bberapa\s+kali\b/g, "how many times", "ms"],
  // Trend: "bere jacche / bere gese / beshi hocche" → increasing; "kome jacche / kom hocche" → decreasing
  [/\bbere\s+(jacche|jacchhe|gese|geche|gelo|jay)\b|\bbeshi\s+(hocche|hoche|hoitese|hoye jacche)\b/g, "increasing", "bn-latn"],
  [/\bkome\s+(jacche|gese|geche|gelo)\b|\bkom\s+(hocche|hoche|hoitese)\b/g, "decreasing", "bn-latn"],
  // Malay ("apa khabar" is "how are you" — not the Banglish "khabar" = food)
  [/\bapa\s+khabar\b/g, "how are you", "ms"],
  [/\bminggu\s+(ini|ni)\b/g, "this week", "ms"],
  [/\bminggu\s+(lepas|lalu|sudah)\b/g, "last week", "ms"],
  [/\bbulan\s+(ini|ni)\b/g, "this month", "ms"],
  [/\bbulan\s+(lepas|lalu|sudah)\b/g, "last month", "ms"],
  [/\bhari\s+(ini|ni)\b/g, "today", "ms"],
  [/\btahun\s+(ini|ni)\b/g, "this year", "ms"],
  [/\btahun\s+(lepas|lalu)\b/g, "last year", "ms"],
  [/\bbarang\s+dapur\b/g, "groceries", "ms"],
  [/\bberapa\s+banyak\b/g, "how much", "ms"],
  [/\b(banyak\s+sangat|terlalu\s+banyak|banyak\s+gila)\b/g, "so much", "ms"],
  [/\b(paling\s+(besar|mahal))\b/g, "biggest", "ms"],
  [/\b(pengguna|orang|user)\s+lain\b/g, "other users", "ms"],
  [/\babaikan\s+(semua\s+)?arahan(\s+(sebelumnya|sebelum\s+ini|tadi))?\b/g, "ignore previous instructions", "ms"],
  // English slang / informal
  [/\b(money|cash|duit|taka)\s+(gone|went)\b/g, "spent", "en"],
  [/\b(eating|eat)\s+out\b/g, "food", "en"],
  // "eating up / into / away" is an idiom about money, not food
  [/\beating(?=\s+(up|into|away|through)\b)/g, "eats", "en"],
  [/\bhow\s+much\s+money\b/g, "how much", "en"],
];

// Single word → canonical word ("" = drop it).
const WORDS: Record<string, [string, Understanding["languages"][number]]> = {
  // Banglish
  koto: ["how much", "bn-latn"], khoroch: ["spent", "bn-latn"], khorch: ["spent", "bn-latn"], khoros: ["spent", "bn-latn"], khorcha: ["spent", "bn-latn"],
  gelo: ["spent", "bn-latn"], geche: ["spent", "bn-latn"], gese: ["spent", "bn-latn"], gesilo: ["spent", "bn-latn"],
  uraisi: ["spent", "bn-latn"], uraichi: ["spent", "bn-latn"], urailam: ["spent", "bn-latn"], urechi: ["spent", "bn-latn"],
  korchi: ["", "bn-latn"], korsi: ["", "bn-latn"], hoise: ["", "bn-latn"], hoyeche: ["", "bn-latn"], korlam: ["", "bn-latn"],
  khabar: ["food", "bn-latn"], khawa: ["food", "bn-latn"], khaoa: ["food", "bn-latn"], khana: ["food", "bn-latn"], bazar: ["groceries", "bn-latn"],
  aaj: ["today", "bn-latn"], ajke: ["today", "bn-latn"], gotokal: ["yesterday", "bn-latn"], kalke: ["yesterday", "bn-latn"],
  keno: ["why", "bn-latn"], kon: ["which", "bn-latn"], konta: ["which", "bn-latn"], kothay: ["where", "bn-latn"], dekhao: ["show", "bn-latn"], dekhaw: ["show", "bn-latn"],
  beshi: ["more", "bn-latn"], kom: ["less", "bn-latn"], ami: ["i", "bn-latn"], amar: ["my", "bn-latn"], shob: ["all", "bn-latn"], sob: ["all", "bn-latn"],
  e: ["", "bn-latn"], te: ["", "bn-latn"], er: ["", "bn-latn"], ki: ["", "bn-latn"], to: ["to", "en"],
  // Malay
  berapa: ["how much", "ms"], belanja: ["spent", "ms"], perbelanjaan: ["spending", "ms"], spend: ["spend", "en"],
  makan: ["food", "ms"], makanan: ["food", "ms"], minum: ["food", "ms"], pengangkutan: ["transport", "ms"], minyak: ["fuel", "ms"],
  saya: ["i", "ms"], aku: ["i", "ms"], untuk: ["on", "ms"], pada: ["on", "ms"], kat: ["at", "ms"], dekat: ["at", "ms"],
  kenapa: ["why", "ms"], tunjuk: ["show", "ms"], tunjukkan: ["show", "ms"], lebih: ["more", "ms"], kurang: ["less", "ms"],
  cuaca: ["weather", "ms"], esok: ["tomorrow", "ms"], guna: ["using", "ms"], pakai: ["using", "ms"], transaksi: ["transactions", "ms"], adakah: ["", "ms"],
  hocche: ["", "bn-latn"], hoche: ["", "bn-latn"], ta: ["", "bn-latn"],
  duit: ["money", "ms"], banyak: ["a lot", "ms"], dengan: ["with", "ms"], banding: ["compare", "ms"], bandingkan: ["compare", "ms"],
  koi: ["where", "bn-latn"], kemon: ["how", "bn-latn"], kmn: ["how", "bn-latn"], oi: ["that", "bn-latn"], kal: ["yesterday", "bn-latn"], jay: ["goes", "bn-latn"], jacche: ["goes", "bn-latn"],
  shathe: ["with", "bn-latn"], sathe: ["with", "bn-latn"], songe: ["with", "bn-latn"], taka: ["money", "bn-latn"], naki: ["", "bn-latn"], wang: ["money", "ms"], semalam: ["yesterday", "ms"], ni: ["", "ms"], ke: ["", "ms"], dah: ["", "ms"], sudah: ["", "ms"],
  // English slang, filler and abbreviations
  burn: ["spend", "en"], burned: ["spent", "en"], burnt: ["spent", "en"], blew: ["spent", "en"], blow: ["spend", "en"], splurged: ["spent", "en"],
  dropped: ["spent", "en"], wk: ["week", "en"], wks: ["weeks", "en"], mth: ["month", "en"], mnth: ["month", "en"], yday: ["yesterday", "en"], yesday: ["yesterday", "en"], yestday: ["yesterday", "en"], ystrdy: ["yesterday", "en"], ystday: ["yesterday", "en"],
  tdy: ["today", "en"], u: ["you", "en"], ur: ["your", "en"], pls: ["", "en"], plz: ["", "en"], bro: ["", "en"], bruh: ["", "en"], dude: ["", "en"],
  lah: ["", "ms"], la: ["", "ms"], leh: ["", "ms"], meh: ["", "ms"], yaar: ["", "en"], eating: ["food", "en"], grub: ["food", "en"],
};

// Word stems (Banglish verb forms, Malay affixes): one rule covers every conjugation ("uraisi", "uraitesi",
// "urailam"…). Applied to single words that the tables above don't already cover.
const STEMS: [RegExp, string, Understanding["languages"][number]][] = [
  [/^urai\w*$|^ura(chi|cchi|tesi|lam|si)$/, "spent", "bn-latn"],
  // bar- / bere = increase, kom- = decrease ("barche", "barse", "bartese", "komche", "komse")
  [/^bar(che|chhe|ce|se|tese|tesi|techhe|lo|e|bo)$/, "increasing", "bn-latn"],
  [/^kom(che|chhe|ce|se|tese|tesi|techhe|lo)$/, "decreasing", "bn-latn"],
  [/^(naik|meningkat|bertambah)$/, "increasing", "ms"],
  [/^(turun|menurun|berkurang|merosot)$/, "decreasing", "ms"],
  [/^khoro?ch\w*$/, "spent", "bn-latn"],
  [/^ge(lo|che|se|silo|chilo|chhe)$/, "spent", "bn-latn"],
  [/^kin(lam|chi|si|ecchi|echi|tesi|techi|bo|e|li)$/, "bought", "bn-latn"],
  [/^di(yechi|chi|lam|si|yesi|ye|tesi)$/, "paid", "bn-latn"],
  [/^kor(chi|si|tesi|techi|lam|bo|ben|o|chen|cho|te|e|eci|echi|eso)$/, "", "bn-latn"],
  [/^h(o|oy)(ise|yeche|eche|cche|che|lo|ilo|ye|ycha|oyeche|sse)$/, "", "bn-latn"],
  [/^habis\w*$|^berbelanja$/, "spent", "ms"],
  [/^(beli|membeli|dibeli)$/, "bought", "ms"],
  [/^(bayar|membayar|dibayar)$/, "paid", "ms"],
];

/** Short typos and abbreviations (edit-distance correction only touches words of 4+ letters). */
const SHORT: Record<string, string> = {
  fod: "food", fud: "food", mch: "much", muc: "much", wht: "what", wat: "what", wek: "week", wik: "week", hw: "how", yr: "year", mnt: "month", mont: "month",
  mnth: "month", lst: "last", wich: "which", whch: "which", spnd: "spend", spnt: "spent", shw: "show", sho: "show", hwo: "how", tdy: "today", tmrw: "tomorrow",
};

// Bengali script (a few common words).
const BENGALI: [RegExp, string][] = [
  [/কত\s*টাকা|কত/g, " how much "], [/খরচ/g, " spent "], [/এই\s*সপ্তাহে|এই\s*সপ্তাহ/g, " this week "], [/গত\s*সপ্তাহে|গত\s*সপ্তাহ/g, " last week "],
  [/এই\s*মাসে|এই\s*মাস/g, " this month "], [/গত\s*মাসে|গত\s*মাস/g, " last month "], [/আজ/g, " today "], [/গতকাল/g, " yesterday "],
  [/খাবার/g, " food "], [/কেন/g, " why "], [/আমি|আমার|করেছি|হয়েছে|হলো/g, " "],
];

/** Words typo correction may produce (SpenDrop's own vocabulary). */
const DOMAIN = [
  "how", "much", "many", "spend", "spent", "spending", "food", "week", "month", "year", "last", "this", "today", "yesterday", "show", "find", "which",
  "what", "where", "why", "compare", "account", "accounts", "category", "categories", "merchant", "merchants", "summary", "unusual", "biggest", "largest",
  "smallest", "transaction", "transactions", "payment", "payments", "purchase", "purchases", "average", "total", "restaurant", "restaurants",
  "shopping", "transport", "groceries", "bills", "entertainment", "education", "health", "travel", "subscription", "subscriptions", "weekly",
  "monthly", "previous", "more", "less", "receipt", "cash", "card", "transfer", "wallet", "money",
  "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december",
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
];

/** Ordinary words that are never "corrected". */
const COMMON = new Set(("i me my you your we our it its is am are was were be been do did does done have has had the a an and or but on in at of for to " +
  "from with by about as into than then that these those there here so if not no yes ok okay please can could would should will just also " +
  "go went gone get got make made buy bought pay paid use used via using up down out over under around near most least all any some every " +
  "lately recently usually normal normally time times day days again still even only really very too much more less " +
  // ordinary words that look like domain words (never "correct" list → last, bill → till, ride → side …)
  "list lists lost lot lots bill bills ride rides trip trips item items thing things stuff need want tell give check remember mind " +
  "kind find fine line live love like look took book back pack fast past most must mast best rest test west went want sent rent " +
  "mean means meant meal meals real read ready head held help hold hole home hope hour huge idea keep kept kids know knew late " +
  "left less life lift light long lose made mail main make many mark meet mine miss month morning move name near next nice none " +
  "note open over part paid pair plan play plus post pull push quite rate rich ride rise road room rule safe sale same save says " +
  "seem seen sell send shop show side sign size slow small some soon sort spot stay step stop such sure take talk team than them " +
  "they thin this told tool tour town tree trip true turn type unit upon vote wait walk wall wear week well were what when wide " +
  "wife will wind wish with word work year your zone admin pretend everyone everybody anyone someone").split(" "));

function editDistance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  const prev2: number[] = [];
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1); // transposition
      cur.push(v);
      rowMin = Math.min(rowMin, v);
    }
    if (rowMin > max) return max + 1;
    prev2.splice(0, prev2.length, ...prev);
    prev = cur;
  }
  return prev[b.length];
}

/**
 * @param names the user's own merchant and account names (so "shope" → "shopee" when they have Shopee records).
 */
export function understand(message: string, names: string[] = []): Understanding {
  const languages = new Set<Understanding["languages"][number]>();
  const translations: Understanding["translations"] = [];
  const corrections: Understanding["corrections"] = [];
  let t = message.toLowerCase().replace(/[’']/g, "'").replace(/\s+/g, " ").trim();

  if (/[ঀ-৿]/.test(t)) {
    languages.add("bn");
    for (const [re, to] of BENGALI) t = t.replace(re, (m) => { translations.push({ from: m.trim(), to: to.trim() }); return to; });
  }
  for (const [re, to, lang] of PHRASES) {
    t = t.replace(re, (m) => { if (m.trim() !== to.trim()) { translations.push({ from: m.trim(), to: to.trim() }); languages.add(lang); } return ` ${to} `; });
  }

  const nameWords = new Set(names.flatMap((n) => n.toLowerCase().split(/[^\p{L}\p{N}]+/u)).filter((w) => w.length >= 3));
  const targets = [...DOMAIN, ...nameWords];
  const known = new Set([...DOMAIN, ...COMMON, ...nameWords]);

  const out = t.split(/(\s+|[?!.,;:()]+)/).map((token) => {
    const w = token.trim();
    if (!w || !/^[\p{L}][\p{L}-]*$/u.test(w)) return token;
    const short = SHORT[w];
    if (short) { corrections.push({ from: w, to: short }); return short; }
    const stem = WORDS[w] ? undefined : STEMS.find(([re]) => re.test(w));
    if (stem) { translations.push({ from: w, to: stem[1] || "(ignored)" }); languages.add(stem[2]); return stem[1]; }
    const mapped = WORDS[w];
    if (mapped) {
      if (mapped[0] !== w) { translations.push({ from: w, to: mapped[0] || "(ignored)" }); languages.add(mapped[1]); }
      return mapped[0];
    }
    // Edit-distance correction only for words of 5+ letters: shorter ones are too often real words ("who" ≠ "why",
    // "junk" ≠ "june"); common short typos are in SHORT instead.
    if (known.has(w) || w.length < 5) return token;
    const max = w.length <= 6 ? 1 : 2;
    let best: string | null = null;
    let bestD = max + 1;
    for (const candidate of targets) {
      if (Math.abs(candidate.length - w.length) > max || candidate[0] !== w[0]) continue;
      const d = editDistance(w, candidate, max);
      if (d < bestD) { best = candidate; bestD = d; }
    }
    if (best && bestD <= max) { corrections.push({ from: w, to: best }); return best; }
    return token;
  });
  t = out.join("").replace(/\s+/g, " ").replace(/\s+([?!.,])/g, "$1").trim();
  if (languages.size === 0 || [...languages].every((l) => l === "en")) languages.add("en");
  return { text: t, corrections, translations, languages: [...languages] };
}

/** "I read that as: …" — only worth showing when something was actually translated or corrected. */
export const understoodAs = (u: Understanding) =>
  u.corrections.length + u.translations.filter((x) => x.to !== "(ignored)").length > 0 ? u.text : undefined;

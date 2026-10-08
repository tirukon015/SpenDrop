// Conversation layer: decides whether a message is SOCIAL (talking to SpenDrop) or FINANCIAL (about the user's money)
// by meaning, not by matching whole phrases, and answers social messages naturally in the user's language.
//
// How it generalises to unseen phrasings:
//   • Financial signals are detected by the planner (amounts, periods, categories, merchants, accounts, channels, money
//     vocabulary, follow-ups). Anything financial goes to the financial engine — the casual part only adds a greeting.
//   • A non-financial message is classified by its STRUCTURE: is it addressed to SpenDrop ("you", "tumi", "awak",
//     "তুমি"…)? Then what does it ask about — well-being, activity, identity, abilities, or is it a compliment?
//     Otherwise: thanks, goodbye, greeting, acknowledgement, yes/no, a social status question, or short chit-chat.
//   • Word families (not phrases) per language live in one table below; adding a language means adding words.
// Replies are short, mirror the user's language, vary naturally (stable per message) and steer back to spending.

export type Lang = "en" | "bn-latn" | "bn" | "ms";
export type SocialAct =
  | "greeting" | "wellbeing" | "doing" | "identity" | "capabilities" | "compliment"
  | "thanks" | "ack" | "goodbye" | "affirm" | "deny" | "chitchat";

// ------------------------------------------------------------------------------------------------------------------
// Word families. Matched as whole words on a lowercased copy whose stretched letters are collapsed ("hiii" → "hi",
// "kemon achoo" → "kemon acho"). Bengali script uses Unicode-aware boundaries.
// ------------------------------------------------------------------------------------------------------------------
const W = {
  /** Second person: the message is addressed to SpenDrop. */
  you: ["you", "u", "ya", "your", "ur", "yours", "yourself", "you're", "youre", "tumi", "tomar", "tomake", "tumio", "apni", "apnar", "apnake", "tui", "tor", "awak", "kau", "anda", "engkau", "তুমি", "তোমার", "তোমাকে", "আপনি", "আপনার", "তুই", "তোর"],
  wellbeing: ["ok", "okay", "alright", "all right", "good", "fine", "well", "doing", "feeling", "feel", "day", "going", "kemon", "kmn", "bhalo", "valo", "sihat", "baik", "khabar", "obostha", "kabar",
    // Banglish "to be" forms that follow kemon / bhalo ("kemon aso", "bhalo achen")
    "aso", "acho", "asen", "achen", "achho", "aco", "achi", "asi", "achis", "asos", "chhen", "আছো", "আছ", "আছেন", "আছিস", "ভালো", "কেমন", "অবস্থা"],
  activity: ["doing", "up to", "busy", "do", "koro", "korcho", "korchen", "korchis", "korchho", "buat", "busy", "করো", "করছ", "করছো", "করছেন", "কি করো"],
  identity: ["name", "who", "nam", "naam", "ke", "siapa", "nama", "নাম", "কে"],
  capability: ["can", "able", "help", "parba", "paro", "paren", "parbe", "boleh", "mampu", "পারো", "পারবে"],
  compliment: ["smart", "helpful", "great", "awesome", "amazing", "best", "nice", "cool", "clever", "brilliant", "love", "genius", "bagus", "pandai", "hebat", "joss", "darun", "osadharon", "দারুণ", "অসাধারণ"],
  thanks: ["thank", "thanks", "thx", "tq", "ty", "tqvm", "cheers", "appreciate", "appreciated", "grateful", "dhonnobad", "dhonnobaad", "shukriya", "terima kasih", "trima kasih", "ধন্যবাদ"],
  goodbye: ["bye", "goodbye", "good bye", "see you", "see ya", "catch you", "later", "good night", "gn", "take care", "ttyl", "allah hafez", "allah hafiz", "pore kotha hobe", "selamat tinggal", "jumpa lagi", "babai", "বিদায়", "আল্লাহ হাফেজ", "আবার কথা হবে"],
  greeting: ["hi", "hello", "hey", "hiya", "yo", "howdy", "morning", "good morning", "good afternoon", "good evening", "greetings", "salam", "assalamualaikum", "assalamu alaikum", "salaam", "nomoshkar", "adab", "hai", "helo", "selamat pagi", "selamat petang", "selamat malam", "shubho shokal", "subho sokal", "হ্যালো", "হাই", "সালাম", "আসসালামু আলাইকুম", "নমস্কার", "শুভ সকাল", "শুভ সন্ধ্যা"],
  /** "nice to see you" is a greeting, not a goodbye. */
  meet: ["nice to see you", "good to see you", "nice to meet you", "good to meet you", "glad to see you"],
  /** Social status questions without "you": "what's up", "ki obostha", "apa khabar", "কি খবর". */
  status: ["what's up", "whats up", "wassup", "sup", "what's new", "whats new", "what's going on", "whats going on", "what's happening", "ki obostha", "ki khobor", "ki khabor", "ki holo", "ki hal", "kemon cholche", "apa khabar", "apa cerita", "apa macam", "কি খবর", "কী খবর", "কি অবস্থা", "কেমন চলছে"],
  ack: ["ok", "okay", "okey", "kk", "k", "got it", "alright", "all right", "cool", "noted", "i see", "understood", "fine", "perfect", "great", "nice", "awesome", "makes sense", "hmm", "hm", "lol", "haha", "hehe", "thik ache", "thik ase", "thik", "accha", "acha", "achha", "bujhlam", "bujhsi", "bujhchi", "bhalo", "valo", "baik", "faham", "orait", "ঠিক আছে", "আচ্ছা", "বুঝলাম", "বুঝেছি", "ওকে", "👍"],
  affirm: ["yes", "yeah", "yep", "yup", "ya", "sure", "go ahead", "do it", "please do", "yes please", "han", "haan", "ha", "hya", "ji", "kore dao", "boleh", "teruskan", "হ্যাঁ", "হ্যা", "জি"],
  deny: ["no", "nope", "nah", "no thanks", "not now", "never mind", "nevermind", "na", "thak", "dorkar nai", "lagbe na", "tak", "tak payah", "tidak", "না", "থাক"],
  fillers: ["bro", "bruh", "dude", "man", "boss", "bhai", "vai", "bhaiya", "lah", "la", "leh", "meh", "ji", "please", "pls", "plz", "so", "and", "oh", "ah", "eh", "re", "there", "just", "pretty", "really", "so much", "very", "a lot", "the", "for", "to", "for the", "ভাই"],
};

// Language cue words (beyond the script): enough to mirror Banglish / Malay replies.
const BANGLISH = ["mash", "gesi", "gese", "gelo", "hoise", "hoyeche", "barche", "barse", "komche", "komse", "bar", "gotho", "jacche", "kinlam", "uraisi", "korchi", "korsi", "koybar", "kotobar", "naki", "keno", "er", "ta", "ami", "amar", "tumi", "tomar", "apni", "ki", "kemon", "kmn", "bhalo", "valo", "achi", "aso", "acho", "asen", "achen", "obostha", "khobor", "koro", "korcho", "nam", "naam", "accha", "thik", "ache", "bujhlam", "dhonnobad", "koto", "khoroch", "kal", "kalke", "aaj", "taka", "keno", "kothay", "shubho", "subho", "shokal", "sokal", "hobe", "pore", "kotha", "darun", "valoi", "bhaiya"];
const MALAY = ["untuk", "ini", "guna", "kali", "lepas", "makan", "makanan", "naik", "turun", "habis", "pakai", "awak", "saya", "apa", "buat", "boleh", "sihat", "khabar", "terima", "kasih", "baik", "tak", "nak", "ni", "tu", "siapa", "nama", "selamat", "pagi", "petang", "malam", "berapa", "belanja", "habis", "jumpa", "lagi", "cerita", "macam", "kau", "anda", "faham", "bagus", "pandai", "hebat", "semalam", "minggu", "bulan"];

const BOUND_L = "(?<![\\p{L}\\p{M}\\p{N}'])";
const BOUND_R = "(?![\\p{L}\\p{M}\\p{N}'])";
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/'/g, "'?");
const family = (words: string[]) => new RegExp(`${BOUND_L}(?:${[...words].sort((a, b) => b.length - a.length).map(escape).join("|")})${BOUND_R}`, "giu");
const RE = Object.fromEntries(Object.entries(W).map(([k, v]) => [k, family(v)])) as Record<keyof typeof W, RegExp>;
const test = (re: RegExp, s: string) => { re.lastIndex = 0; return re.test(s); };

/** Lowercase, unify apostrophes, collapse stretched letters ("hiiii" → "hi", "thanksss" → "thanks", "achoo" → "acho"). */
export function casualForm(message: string): string {
  return message.toLowerCase().replace(/[’`]/g, "'").replace(/(\p{L})\1{2,}/gu, "$1").replace(/oo(?=\s|$|[?!.,])/g, "o").replace(/\s+/g, " ").trim();
}

/** The user's language for a social reply (script first, then cue words; English by default). */
export function detectLanguage(message: string): Lang {
  if (/[\u0980-\u09ff]/.test(message)) return "bn";
  const words = casualForm(message).split(/[^\p{L}']+/u).filter(Boolean);
  const bn = words.filter((w) => BANGLISH.includes(w)).length;
  const ms = words.filter((w) => MALAY.includes(w)).length;
  if (bn > ms && bn > 0) return "bn-latn";
  if (ms > 0) return "ms";
  return "en";
}

/** Whatever remains after removing every social word family and filler (empty = purely social). */
function nonSocialRemainder(s: string): string {
  let rest = s;
  for (const key of ["meet", "status", "thanks", "goodbye", "greeting", "ack", "affirm", "deny", "you", "wellbeing", "activity", "identity", "capability", "compliment", "fillers"] as const) {
    RE[key].lastIndex = 0;
    rest = rest.replace(RE[key], " ");
  }
  return rest.replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}\s.,!?;:…~"()\-]+/gu, " ").replace(/\b(what|whats|how|are|is|am|was|were|do|does|did|it|its|it's|me|i|my|a|an|of|with|at|in|on|ki|tu|apa|kau|ke|ni|yang)\b/g, " ").trim();
}

export interface SocialReading {
  act: SocialAct | null;
  lang: Lang;
  /** Only social words (no other content) — safe to answer socially without anything being lost. */
  pure: boolean;
  saidBro: boolean;
}

/**
 * Classify a message that has NO financial content. (The planner checks financial signals first; this never decides
 * that a message about money is "just chat".)
 */
export function readSocial(message: string): SocialReading {
  const s = casualForm(message);
  const lang = detectLanguage(message);
  const saidBro = /(?<![\p{L}])(bro|bruh|bhai|vai|ভাই)(?![\p{L}])/iu.test(s);
  const words = s.split(/\s+/).filter(Boolean);
  const pure = nonSocialRemainder(s) === "";
  const addressed = test(RE.you, s);
  let act: SocialAct | null = null;
  if (test(RE.meet, s)) act = "greeting";
  else if (test(RE.thanks, s)) act = "thanks";
  else if (test(RE.goodbye, s) && !addressed || /^(catch you|see you|see ya)/.test(s)) act = "goodbye";
  else if (test(RE.status, s)) act = "wellbeing";
  else if (addressed) {
    act = test(RE.identity, s) ? "identity"
      : test(RE.capability, s) ? "capabilities"
      : test(RE.activity, s) && !/\b(how are|how r)\b/.test(s) ? "doing"
      : test(RE.compliment, s) ? "compliment"
      : test(RE.wellbeing, s) || /\b(how are|how r|are you)\b/.test(s) ? "wellbeing"
      : "chitchat";
  } else if (/^(kemon|kmn|valo|bhalo)\b.*\?$|^(kemon|kmn)\b/.test(s) || /^(কেমন|ভালো আছ)/.test(s)) act = "wellbeing";
  else if (test(RE.greeting, s) && /^\s*\S+/.test(s) && words.length <= 6) act = "greeting";
  else if (pure && test(RE.affirm, s) && words.length <= 3) act = "affirm";
  else if (pure && test(RE.deny, s) && words.length <= 3) act = "deny";
  else if (pure && test(RE.ack, s)) act = "ack";
  else if (words.length <= 5) act = "chitchat";
  // A greeting that also asks how we are is answered as the question ("hey, how's your day going?").
  if (act === "greeting" && (test(RE.status, s) || (addressed && (test(RE.wellbeing, s) || /\b(how are|how r)\b/.test(s))))) act = "wellbeing";
  return { act, lang, pure, saidBro };
}

// ------------------------------------------------------------------------------------------------------------------
// Replies: several natural variants per act and language; the choice is stable for the same message.
// ------------------------------------------------------------------------------------------------------------------
const REPLIES: Record<SocialAct, Record<Lang, string[]>> = {
  greeting: {
    en: ["Hey{bro}! 😊 What would you like to know about your spending?", "Hi{bro}! What can I check for you today?", "Hello! 😊 Ask me anything about your money."],
    "bn-latn": ["Hello{bro} 😄 Aaj ki dekhte chao?", "Hi 😄 Khoroch niye ki janbe bolo?"],
    bn: ["হ্যালো 😄 আজ কী দেখতে চাও?", "হাই 😄 খরচ নিয়ে কী জানতে চাও?"],
    ms: ["Hai! 😊 Apa yang boleh saya bantu hari ini?", "Helo! 😊 Nak semak apa tentang perbelanjaan awak?"],
  },
  wellbeing: {
    en: ["I'm doing great! 😊 What can I help you check today?", "All good here{bro} 😊 What would you like to look at?", "Doing well, thanks for asking! 😊 What can I check for you?"],
    "bn-latn": ["Bhalo achi 😄 Tumi kemon acho?", "Ekdom bhalo{bro} 😄 Tumi kemon? Ki check korbo?", "Bhalo achi 😄 Bolo, ki dekhte chao?"],
    bn: ["ভালো আছি 😄 তুমি কেমন আছো?", "ভালোই আছি 😄 বলো, কী দেখতে চাও?"],
    ms: ["Baik! 😊 Apa yang boleh saya bantu hari ini?", "Sihat, terima kasih 😊 Awak pula macam mana?"],
  },
  doing: {
    en: ["I'm here helping you understand your spending 😊 What would you like to check?", "Just keeping an eye on your money with you 😊 What should I look at?"],
    "bn-latn": ["Tomar khoroch bujhte help korchi 😄 Ki janbe?", "Tomar spending dekhchi 😄 Ki check korbo bolo?"],
    bn: ["তোমার খরচ বুঝতে সাহায্য করছি 😄 কী জানতে চাও?"],
    ms: ["Saya di sini untuk bantu awak faham perbelanjaan 😊 Nak semak apa?"],
  },
  identity: {
    en: ["I'm SpenDrop's assistant 😊 I answer questions about your own spending, straight from your records."],
    "bn-latn": ["Ami SpenDrop er assistant 😄 Tomar nijer khoroch niye ja khushi jiggesh koro."],
    bn: ["আমি SpenDrop-এর সহকারী 😄 তোমার খরচ নিয়ে যা খুশি জিজ্ঞেস করো।"],
    ms: ["Saya pembantu SpenDrop 😊 Tanya apa saja tentang perbelanjaan awak."],
  },
  capabilities: {
    en: ["I can check your own SpenDrop records: totals (“How much did I spend this week?”), lookups (“Where did my RM15 go?”), comparisons, unusual spending and what's driving changes."],
    "bn-latn": ["Ami tomar SpenDrop records dekhte pari 😄 — jemon “ei week e koto khoroch hoise?”, “RM15 ta koi gelo?”, ba “keno beshi khoroch hocche?”"],
    bn: ["আমি তোমার SpenDrop রেকর্ড দেখতে পারি 😄 — যেমন “এই সপ্তাহে কত খরচ হয়েছে?”"],
    ms: ["Saya boleh semak rekod SpenDrop awak 😊 — contohnya “berapa saya belanja minggu ni?” atau “RM15 saya pergi mana?”"],
  },
  compliment: {
    en: ["Thank you{bro}! 😊 Happy to help.", "Aww, thanks! 😊 Anything else to check?"],
    "bn-latn": ["Thank you{bro} 😄", "Dhonnobad 😄 Aro kichu dekhbo?"],
    bn: ["ধন্যবাদ 😄"],
    ms: ["Terima kasih! 😊"],
  },
  thanks: {
    en: ["You're welcome! 😊", "Anytime{bro} 😄", "Happy to help! 😊"],
    "bn-latn": ["Anytime{bro} 😄", "Kono bepar na 😄"],
    bn: ["স্বাগতম 😄", "কোনো ব্যাপার না 😄"],
    ms: ["Sama-sama 😊", "Tak ada masalah 😊"],
  },
  ack: { en: ["👍"], "bn-latn": ["👍"], bn: ["ঠিক আছে 😄", "আচ্ছা 👍"], ms: ["👍"] },
  goodbye: {
    en: ["Bye{bro}! Ask me anytime 👋", "See you later! 👋"],
    "bn-latn": ["Allah hafez 👋", "Pore kotha hobe 👋"],
    bn: ["আবার কথা হবে 👋"],
    ms: ["Jumpa lagi 👋"],
  },
  affirm: { en: ["👍"], "bn-latn": ["👍"], bn: ["👍"], ms: ["👍"] },
  deny: { en: ["No problem 👍"], "bn-latn": ["Thik ache 👍"], bn: ["ঠিক আছে 👍"], ms: ["Tak apa 👍"] },
  chitchat: {
    en: ["😊 I'm best with questions about your money — try “How much did I spend this week?”"],
    "bn-latn": ["😄 Ami tomar khoroch niye help korte pari — jemon “ei week e koto khoroch hoise?”"],
    bn: ["😄 আমি তোমার খরচ নিয়ে সাহায্য করতে পারি — যেমন “এই সপ্তাহে কত খরচ হয়েছে?”"],
    ms: ["😊 Saya paling pandai soal duit awak — cuba “berapa saya belanja minggu ni?”"],
  },
};

/** Time-of-day greetings keep the user's own words ("Good morning! ☀️ …"). */
function timeGreeting(s: string, lang: Lang): string | null {
  if (/\bgood morning|\bmorning\b/.test(s)) return "Good morning! ☀️ What would you like to check today?";
  if (/\bgood (afternoon|evening)\b/.test(s)) return `Good ${/afternoon/.test(s) ? "afternoon" : "evening"}! 😊 What would you like to check today?`;
  if (/selamat pagi/.test(s)) return "Selamat pagi! ☀️ Apa yang boleh saya bantu?";
  if (/selamat (petang|malam)/.test(s)) return "Selamat petang! 😊 Apa yang boleh saya bantu?";
  if (/শুভ সকাল|shubho shokal|subho sokal/.test(s)) return lang === "bn" ? "শুভ সকাল ☀️ কী দেখতে চাও?" : "Shubho shokal ☀️ Ki dekhte chao?";
  if (/assalam|salam/.test(s)) return lang === "bn" ? "ওয়ালাইকুম আসসালাম 😄 কী দেখতে চাও?" : "Walaikum assalam 😄 What would you like to check?";
  if (/^(thik ache|thik ase)/.test(s)) return "Thik ache 😄";
  return null;
}

const seedOf = (s: string) => [...s].reduce((h, c) => (h * 31 + c.codePointAt(0)!) >>> 0, 7);

export function socialReply(message: string, reading: SocialReading): string {
  const s = casualForm(message);
  const special = reading.act === "greeting" || reading.act === "ack" ? timeGreeting(s, reading.lang) : null;
  const options = REPLIES[reading.act ?? "chitchat"][reading.lang];
  const text = special ?? options[seedOf(s) % options.length];
  return text.replace("{bro}", reading.saidBro ? " bro" : "");
}

/** A short greeting before a financial answer when the message opened casually ("kemon aso bro, food e…"). */
export function openerPreface(reading: SocialReading): string | undefined {
  const byLang: Partial<Record<SocialAct, Record<Lang, string>>> = {
    wellbeing: { en: "Doing great! 😊", "bn-latn": "Bhalo achi 😄", bn: "ভালো আছি 😄", ms: "Baik! 😊" },
    greeting: { en: "Hey{bro}! 😊", "bn-latn": "Hello{bro} 😄", bn: "হ্যালো 😄", ms: "Hai! 😊" },
  };
  return byLang[reading.act ?? "chitchat"]?.[reading.lang]?.replace("{bro}", reading.saidBro ? " bro" : "");
}

/** Suggestions only after an opening (greeting / how are you / who are you), never after thanks / ok / bye. */
export const socialFollowUps = (r: SocialReading): string[] =>
  r.act && ["greeting", "wellbeing", "doing", "identity", "capabilities", "chitchat"].includes(r.act) ? ["How much did I spend this week?", "Where did my money go this week?"] : [];

export const isYes = (r: SocialReading) => r.pure && (r.act === "affirm" || r.act === "ack");
export const isNo = (r: SocialReading) => r.pure && r.act === "deny";

/** Split a casual opener off a mixed message: "kemon aso bro, food e koto khoroch hoise?" → opener + "food e koto…". */
export function splitOpener(message: string): { opener: SocialReading | null; rest: string } {
  const m = /^\s*(.{2,40}?)(?:\s*[,.!?]+\s*|\s+-\s+|\s+(?=(?:and|so|ar|tapi)\b))([\s\S]+)$/u.exec(message);
  if (!m) return { opener: null, rest: message };
  const head = readSocial(m[1]);
  if (!head.act || head.act === "chitchat" || !head.pure) return { opener: null, rest: message };
  return { opener: head, rest: m[2].replace(/^(and|so|ar|tapi)\s+/i, "").trim() };
}

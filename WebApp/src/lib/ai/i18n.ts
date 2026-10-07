// Wording of financial answers in the user's language. The figures come in already verified (money already
// formatted from integer sen, counts, dates, category / merchant / account / channel names exactly as stored) and
// are inserted unchanged — only the sentence around them changes. Category and merchant names stay as they appear
// in the app. English is the fallback for anything not listed here.
import type { Lang } from "./conversation";
import type { PeriodInfo } from "./types";

export interface SubjectParts { category?: string; merchant?: string; fundingAccount?: string; channels?: string }

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** "this week (5–11 Oct 2026)" in each language; `words` is how the user named the period, if they did. */
export function periodText(lang: Lang, p: PeriodInfo | null, words?: string): string {
  if (!p) return { en: "across all your records", "bn-latn": "shob record e", bn: "সব রেকর্ডে", ms: "dalam semua rekod anda" }[lang];
  const w = words?.toLowerCase();
  const named: Record<Exclude<Lang, "en">, Record<string, string>> = {
    "bn-latn": { "this week": "ei week e", "this month": "ei mash e", "last week": "gotho week e", "last month": "gotho mash e", today: "aaj", yesterday: "kal", "this year": "ei bochor" },
    bn: { "this week": "এই সপ্তাহে", "this month": "এই মাসে", "last week": "গত সপ্তাহে", "last month": "গত মাসে", today: "আজ", yesterday: "গতকাল", "this year": "এই বছরে" },
    ms: { "this week": "minggu ini", "this month": "bulan ini", "last week": "minggu lepas", "last month": "bulan lepas", today: "hari ini", yesterday: "semalam", "this year": "tahun ini" },
  };
  if (lang === "en") return w ? `${w} (${p.label})` : p.from === p.to ? `on ${p.label}` : `in ${p.label}`;
  const n = w ? named[lang][w] : undefined;
  if (n) return `${n} (${p.label})`;
  return { "bn-latn": `${p.label} e`, bn: `${p.label}-এ`, ms: `pada ${p.label}` }[lang];
}

function subjectText(lang: Exclude<Lang, "en">, s: SubjectParts): string {
  const parts: string[] = [];
  if (lang === "bn-latn") {
    if (s.category) parts.push(`${s.category} e`);
    if (s.merchant) parts.push(`${s.merchant} e`);
    if (s.fundingAccount) parts.push(`${s.fundingAccount} theke`);
    if (s.channels) parts.push(`${s.channels} diye`);
  } else if (lang === "bn") {
    if (s.category) parts.push(`${s.category}-এ`);
    if (s.merchant) parts.push(`${s.merchant}-এ`);
    if (s.fundingAccount) parts.push(`${s.fundingAccount} থেকে`);
    if (s.channels) parts.push(`${s.channels} দিয়ে`);
  } else {
    if (s.category) parts.push(`untuk ${s.category}`);
    if (s.merchant) parts.push(`di ${s.merchant}`);
    if (s.fundingAccount) parts.push(`dari ${s.fundingAccount}`);
    if (s.channels) parts.push(`guna ${s.channels}`);
  }
  return parts.join(" ");
}

const join = (...xs: (string | undefined | false)[]) => xs.filter(Boolean).join(" ").replace(/\s+/g, " ").trim();

/** Localised sentence builders. Each returns null for English (the composer's English text is used). */
export const say = {
  /** "You spent RM 174.85 on Food this month. Based on 4 transactions." */
  spent(lang: Lang, x: { amounts: string; count: number; subject: SubjectParts; period: string; multiCurrency: boolean }): string | null {
    if (lang === "en") return null;
    const subj = subjectText(lang, x.subject);
    if (lang === "bn-latn") return cap(join(x.period, subj, `tomar ${x.amounts} khoroch hoise, ${x.count} ta transaction e.`, x.multiCurrency && "(Currency gula alada rakhsi, convert kori nai.)"));
    if (lang === "bn") return join(x.period, subj, `তুমি ${x.amounts} খরচ করেছ, ${x.count}টি লেনদেনে।`, x.multiCurrency && "(মুদ্রাগুলো আলাদা রাখা হয়েছে।)");
    return join(`Anda belanja ${x.amounts}`, subj, `${x.period}, dalam ${x.count} transaksi.`, x.multiCurrency && "(Mata wang diasingkan, tidak ditukar.)");
  },
  /** "You had 6 transactions at Starbucks this month, on 5 different days." */
  count(lang: Lang, x: { count: number; days?: number; subject: SubjectParts; period: string }): string | null {
    if (lang === "en") return null;
    const subj = subjectText(lang, x.subject);
    const days = x.days !== undefined && x.days > 0;
    if (lang === "bn-latn") return cap(join(x.period, subj, `${x.count} ta transaction hoise${days ? `, ${x.days} ta alada din e` : ""}.`));
    if (lang === "bn") return join(x.period, subj, `${x.count}টি লেনদেন হয়েছে${days ? `, ${x.days}টি আলাদা দিনে` : ""}।`);
    return join(`Anda ada ${x.count} transaksi`, subj, `${x.period}${days ? `, pada ${x.days} hari berbeza` : ""}.`);
  },
  nothing(lang: Lang, x: { subject: SubjectParts; period: string }): string | null {
    if (lang === "en") return null;
    const subj = subjectText(lang, x.subject);
    if (lang === "bn-latn") return cap(join(x.period, subj, "kono khoroch nai tomar record e."));
    if (lang === "bn") return join(x.period, subj, "তোমার রেকর্ডে কোনো খরচ নেই।");
    return join("Tiada perbelanjaan", subj, `${x.period} dalam rekod anda.`);
  },
  /** Top group of a breakdown: "Most went to Groceries: RM 252.15 (28.5%, 3 transactions)." */
  top(lang: Lang, x: { label: string; amount: string; pct: number; count: number; period: string; others: string[] }): string | null {
    if (lang === "en") return null;
    if (lang === "bn-latn") return cap(join(x.period, `sobcheye beshi gese ${x.label} e: ${x.amount} (${x.pct}%, ${x.count} ta transaction).`, x.others.length > 0 && `Tarpor ${x.others.join(" ar ")}.`));
    if (lang === "bn") return join(x.period, `সবচেয়ে বেশি খরচ হয়েছে ${x.label}-এ: ${x.amount} (${x.pct}%, ${x.count}টি লেনদেন)।`, x.others.length > 0 && `তারপর ${x.others.join(" ও ")}।`);
    return join(`Paling banyak ${x.period} untuk ${x.label}: ${x.amount} (${x.pct}%, ${x.count} transaksi).`, x.others.length > 0 && `Diikuti ${x.others.join(" dan ")}.`);
  },
  /** "Yes — you spent RM 50.00 more on Food in 1–7 Oct (RM 150.00) than in 1–7 Sep (RM 100.00), up 50%." */
  compared(lang: Lang, x: { yes: boolean; more: boolean; diff: string; a: string; aLabel: string; b: string; bLabel: string; pct: number | null; subject: SubjectParts }): string | null {
    if (lang === "en") return null;
    const subj = subjectText(lang, x.subject);
    const pct = x.pct === null ? "" : Math.abs(x.pct).toString();
    if (lang === "bn-latn") return join(x.yes ? "Ha —" : "Na —", `${x.aLabel} e`, subj, `${x.diff} ${x.more ? "beshi" : "kom"} khoroch hoise (${x.a}), ${x.bLabel} er (${x.b}) cheye${pct ? `, ${pct}% ${x.more ? "beshi" : "kom"}` : ""}.`);
    if (lang === "bn") return join(x.yes ? "হ্যাঁ —" : "না —", `${x.aLabel}-এ`, subj, `${x.diff} ${x.more ? "বেশি" : "কম"} খরচ হয়েছে (${x.a}), ${x.bLabel}-এর (${x.b}) তুলনায়${pct ? ` ${pct}% ${x.more ? "বেশি" : "কম"}` : ""}।`);
    return join(x.yes ? "Ya —" : "Tidak —", `anda belanja ${x.diff} ${x.more ? "lebih" : "kurang"}`, subj, `pada ${x.aLabel} (${x.a}) berbanding ${x.bLabel} (${x.b})${pct ? `, ${x.more ? "naik" : "turun"} ${pct}%` : ""}.`);
  },
  /** Lookups ("where did my RM15 go?"). */
  lookupNone(lang: Lang, x: { target: string; period: string }): string | null {
    if (lang === "en") return null;
    if (lang === "bn-latn") return `${x.target} er kachakachi kono transaction pai nai ${x.period}.`;
    if (lang === "bn") return `${x.period} ${x.target}-এর কাছাকাছি কোনো লেনদেন পাইনি।`;
    return `Tiada transaksi sekitar ${x.target} ${x.period}.`;
  },
  lookupOffer(lang: Lang, x: { target: string }): string | null {
    if (lang === "en") return null;
    if (lang === "bn-latn") return `Shob transaction e ${x.target} er moto amount khujbo?`;
    if (lang === "bn") return `সব লেনদেনে ${x.target}-এর মতো অ্যামাউন্ট খুঁজব?`;
    return `Nak saya cari dalam semua transaksi anda untuk jumlah sekitar ${x.target}?`;
  },
  lookupMany(lang: Lang, x: { n: number; target: string; period: string }): string | null {
    if (lang === "en") return null;
    if (lang === "bn-latn") return `${x.target} er kachakachi ${x.n} ta transaction peyechi ${x.period}. Konta khujcho?`;
    if (lang === "bn") return `${x.period} ${x.target}-এর কাছাকাছি ${x.n}টি লেনদেন পেয়েছি। কোনটা খুঁজছ?`;
    return `Saya jumpa ${x.n} transaksi sekitar ${x.target} ${x.period}. Yang mana satu?`;
  },
  lookupOne(lang: Lang, x: { line: string }): string | null {
    if (lang === "en") return null;
    if (lang === "bn-latn") return `Peye gesi: ${x.line}.`;
    if (lang === "bn") return `পেয়েছি: ${x.line}।`;
    return `Jumpa: ${x.line}.`;
  },
  /** Personal insights headline. */
  insight(lang: Lang, x: { kind: "more" | "less" | "same" | "unknown"; diff?: string; current: string; normal?: string; period: string; count: number; pct?: number | null }): string | null {
    if (lang === "en") return null;
    const pct = x.pct !== undefined && x.pct !== null ? Math.abs(x.pct) : null;
    if (lang === "bn-latn") {
      if (x.kind === "unknown") return `Tomar normal bujhte aro kichu history lagbe. Ei porjonto ${x.period} ${x.current} khoroch hoise, ${x.count} ta transaction e.`;
      if (x.kind === "same") return `${cap(x.period)} tomar khoroch ${x.current} — tomar normal er (${x.normal}) motoi.`;
      return `${cap(x.period)} tomar normal er cheye ${x.diff} ${x.kind === "more" ? "beshi" : "kom"} khoroch hoise (${x.current} vs normal ${x.normal})${pct !== null ? `, ${pct}% ${x.kind === "more" ? "beshi" : "kom"}` : ""}.`;
    }
    if (lang === "bn") {
      if (x.kind === "unknown") return `তোমার স্বাভাবিক খরচ বুঝতে আরও কিছু ইতিহাস লাগবে। এখন পর্যন্ত ${x.period} ${x.current} খরচ হয়েছে, ${x.count}টি লেনদেনে।`;
      if (x.kind === "same") return `${x.period} তোমার খরচ ${x.current} — স্বাভাবিকের (${x.normal}) মতোই।`;
      return `${x.period} তোমার স্বাভাবিকের চেয়ে ${x.diff} ${x.kind === "more" ? "বেশি" : "কম"} খরচ হয়েছে (${x.current}, স্বাভাবিক ${x.normal})${pct !== null ? `, ${pct}% ${x.kind === "more" ? "বেশি" : "কম"}` : ""}।`;
    }
    if (x.kind === "unknown") return `Saya perlukan lebih banyak sejarah untuk tahu corak biasa anda. Setakat ini ${x.period} anda belanja ${x.current}, dalam ${x.count} transaksi.`;
    if (x.kind === "same") return `Perbelanjaan anda ${x.period} ${x.current} — sama seperti biasa (${x.normal}).`;
    return `Anda belanja ${x.diff} ${x.kind === "more" ? "lebih" : "kurang"} ${x.period} berbanding biasa (${x.current} vs biasa ${x.normal})${pct !== null ? `, ${x.kind === "more" ? "naik" : "turun"} ${pct}%` : ""}.`;
  },
  /** "You used Card more: RM X (n) vs QR RM Y (m)." */
  channels(lang: Lang, x: { winner: string; wAmount: string; wCount: number; rest: { label: string; amount: string; count: number }[]; period: string }): string | null {
    if (lang === "en") return null;
    const r = x.rest.map((o) => (lang === "bn-latn" ? `${o.label} ${o.amount} (${o.count} ta)` : lang === "bn" ? `${o.label} ${o.amount} (${o.count}টি)` : `${o.label} ${o.amount} (${o.count} transaksi)`));
    if (lang === "bn-latn") return cap(join(x.period, `${x.winner} beshi use korecho: ${x.wAmount} (${x.wCount} ta transaction)`, r.length > 0 && `, ${r.join(", ")}.`).replace(/ ,/g, ","));
    if (lang === "bn") return join(x.period, `${x.winner} বেশি ব্যবহার করেছ: ${x.wAmount} (${x.wCount}টি লেনদেন)`, r.length > 0 && `, ${r.join(", ")}।`).replace(/ ,/g, ",");
    return join(`Anda lebih banyak guna ${x.winner} ${x.period}: ${x.wAmount} (${x.wCount} transaksi)`, r.length > 0 && `, berbanding ${r.join(", ")}.`).replace(/ ,/g, ",");
  },
};

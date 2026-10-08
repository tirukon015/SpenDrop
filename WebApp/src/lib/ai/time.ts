// Calendar maths in the user's own IANA time zone (no date library). Local dates are "YYYY-MM-DD" strings and
// spans are inclusive [from, to]; they become exact instants only at query time, in that time zone. Weeks run
// Monday–Sunday and months are calendar months, the same as the rest of SpenDrop (lib/domain/dates.ts).

export type LocalDate = string;
export interface DateSpan { from: LocalDate; to: LocalDate }

export const DEFAULT_TIME_ZONE = "Asia/Kuala_Lumpur";

export function isValidTimeZone(tz: string): boolean {
  if (!tz || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

const formatters = new Map<string, Intl.DateTimeFormat>();
function formatter(tz: string) {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
    });
    formatters.set(tz, f);
  }
  return f;
}

function zonedParts(instant: Date, tz: string) {
  const parts: Record<string, number> = {};
  for (const p of formatter(tz).formatToParts(instant)) if (p.type !== "literal") parts[p.type] = Number(p.value);
  return { y: parts.year, m: parts.month, d: parts.day, h: parts.hour === 24 ? 0 : parts.hour, mi: parts.minute, s: parts.second };
}

/** Milliseconds the zone is ahead of UTC at `instant`. */
function offsetMs(instant: Date, tz: string) {
  const p = zonedParts(instant, tz);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s) - Math.floor(instant.getTime() / 1000) * 1000;
}

const pad = (n: number) => String(n).padStart(2, "0");
const fromUTC = (t: number) => { const d = new Date(t); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; };
const parse = (date: LocalDate) => date.split("-").map(Number) as [number, number, number];

export const isLocalDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s) && fromUTC(Date.UTC(...toUTCArgs(s))) === s;
const toUTCArgs = (s: string): [number, number, number] => { const [y, m, d] = parse(s); return [y, m - 1, d]; };

/** The calendar date of `instant` in `tz`. */
export function localDateOf(instant: Date | string, tz: string): LocalDate {
  const p = zonedParts(typeof instant === "string" ? new Date(instant) : instant, tz);
  return `${p.y}-${pad(p.m)}-${pad(p.d)}`;
}

/** First instant of `date` in `tz` (handles DST and odd offsets). */
export function startOfLocalDay(date: LocalDate, tz: string): Date {
  const guess = Date.UTC(...toUTCArgs(date));
  const first = guess - offsetMs(new Date(guess), tz);
  const second = guess - offsetMs(new Date(first), tz);
  return new Date(second);
}

export const addDays = (date: LocalDate, n: number): LocalDate => { const [y, m, d] = parse(date); return fromUTC(Date.UTC(y, m - 1, d + n)); };
/** Monday = 0 … Sunday = 6. */
export const weekdayIndex = (date: LocalDate) => (new Date(Date.UTC(...toUTCArgs(date))).getUTCDay() + 6) % 7;
export const startOfWeek = (date: LocalDate) => addDays(date, -weekdayIndex(date));
export const startOfMonth = (date: LocalDate) => date.slice(0, 8) + "01";
export const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate();
export const endOfMonth = (date: LocalDate) => { const [y, m] = parse(date); return `${y}-${pad(m)}-${pad(daysInMonth(y, m))}`; };
export const addMonths = (date: LocalDate, n: number): LocalDate => {
  const [y, m, d] = parse(date);
  const target = new Date(Date.UTC(y, m - 1 + n, 1));
  const ty = target.getUTCFullYear(), tm = target.getUTCMonth() + 1;
  return `${ty}-${pad(tm)}-${pad(Math.min(d, daysInMonth(ty, tm)))}`;
};
export const daysBetween = (a: LocalDate, b: LocalDate) => Math.round((Date.UTC(...toUTCArgs(b)) - Date.UTC(...toUTCArgs(a))) / 86_400_000);
export const spanDays = (s: DateSpan) => daysBetween(s.from, s.to) + 1;
export const inSpan = (date: LocalDate, s: DateSpan) => date >= s.from && date <= s.to;

/** [start, endExclusive) instants of a span in `tz`. */
export function spanInstants(span: DateSpan, tz: string): { start: Date; end: Date } {
  return { start: startOfLocalDay(span.from, tz), end: startOfLocalDay(addDays(span.to, 1), tz) };
}

export const PERIOD_PRESETS = [
  "today", "yesterday", "this_week", "last_week", "this_month", "last_month", "this_year", "last_year",
  "last_7_days", "last_30_days", "last_90_days", "all_time",
] as const;
export type PeriodPreset = (typeof PERIOD_PRESETS)[number];

/** The span of a preset relative to `today` (null = all time). */
export function presetSpan(preset: PeriodPreset, today: LocalDate): DateSpan | null {
  switch (preset) {
    case "today": return { from: today, to: today };
    case "yesterday": { const y = addDays(today, -1); return { from: y, to: y }; }
    case "this_week": { const s = startOfWeek(today); return { from: s, to: addDays(s, 6) }; }
    case "last_week": { const s = addDays(startOfWeek(today), -7); return { from: s, to: addDays(s, 6) }; }
    case "this_month": return { from: startOfMonth(today), to: endOfMonth(today) };
    case "last_month": { const s = startOfMonth(addMonths(startOfMonth(today), -1)); return { from: s, to: endOfMonth(s) }; }
    case "this_year": return { from: today.slice(0, 4) + "-01-01", to: today.slice(0, 4) + "-12-31" };
    case "last_year": { const y = Number(today.slice(0, 4)) - 1; return { from: `${y}-01-01`, to: `${y}-12-31` }; }
    case "last_7_days": return { from: addDays(today, -6), to: today };
    case "last_30_days": return { from: addDays(today, -29), to: today };
    case "last_90_days": return { from: addDays(today, -89), to: today };
    case "all_time": return null;
  }
}

/**
 * The fair "previous" period for a comparison. A period still in progress (this week / this month) is compared
 * with the same days of the previous week / month ("1–7 Oct vs 1–7 Sep"), never a partial month with a full one.
 */
export function previousComparable(span: DateSpan, today: LocalDate): DateSpan {
  const isWholeMonth = span.from === startOfMonth(span.from) && span.to === endOfMonth(span.from);
  const isMonthToDate = span.from === startOfMonth(span.from) && span.to >= today && span.from <= today && span.to === endOfMonth(span.from);
  if (isMonthToDate) {
    const prevStart = addMonths(span.from, -1);
    const elapsed = daysBetween(span.from, today);
    const [py, pm] = parse(prevStart);
    const prevEnd = addDays(prevStart, Math.min(elapsed, daysInMonth(py, pm) - 1));
    return { from: prevStart, to: prevEnd };
  }
  if (isWholeMonth) { const s = addMonths(span.from, -1); return { from: s, to: endOfMonth(s) }; }
  // Anything else (weeks, days, custom): the same number of days just before, clipped to "today" when in progress.
  const effectiveTo = span.to > today && span.from <= today ? today : span.to;
  const length = daysBetween(span.from, effectiveTo) + 1;
  const isWeek = weekdayIndex(span.from) === 0 && spanDays(span) === 7;
  const shift = isWeek ? 7 : length;
  return { from: addDays(span.from, -shift), to: addDays(effectiveTo, -shift) };
}

/** The part of a span that has happened (up to and including today). */
export const elapsedSpan = (span: DateSpan, today: LocalDate): DateSpan => (span.to > today && span.from <= today ? { from: span.from, to: today } : span);

const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "7 Oct 2026", "1–7 Oct 2026", "28 Sep – 4 Oct 2026". */
export function formatSpan(span: DateSpan | null): string {
  if (!span) return "All time";
  const [fy, fm, fd] = parse(span.from), [ty, tm, td] = parse(span.to);
  if (span.from === span.to) return `${fd} ${MONTHS_SHORT[fm - 1]} ${fy}`;
  if (fy === ty && fm === tm) return `${fd}–${td} ${MONTHS_SHORT[fm - 1]} ${fy}`;
  if (fy === ty) return `${fd} ${MONTHS_SHORT[fm - 1]} – ${td} ${MONTHS_SHORT[tm - 1]} ${fy}`;
  return `${fd} ${MONTHS_SHORT[fm - 1]} ${fy} – ${td} ${MONTHS_SHORT[tm - 1]} ${ty}`;
}

export const formatLocalDate = (date: LocalDate) => formatSpan({ from: date, to: date });

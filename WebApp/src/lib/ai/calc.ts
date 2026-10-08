// The single trusted calculation layer for SpenDrop AI. Every total, average, share, difference and percentage in
// an answer comes from these functions — no other file implements a money formula. All money is integer minor
// units (sen): sums are exact; rounding happens once, at the end, half away from zero (so +x and −x round alike).

/** Σ of integer minor units. Throws on a non-integer or non-finite amount instead of silently corrupting a total. */
export function totalMinor(values: readonly number[]): number {
  let t = 0;
  for (const v of values) {
    if (!Number.isSafeInteger(v)) throw new CalculationError(`not an integer amount: ${v}`);
    t += v;
  }
  if (!Number.isSafeInteger(t)) throw new CalculationError("total out of range");
  return t;
}

/** Round half away from zero (Math.round rounds −2.5 to −2; money must be symmetric). */
export const roundHalfAway = (x: number) => Math.sign(x) * Math.round(Math.abs(x));

/** Mean in minor units, rounded once; null for no values. */
export const averageMinor = (values: readonly number[]): number | null => (values.length ? roundHalfAway(totalMinor(values) / values.length) : null);

/** current − previous. */
export const differenceMinor = (current: number, previous: number) => current - previous;

/**
 * Percentage change ((C − P) / P) × 100, to one decimal. null when there is no previous amount (P = 0): a change
 * "from nothing" has no meaningful percentage, and the answer says so instead of showing Infinity or NaN.
 * 60.00 → 86.45 = +44.1, 100 → 75 = −25, 100 → 100 = 0.
 */
export function percentChange(current: number, previous: number): number | null {
  if (previous === 0) return null;
  return roundHalfAway(((current - previous) * 1000) / previous) / 10;
}

/** part as a percentage of whole, one decimal (0 when whole is 0). */
export const sharePercent = (part: number, whole: number) => (whole === 0 ? 0 : roundHalfAway((part * 1000) / whole) / 10);

/** Average per day over `days` calendar days. */
export const perDayMinor = (total: number, days: number) => roundHalfAway(total / Math.max(1, days));

/** Scale a total from `fromDays` to `toDays` (e.g. a baseline per day × the days in this period). */
export const scaleMinor = (total: number, fromDays: number, toDays: number) => roundHalfAway((total / Math.max(1, fromDays)) * toDays);

/** The element with the largest key (ties: the first one); null for an empty list. */
export function maxBy<T>(items: readonly T[], key: (x: T) => number): T | null {
  let best: T | null = null;
  for (const x of items) if (best === null || key(x) > key(best)) best = x;
  return best;
}
export function minBy<T>(items: readonly T[], key: (x: T) => number): T | null {
  let best: T | null = null;
  for (const x of items) if (best === null || key(x) < key(best)) best = x;
  return best;
}

/** Median in minor units (0 for none). */
export function medianMinor(values: readonly number[]): number {
  const s = [...values].sort((a, b) => a - b);
  if (!s.length) return 0;
  return s.length % 2 ? s[(s.length - 1) / 2] : roundHalfAway((s[s.length / 2 - 1] + s[s.length / 2]) / 2);
}

export class CalculationError extends Error {}

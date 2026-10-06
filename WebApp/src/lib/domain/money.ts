// Exact money handling in integer minor units (sen). Mirrors iOS Money / CurrencyFormatter.
// Never use floating point for calculations; numbers here are always whole sen.

/**
 * "7.50" -> 750, "RM 1,234.5" -> 123450, "33.335" -> 3334 (half up, like iOS NSDecimalRound .plain).
 * Returns null when the text is not a plain decimal number.
 */
export function parseMinor(text: string): number | null {
  const cleaned = text.replace(/RM|MYR/gi, "").replace(/,/g, "").trim();
  const match = /^([+-])?(\d*)(?:\.(\d*))?$/.exec(cleaned);
  if (!match || (match[2] === "" && (match[3] ?? "") === "")) return null;
  const negative = match[1] === "-";
  const whole = match[2] || "0";
  const fraction = (match[3] ?? "").padEnd(3, "0");
  if (whole.length > 13) return null;
  let minor = Number(whole) * 100 + Number(fraction.slice(0, 2));
  if (Number(fraction[2]) >= 5) minor += 1;
  return negative ? -minor : minor;
}

/** 123450 -> "1,234.50" (no currency). */
export function formatMinorNumber(minor: number): string {
  const abs = Math.abs(Math.trunc(minor));
  const whole = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const cents = (abs % 100).toString().padStart(2, "0");
  return `${minor < 0 ? "-" : ""}${whole}.${cents}`;
}

/** 123450 -> "RM 1,234.50"; -500 -> "-RM 5.00" (iOS CurrencyFormatter style). */
export function formatMoney(minor: number, currency = "RM"): string {
  const body = formatMinorNumber(Math.abs(minor));
  return minor < 0 ? `-${currency} ${body}` : `${currency} ${body}`;
}

/** 750 -> "7.50" for editable text boxes. */
export function minorToInput(minor: number): string {
  return formatMinorNumber(minor).replace(/,/g, "");
}

export const sumMinor = (values: number[]) => values.reduce((total, value) => total + value, 0);

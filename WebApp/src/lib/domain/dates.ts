// Date ranges like iOS QuickDateFilter (device-local time; weeks run Monday–Sunday).
export type QuickDate =
  | "all" | "today" | "yesterday" | "last3Days" | "last7Days" | "last30Days" | "thisWeek" | "lastWeek" | "thisMonth" | "lastMonth" | "custom";

export const QUICK_DATES: { id: QuickDate; label: string }[] = [
  { id: "all", label: "All Time" },
  { id: "today", label: "Today" },
  { id: "yesterday", label: "Yesterday" },
  { id: "last3Days", label: "Last 3 Days" },
  { id: "last7Days", label: "Last 7 Days" },
  { id: "last30Days", label: "Last 30 Days" },
  { id: "thisWeek", label: "This Week" },
  { id: "lastWeek", label: "Last Week" },
  { id: "thisMonth", label: "This Month" },
  { id: "lastMonth", label: "Last Month" },
  { id: "custom", label: "Custom Range" },
];

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const endOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);

/** Monday of the week containing `d`. */
export function startOfWeek(d: Date) {
  const day = (d.getDay() + 6) % 7; // Monday = 0
  return addDays(startOfDay(d), -day);
}

/** [start, end] inclusive, or null for All Time. */
export function dateRange(filter: QuickDate, now = new Date(), custom?: { from?: string; to?: string }): [Date, Date] | null {
  const today = startOfDay(now);
  switch (filter) {
    case "all": return null;
    case "today": return [today, endOfDay(today)];
    case "yesterday": return [addDays(today, -1), endOfDay(addDays(today, -1))];
    case "last3Days": return [addDays(today, -2), endOfDay(today)];
    case "last7Days": return [addDays(today, -6), endOfDay(today)];
    case "last30Days": return [addDays(today, -29), endOfDay(today)];
    case "thisWeek": { const s = startOfWeek(now); return [s, endOfDay(addDays(s, 6))]; }
    case "lastWeek": { const s = addDays(startOfWeek(now), -7); return [s, endOfDay(addDays(s, 6))]; }
    case "thisMonth": return [new Date(now.getFullYear(), now.getMonth(), 1), endOfDay(new Date(now.getFullYear(), now.getMonth() + 1, 0))];
    case "lastMonth": return [new Date(now.getFullYear(), now.getMonth() - 1, 1), endOfDay(new Date(now.getFullYear(), now.getMonth(), 0))];
    case "custom": {
      const from = custom?.from ? startOfDay(new Date(custom.from + "T00:00:00")) : new Date(0);
      const to = custom?.to ? endOfDay(new Date(custom.to + "T00:00:00")) : endOfDay(today);
      return [from, to];
    }
  }
}

export const inRange = (iso: string, range: [Date, Date] | null) => {
  if (!range) return true;
  const t = new Date(iso).getTime();
  return t >= range[0].getTime() && t <= range[1].getTime();
};

/** The same length of time immediately before `range` (for "vs previous period"). */
export function previousRange(range: [Date, Date]): [Date, Date] {
  const length = range[1].getTime() - range[0].getTime();
  const end = new Date(range[0].getTime() - 1);
  return [new Date(end.getTime() - length), end];
}

export const dayCount = (range: [Date, Date]) => Math.max(1, Math.round((startOfDay(range[1]).getTime() - startOfDay(range[0]).getTime()) / 86_400_000) + 1);

/** "2026-10-07" in local time (for <input type="date">). */
export const toDateInput = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
export const toTimeInput = (d: Date) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
/** Local date + time inputs → ISO string. */
export const fromInputs = (date: string, time: string) => new Date(`${date}T${time || "12:00"}:00`).toISOString();

export const formatDate = (iso: string, opts: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", year: "numeric" }) =>
  new Intl.DateTimeFormat("en-MY", opts).format(new Date(iso));
export const formatTime = (iso: string) => new Intl.DateTimeFormat("en-MY", { hour: "numeric", minute: "2-digit" }).format(new Date(iso));
export const dayKey = (iso: string) => toDateInput(new Date(iso));

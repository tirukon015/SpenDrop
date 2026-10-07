// SpenDrop AI tuning knobs. Pure values (no secrets, no env access) so the same numbers are used on the server, in
// the browser demo and in tests. Provider settings (model, URLs, keys) live in ./providers/config.ts (server only).

export const AI_LIMITS = {
  /** search_transactions: default and hard maximum rows returned to the model / UI. */
  searchDefaultLimit: 20,
  searchMaxLimit: 100,
  /** Rows a single tool may load from the database; above this the tool refuses instead of answering wrongly. */
  maxRowsPerTool: 20_000,
  /** Longest period a tool accepts (days). */
  maxSpanDays: 366 * 3,
  /** LLM loop: tool calls per question and per-call / provider timeouts. */
  maxToolCalls: 6,
  toolTimeoutMs: 10_000,
  /** Conversation context sent to the model (most recent messages only). */
  historyMessages: 8,
  /** Longest question accepted. */
  maxMessageChars: 500,
} as const;

/** Rate limits per signed-in user (counted from the user's own stored questions). */
export const AI_RATE_LIMITS = { perMinute: 15, perHour: 150 } as const;

/**
 * Amount tolerance for "where did my RM15 go?". An amount said plainly is matched within ±10% (at least RM1); an
 * approximate one ("around", "about", "roughly", "~") within ±20% (at least RM2). Ranges ("RM20–30") are used as given.
 */
export const AMOUNT_TOLERANCE = {
  exact: { ratio: 0.1, minMinor: 100 },
  approximate: { ratio: 0.2, minMinor: 200 },
} as const;

/** Personal insights: compared with the user's OWN normal; only meaningful differences are mentioned. */
export const INSIGHTS = {
  /** Earlier months / weeks averaged into "normal" (same days of each), and how many are needed at least. */
  baselineMonths: 3,
  baselineWeeks: 4,
  minBaselinePeriods: 2,
  /** A change is worth mentioning from this percentage AND this amount (month / week). */
  minPct: 25,
  minDiffMinorMonth: 3_000,
  minDiffMinorWeek: 2_000,
  /** "Small payments add up": at least this many, each below this, together at least this. */
  smallCount: 5,
  smallEachMinor: 1_500,
  smallTotalMinor: 4_000,
  /** Weekend days at least this many times the weekday daily average (over ≥ 4 weeks). */
  weekendRatio: 1.5,
} as const;

/** Unusual-spending rules (always relative to the user's own history, never to other users). */
export const UNUSUAL = {
  /** Weeks of history before the period used as the baseline. */
  baselineWeeks: 8,
  /** Minimum weeks with recorded spending before anything is called "unusual". */
  minHistoryWeeks: 3,
  /** A category is a spike when it is ≥ this × its weekly average and at least `minSpikeMinor` above it. */
  spikeRatio: 1.5,
  minSpikeMinor: 2_000,
  /** A transaction is large when it is ≥ this × the median of its category (≥ `minCategorySamples` samples). */
  largeRatio: 3,
  minCategorySamples: 5,
  minLargeMinor: 2_000,
  /** New merchants are only reported from this amount up, and at most this many. */
  minNewMerchantMinor: 3_000,
  maxNewMerchants: 3,
} as const;

// SpenDrop AI shared types: the execution context (who is asking — set by the server from the verified session,
// never by the model or the browser), tool results, and the structured answer the UI renders.
import type { CategoryId, PaymentChannelId } from "@/lib/domain/types";
import type { DateSpan, LocalDate } from "./time";

/**
 * Who is asking and in which time zone. Built ONLY by the server from the authenticated session (or by the local
 * demo for its synthetic data). Tools receive it as a separate argument; tool inputs can never contain a user id.
 */
export interface AiContext {
  readonly userId: string;
  readonly timeZone: string;
  /** "Today" in the user's time zone. */
  readonly today: LocalDate;
  readonly requestId: string;
}

export type Intent =
  | "SEARCH" | "CALCULATE" | "COMPARE" | "INVESTIGATE" | "SUMMARY" | "ACCOUNT_ANALYSIS" | "PAYMENT_CHANNEL_ANALYSIS"
  | "MERCHANT_ANALYSIS" | "CATEGORY_ANALYSIS" | "UNUSUAL_SPENDING" | "TRANSACTION_DETAIL" | "INSIGHTS" | "PERSONAL_RULE" | "MEMORY"
  | "CLARIFY" | "OUT_OF_SCOPE" | "SMALL_TALK" | "GENERAL" | "SECURITY" | "UNKNOWN";

export type Confidence = "HIGH" | "MEDIUM" | "LOW" | "NO_MATCH";

/** A transaction as shown to the user / model: only the fields needed to recognise it. */
export interface TxnCard {
  id: string;
  merchant: string;
  /** Full transaction amount. */
  amountMinor: number;
  /** What counts as the user's spending (their share when someone else paid). */
  spendMinor: number;
  currency: string;
  /** ISO instant + the local calendar date and time in the user's zone. */
  date: string;
  localDate: LocalDate;
  localTime: string;
  /** The category used in answers (the user's personal rule, if any). */
  category: CategoryId;
  /** Set when a personal rule changed the category: what the record itself says. */
  recordedCategory?: CategoryId;
  /** WHERE the money came from. */
  fundingAccount: string;
  /** HOW it was paid. */
  paymentChannel: PaymentChannelId;
  hasReceipt: boolean;
  isShared: boolean;
  source: string;
  /** The user's own remark on the transaction (context only — never a source of facts). */
  remark?: string;
}

export interface PeriodInfo { from: LocalDate; to: LocalDate; label: string }

export interface Evidence {
  tool: string;
  transactionCount: number;
  period: string;
  filters: string;
  generatedAt: string;
}

export interface ToolSuccess<T> { ok: true; data: T; evidence: Evidence }
export interface ToolFailure { ok: false; error: { kind: "validation" | "unavailable" | "not_found" | "too_large" | "timeout" | "permission"; message: string } }
export type ToolResult<T = unknown> = ToolSuccess<T> | ToolFailure;

// ---------------------------------------------------------------------------------------------------------------
// Answer shown in the UI (and stored with the conversation). Text is plain text — never HTML.
// ---------------------------------------------------------------------------------------------------------------
export type AnswerBlock =
  | { type: "metric"; label: string; valueMinor: number; currency: string; caption?: string }
  | { type: "comparison"; currency: string; a: { label: string; valueMinor: number; count: number }; b: { label: string; valueMinor: number; count: number }; diffMinor: number; pct: number | null }
  | { type: "breakdown"; title: string; currency: string; kind: "category" | "merchant" | "account" | "channel" | "day"; items: { key: string; label: string; valueMinor: number; count: number; diffMinor?: number }[] }
  | { type: "transactions"; title: string; items: TxnCard[]; more?: number }
  | { type: "findings"; title: string; items: { title: string; detail: string }[] };

export type AnswerStatus = "answered" | "clarify" | "no_match" | "no_data" | "refused" | "error";

/** What the conversation is "about", so short follow-ups ("Why?", "Which restaurants?") can be resolved. */
export interface Focus {
  intent: Intent;
  filters: FocusFilters;
  span: DateSpan | null;
  compareSpan?: DateSpan | null;
  /** Transactions just shown, for "the first one" / "tell me more about #2". */
  transactionIds?: string[];
  /** How the last answer was calculated, so "what about last month?" can repeat it with only the period changed. */
  operation?: "sum" | "count" | "average";
  groupBy?: "category" | "merchant" | "funding_account" | "payment_channel";
  /**
   * The main question a drill-down came from ("How much on Food this week?" → "Why?" → "Which restaurants?"): a later
   * "Yesterday?" repeats the main question for the new period, not the drill-down.
   */
  base?: { intent: Intent; operation?: "sum" | "count" | "average"; groupBy?: "category" | "merchant" | "funding_account" | "payment_channel" };
  /** An offer made in the last answer ("search all your transactions?"), accepted by "yes" / "okay". */
  offer?: { args: Record<string, unknown>; label: string };
}

export interface FocusFilters {
  category?: CategoryId;
  merchant?: string;
  /** Exact stored merchant names the question resolved to (several when the user asked for all similar names). */
  merchants?: string[];
  fundingAccount?: string;
  paymentChannel?: PaymentChannelId;
  paymentChannels?: PaymentChannelId[];
  currency?: string;
  amountMin?: number;
  amountMax?: number;
  /** The amount the user remembers (lookups), so "Yesterday?" keeps looking for it. */
  targetAmount?: number;
  keyword?: string;
}

export interface AnswerMeta {
  requestId: string;
  intent: Intent;
  route: "deterministic" | "model";
  provider: string;
  model?: string;
  tools: { name: string; ok: boolean; ms: number }[];
  totalMs: number;
  /** Set when a model answer was replaced because it contained figures no tool returned. */
  groundingFallback?: boolean;
  tokens?: { input: number; output: number };
}

export interface AskAnswer {
  status: AnswerStatus;
  text: string;
  blocks: AnswerBlock[];
  evidence: Evidence[];
  followUps: string[];
  confidence?: Confidence;
  /** How SpenDrop read an informal / other-language / misspelt question ("how much spent food this week"). */
  understoodAs?: string;
  /** A short greeting when the question opened casually ("kemon aso bro, …" → "Bhalo achi 😄"). Never contains figures. */
  preface?: string;
  /** A data-based observation beyond the direct answer ("That's RM96 more than your usual week"). */
  insight?: string;
  /** An optional, evidence-based suggestion (never advice). */
  suggestion?: string;
  focus: Focus | null;
  meta: AnswerMeta;
}

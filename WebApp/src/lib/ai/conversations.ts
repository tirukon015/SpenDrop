// Conversation history in Supabase (tables from migration 20261009000000_spendrop_ai.sql), always for the
// authenticated user: the user's own JWT (RLS) plus an explicit user_id filter on every query. A conversation id
// from someone else simply isn't found.
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { categorySchema, channelSchema } from "./schemas";
import { isLocalDate } from "./time";
import type { AskAnswer, Focus } from "./types";

export class AiSetupError extends Error {}
export class AiStoreError extends Error {}

const isMissingTable = (e: { code?: string; message?: string }) => e.code === "42P01" || e.code === "PGRST205" || /does not exist|schema cache/.test(e.message ?? "");

const date = z.string().refine(isLocalDate);
const span = z.object({ from: date, to: date }).nullable();
/** The focus stored with an answer is re-validated when it is read back (it is only ever a hint for the planner). */
export const focusSchema = z.object({
  intent: z.string().max(40),
  filters: z.object({
    category: categorySchema.optional(), merchant: z.string().max(80).optional(), fundingAccount: z.string().max(80).optional(),
    paymentChannel: channelSchema.optional(), paymentChannels: z.array(channelSchema).max(11).optional(), currency: z.string().max(8).optional(),
    amountMin: z.number().min(0).optional(), amountMax: z.number().min(0).optional(), targetAmount: z.number().min(0).optional(), keyword: z.string().max(80).optional(),
  }),
  span,
  compareSpan: span.optional(),
  transactionIds: z.array(z.string().uuid()).max(10).optional(),
  operation: z.enum(["sum", "count", "average"]).optional(),
  groupBy: z.enum(["category", "merchant", "funding_account", "payment_channel"]).optional(),
  base: z.object({ intent: z.string().max(40), operation: z.enum(["sum", "count", "average"]).optional(), groupBy: z.enum(["category", "merchant", "funding_account", "payment_channel"]).optional() }).optional(),
  // Offered tool arguments are only a hint: they are validated again by the tool's strict schema when used.
  offer: z.object({ args: z.record(z.string(), z.unknown()), label: z.string().max(120) }).optional(),
});

export interface StoredMessage { id: string; role: "user" | "assistant"; content: string; createdAt: string; answer?: Partial<AskAnswer> }
export interface ConversationSummary { id: string; title: string; updatedAt: string }

export class ConversationStore {
  constructor(private readonly client: SupabaseClient, private readonly userId: string) {}

  private check(error: { code?: string; message?: string } | null) {
    if (!error) return;
    if (isMissingTable(error)) throw new AiSetupError("AI tables are missing");
    throw new AiStoreError(`conversation query failed (${error.code ?? "unknown"})`);
  }

  async exists(id: string): Promise<boolean> {
    const { data, error } = await this.client.from("ai_conversations").select("id").eq("id", id).eq("user_id", this.userId).maybeSingle();
    this.check(error);
    return Boolean(data);
  }

  async create(title: string): Promise<string> {
    const { data, error } = await this.client.from("ai_conversations").insert({ title: title.slice(0, 120), user_id: this.userId }).select("id").single();
    this.check(error);
    return data!.id as string;
  }

  async rename(id: string, title: string) {
    const { error } = await this.client.from("ai_conversations").update({ title: title.slice(0, 120), updated_at: new Date().toISOString() }).eq("id", id).eq("user_id", this.userId);
    this.check(error);
  }

  async append(conversationId: string, role: "user" | "assistant", content: string, metadata: Record<string, unknown> = {}) {
    const { error } = await this.client.from("ai_messages").insert({ conversation_id: conversationId, user_id: this.userId, role, content: content.slice(0, 8000), metadata });
    this.check(error);
  }

  async messages(conversationId: string, limit = 100): Promise<StoredMessage[]> {
    const { data, error } = await this.client.from("ai_messages").select("id, user_id, role, content, metadata, created_at")
      .eq("conversation_id", conversationId).eq("user_id", this.userId).order("created_at", { ascending: false }).limit(limit);
    this.check(error);
    return (data ?? []).filter((r) => r.user_id === this.userId).reverse().map((r) => ({
      id: r.id, role: r.role, content: r.content, createdAt: r.created_at,
      ...(r.role === "assistant" ? { answer: r.metadata as Partial<AskAnswer> } : {}),
    }));
  }

  /** The focus of the latest answer, validated; null if missing or malformed. */
  static focusOf(history: StoredMessage[]): Focus | null {
    const last = [...history].reverse().find((m) => m.role === "assistant");
    const parsed = focusSchema.safeParse(last?.answer?.focus);
    return parsed.success ? (parsed.data as Focus) : null;
  }

  async list(limit = 30): Promise<ConversationSummary[]> {
    const { data, error } = await this.client.from("ai_conversations").select("id, title, updated_at").eq("user_id", this.userId).order("updated_at", { ascending: false }).limit(limit);
    this.check(error);
    return (data ?? []).map((r) => ({ id: r.id, title: r.title, updatedAt: r.updated_at }));
  }

  async remove(id: string): Promise<boolean> {
    const { data, error } = await this.client.from("ai_conversations").delete().eq("id", id).eq("user_id", this.userId).select("id");
    this.check(error);
    return (data ?? []).length > 0;
  }

  /** The user's questions since `since` (for rate limiting). */
  async questionsSince(since: Date): Promise<number> {
    const { count, error } = await this.client.from("ai_messages").select("id", { count: "exact", head: true })
      .eq("user_id", this.userId).eq("role", "user").gte("created_at", since.toISOString());
    this.check(error);
    return count ?? 0;
  }
}

/** A short, non-sensitive title (no amounts or merchants). */
export function titleFor(answer: AskAnswer): string {
  const names: Partial<Record<AskAnswer["meta"]["intent"], string>> = {
    SEARCH: "Transaction search", CALCULATE: "Spending total", COMPARE: "Spending comparison", INVESTIGATE: "Spending investigation",
    SUMMARY: "Weekly summary", ACCOUNT_ANALYSIS: "Funding accounts", PAYMENT_CHANNEL_ANALYSIS: "Payment channels", MERCHANT_ANALYSIS: "Merchants",
    CATEGORY_ANALYSIS: "Categories", UNUSUAL_SPENDING: "Unusual spending", TRANSACTION_DETAIL: "Transaction details",
  };
  const base = names[answer.meta.intent] ?? "Question";
  const period = answer.evidence[0]?.period;
  return period && period !== "All time" ? `${base} · ${period}` : base;
}

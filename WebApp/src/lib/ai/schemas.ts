// Validation for everything that crosses a trust boundary: tool arguments (written by a model — untrusted) and the
// chat request (written by a browser — untrusted). Objects are strict: an unknown key such as `user_id` is rejected,
// never silently used. JSON Schemas for the model are generated from these same definitions (one source of truth).
import { z } from "zod";
import { CATEGORIES, PAYMENT_CHANNELS } from "@/lib/domain/constants";
import type { CategoryId, PaymentChannelId } from "@/lib/domain/types";
import { AI_LIMITS } from "./config";
import { PERIOD_PRESETS, isLocalDate } from "./time";

const localDate = z.string().refine(isLocalDate, "must be a real date as YYYY-MM-DD");
const shortText = (max: number) => z.string().trim().min(1).max(max).refine((s) => !/[\u0000-\u001f]/.test(s), "control characters are not allowed");

export const categorySchema = z.enum(CATEGORIES.map((c) => c.id) as [CategoryId, ...CategoryId[]]);
export const channelSchema = z.enum(PAYMENT_CHANNELS.map((c) => c.id) as [PaymentChannelId, ...PaymentChannelId[]]);
/** Major units (e.g. 15.5 = RM 15.50). */
const amount = z.number().finite().min(0).max(1_000_000_000);

export const periodSchema = z.union([
  z.strictObject({ preset: z.enum(PERIOD_PRESETS).describe("Relative period in the user's time zone") }),
  z.strictObject({ from: localDate.describe("First day, YYYY-MM-DD"), to: localDate.describe("Last day (inclusive), YYYY-MM-DD") })
    .refine((p) => p.from <= p.to, "from must not be after to"),
]);
export type PeriodInput = z.infer<typeof periodSchema>;

const filterShape = {
  period: periodSchema.optional().describe("Date range. Omit for all time."),
  merchant: shortText(80).optional().describe("Merchant name or part of it, e.g. 'Starbucks'"),
  category: categorySchema.optional().describe("One of SpenDrop's categories"),
  fundingAccount: shortText(80).optional().describe("WHERE the money came from, e.g. 'Maybank', 'Touch n Go', 'Cash'. Never a payment channel."),
  paymentChannel: channelSchema.optional().describe("HOW it was paid, e.g. APPLE_PAY, QR_PAYMENT, CARD. Never a bank/account."),
  paymentChannels: z.array(channelSchema).min(1).max(11).optional().describe("Several payment channels at once, e.g. all QR types"),
  currency: shortText(8).optional().describe("Currency code as stored, e.g. 'RM' (Malaysian ringgit), 'USD'"),
  amountMin: amount.optional().describe("Minimum transaction amount in major units"),
  amountMax: amount.optional().describe("Maximum transaction amount in major units"),
  keyword: shortText(80).optional().describe("Text to find in merchant, notes or reference"),
  hasReceipt: z.boolean().optional().describe("Only transactions with (true) or without (false) a receipt image"),
};

export const filtersSchema = z.strictObject(filterShape).refine(
  (f) => f.amountMin === undefined || f.amountMax === undefined || f.amountMin <= f.amountMax, "amountMin must not exceed amountMax");
export type FiltersInput = z.infer<typeof filtersSchema>;

export const searchInputSchema = z.strictObject({
  ...filterShape,
  targetAmount: amount.optional().describe("The amount the user remembers; results are ranked by closeness"),
  targetDate: localDate.optional().describe("The day the user remembers; results are ranked by closeness"),
  sort: z.enum(["relevance", "date_desc", "date_asc", "amount_desc", "amount_asc"]).optional(),
  limit: z.number().int().min(1).max(AI_LIMITS.searchMaxLimit).optional(),
  offset: z.number().int().min(0).max(10_000).optional(),
});

export const calculateInputSchema = z.strictObject({
  ...filterShape,
  operation: z.enum(["sum", "count", "average", "min", "max"]).describe("Calculation done by SpenDrop, never by the model"),
  groupBy: z.enum(["none", "category", "merchant", "funding_account", "payment_channel", "day"]).optional(),
});

export const compareInputSchema = z.strictObject({
  periodA: periodSchema.describe("The period being asked about (usually the more recent one)"),
  periodB: periodSchema.optional().describe("The period to compare with. Omit for the fair previous period"),
  merchant: filterShape.merchant, category: filterShape.category, fundingAccount: filterShape.fundingAccount,
  paymentChannel: filterShape.paymentChannel, paymentChannels: filterShape.paymentChannels, currency: filterShape.currency,
  breakdownBy: z.enum(["category", "merchant", "funding_account", "payment_channel"]).optional().describe("Show what changed by this dimension"),
});

export const getTransactionInputSchema = z.strictObject({
  transactionId: z.string().uuid().describe("An id returned by search_transactions"),
});

export const weeklySummaryInputSchema = z.strictObject({
  weekOf: localDate.optional().describe("Any day in the week (Monday–Sunday). Omit for the current week"),
});

export const unusualInputSchema = z.strictObject({
  period: periodSchema.optional().describe("Period to check. Omit for the current week"),
});

export const insightsInputSchema = z.strictObject({
  period: z.enum(["this_week", "this_month"]).optional().describe("Compare this week or this month so far with the user's own normal. Default this_month"),
  merchant: filterShape.merchant, category: filterShape.category, fundingAccount: filterShape.fundingAccount,
  paymentChannel: filterShape.paymentChannel, paymentChannels: filterShape.paymentChannels, currency: filterShape.currency,
});

/** POST /api/ai/chat body. Strict: a `userId`/`user_id` (or any other extra field) is rejected. */
export const chatRequestSchema = z.strictObject({
  message: z.string().trim().min(1).max(AI_LIMITS.maxMessageChars),
  conversationId: z.string().uuid().optional(),
  timeZone: z.string().max(64).optional(),
});
export type ChatRequest = z.infer<typeof chatRequestSchema>;

/** Short, safe description of a validation problem (field + message, never the raw input). */
export function describeIssues(error: z.ZodError): string {
  return error.issues.slice(0, 3).map((i) => `${i.path.join(".") || "input"}: ${i.code === "unrecognized_keys" ? `unknown field(s) ${(i as { keys: string[] }).keys.join(", ")}` : i.message}`).join("; ");
}

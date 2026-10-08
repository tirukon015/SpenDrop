// Central tool registry: name, precise description, permission, input schema, timeout and handler for every tool
// the model (or the deterministic planner) may call. executeTool() is the ONLY way a tool runs: it validates the
// untrusted arguments, checks the permission, enforces the timeout and turns any failure into a controlled error.
// The user scope is the AiContext argument — it is never part of the tool input.
import { z } from "zod";
import { AI_LIMITS } from "./config";
import { invariantViolations } from "./invariants";
import { DataUnavailableError, type FinanceRepository } from "./repository";
import {
  calculateInputSchema, compareInputSchema, describeIssues, getTransactionInputSchema, insightsInputSchema, searchInputSchema, unusualInputSchema,
  weeklySummaryInputSchema,
} from "./schemas";
import { getSpendingInsights } from "./insights";
import { calculateSpending, comparePeriods, findUnusualSpending, getTransaction, getWeeklySummary, searchTransactions } from "./tools";
import type { AiContext, ToolResult } from "./types";

export type Permission = "READ_FINANCIAL_DATA" | "READ_ANALYTICS" | "READ_RECEIPTS" | "READ_MEMORY" | "WRITE_TRANSACTION" | "WRITE_CATEGORY" | "WRITE_MEMORY";

/** The MVP is read-only: no write permission is granted to SpenDrop AI. */
export const ENABLED_PERMISSIONS: readonly Permission[] = ["READ_FINANCIAL_DATA", "READ_ANALYTICS", "READ_RECEIPTS"];

interface ToolDefinition {
  name: string;
  description: string;
  permission: Permission;
  schema: z.ZodType;
  timeoutMs: number;
  handler: (input: never, ctx: AiContext, repo: FinanceRepository) => Promise<ToolResult>;
}

const define = <S extends z.ZodType>(d: Omit<ToolDefinition, "schema" | "handler"> & { schema: S; handler: (input: z.infer<S>, ctx: AiContext, repo: FinanceRepository) => Promise<ToolResult> }) =>
  d as unknown as ToolDefinition;

export const TOOLS: readonly ToolDefinition[] = [
  define({
    name: "search_transactions",
    description:
      "Find the authenticated user's own expense transactions using optional date, amount, merchant, category, funding account, payment channel, currency, keyword and receipt filters. " +
      "Use targetAmount/targetDate for 'where did my RM15 go' style lookups (results are ranked by closeness). Returns at most `limit` rows plus the total match count.",
    permission: "READ_FINANCIAL_DATA", schema: searchInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: searchTransactions,
  }),
  define({
    name: "calculate_spending",
    description:
      "Calculate the authenticated user's spending exactly (sum, count, average, min or max), optionally grouped by category, merchant, funding_account, payment_channel or day. " +
      "Totals are per currency and are never added across currencies. Always use this for any total — never add numbers yourself.",
    permission: "READ_ANALYTICS", schema: calculateInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: calculateSpending,
  }),
  define({
    name: "compare_periods",
    description:
      "Compare the authenticated user's spending in two periods (difference, percentage, counts) with the biggest changes by category/merchant/account/channel and the largest transactions. " +
      "Omit periodB to compare with the fair previous period (an in-progress month is compared with the same days of last month).",
    permission: "READ_ANALYTICS", schema: compareInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: comparePeriods,
  }),
  define({
    name: "get_transaction",
    description: "Get one of the authenticated user's transactions by the id returned from search_transactions: amount, date, merchant, category, funding account, payment channel, split, note and whether a receipt exists.",
    permission: "READ_RECEIPTS", schema: getTransactionInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: getTransaction,
  }),
  define({
    name: "get_weekly_summary",
    description: "Weekly summary of the authenticated user's spending (Monday–Sunday): total, change vs last week and vs the 4-week average, categories, largest transaction, spending by day, top merchants, accounts and payment channels.",
    permission: "READ_ANALYTICS", schema: weeklySummaryInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: getWeeklySummary,
  }),
  define({
    name: "find_unusual_spending",
    description:
      "Find spending that is unusual compared with the authenticated user's OWN previous 8 weeks: spikes in total or per category, unusually large transactions for their category and new merchants. " +
      "Reports when there is not enough history. Never use it to claim fraud.",
    permission: "READ_ANALYTICS", schema: unusualInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: findUnusualSpending,
  }),
  define({
    name: "get_spending_insights",
    description:
      "Compare the authenticated user's spending this month (or week) so far with their OWN normal — the average of the same days in previous months/weeks: " +
      "total change, categories and merchants that changed most, larger-than-usual purchases, small payments that add up, weekend vs weekday. " +
      "Use it for 'why am I spending so much', 'how am I doing', 'what's going wrong with my spending'. Reports when there isn't enough history.",
    permission: "READ_ANALYTICS", schema: insightsInputSchema, timeoutMs: AI_LIMITS.toolTimeoutMs, handler: getSpendingInsights,
  }),
];

export type ToolName = (typeof TOOLS)[number]["name"];
export const toolByName = (name: string) => TOOLS.find((t) => t.name === name);

export interface ExecutedTool { name: string; args: unknown; result: ToolResult; ms: number }

const timeout = <T>(promise: Promise<T>, ms: number) =>
  new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("tool timeout")), ms);
    promise.then((v) => { clearTimeout(t); resolve(v); }, (e) => { clearTimeout(t); reject(e); });
  });

/**
 * Runs one tool for the authenticated user. `rawArgs` is untrusted (model output): it is validated against the
 * tool's strict schema — a `user_id`/`userId` field, unknown tool, bad date or out-of-range limit is rejected.
 */
export async function executeTool(name: string, rawArgs: unknown, ctx: AiContext, repo: FinanceRepository, permissions: readonly Permission[] = ENABLED_PERMISSIONS): Promise<ExecutedTool> {
  const started = Date.now();
  const done = (result: ToolResult): ExecutedTool => ({ name, args: rawArgs, result, ms: Date.now() - started });
  const tool = toolByName(name);
  if (!tool) return done({ ok: false, error: { kind: "validation", message: `Unknown tool "${String(name).slice(0, 40)}".` } });
  if (!permissions.includes(tool.permission)) return done({ ok: false, error: { kind: "permission", message: "That action isn't allowed." } });
  const parsed = tool.schema.safeParse(rawArgs ?? {});
  if (!parsed.success) return done({ ok: false, error: { kind: "validation", message: `Invalid arguments: ${describeIssues(parsed.error)}` } });
  try {
    const result = await timeout(tool.handler(parsed.data as never, ctx, repo), tool.timeoutMs);
    // A result whose figures don't match its own dataset is never shown.
    const problems = result.ok ? invariantViolations(tool.name, result.data) : [];
    if (problems.length) {
      console.error(`[ai][invariant] ${tool.name} (request ${ctx.requestId}): ${problems.slice(0, 3).join("; ")}`);
      return done({ ok: false, error: { kind: "unavailable", message: "I couldn't verify that calculation, so I'm not showing it." } });
    }
    return done(result);
  } catch (error) {
    if (error instanceof Error && error.message === "tool timeout") return done({ ok: false, error: { kind: "timeout", message: "Checking your transactions took too long." } });
    // Never leak database/stack details: log the category server-side, return a plain message.
    console.error(`[ai] tool ${name} failed (request ${ctx.requestId}):`, error instanceof DataUnavailableError ? error.message : error instanceof Error ? error.name : "error");
    return done({ ok: false, error: { kind: "unavailable", message: "I couldn't access your transaction data right now." } });
  }
}

/** Tool definitions for the model, generated from the same strict schemas used for validation. */
export function toolSpecs() {
  return TOOLS.filter((t) => ENABLED_PERMISSIONS.includes(t.permission)).map((t) => ({
    name: t.name,
    description: t.description,
    parameters: z.toJSONSchema(t.schema, { io: "input", unrepresentable: "any" }) as Record<string, unknown>,
  }));
}

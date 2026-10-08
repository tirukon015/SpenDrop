// Proactive insights: the same deterministic insight tool, run for this week and this month, reduced to at most two
// meaningful notices. Used by GET /api/ai/insights and by the browser demo.
import { proactiveNotices } from "./compose";
import type { InsightsData } from "./insights";
import { executeTool } from "./registry";
import type { FinanceRepository } from "./repository";
import type { AiContext } from "./types";

export interface Notice { title: string; detail: string; ask: string }

export async function proactiveNoticesFor(ctx: AiContext, repo: FinanceRepository): Promise<Notice[]> {
  const out: Notice[] = [];
  for (const period of ["this_week", "this_month"] as const) {
    const r = await executeTool("get_spending_insights", { period }, ctx, repo);
    if (r.result.ok) out.push(...proactiveNotices(r.result.data as InsightsData));
  }
  // One notice per subject (a category higher this week and this month is said once).
  const seen = new Set<string>();
  return out.filter((n) => { const k = n.title.replace(/ this (week|month)$/, ""); if (seen.has(k)) return false; seen.add(k); return true; }).slice(0, 2);
}

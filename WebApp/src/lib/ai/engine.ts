// Server orchestration of one question (hybrid routing, master prompt §14/§53): SpenDrop's deterministic tools
// answer everything the planner understands (exact, instant, free); only the rest goes to the configured model,
// which can use the same validated, user-scoped tools. With no model configured, the user gets a helpful
// "here's what I can answer" reply — never a guess.
import { answerDeterministic, capabilitiesAnswer } from "./core";
import { answerWithModel, type HistoryTurn } from "./model";
import type { ChatProvider } from "./providers/types";
import type { FinanceRepository, MemoryStore } from "./repository";
import type { AiContext, AskAnswer, Focus } from "./types";

export async function ask(p: {
  message: string; ctx: AiContext; repo: FinanceRepository; provider: ChatProvider | null; history: HistoryTurn[]; focus: Focus | null; memory?: MemoryStore | null;
}): Promise<AskAnswer> {
  const deterministic = await answerDeterministic(p.message, p.ctx, p.repo, p.focus, p.memory ?? null);
  if (deterministic.kind === "answer") return deterministic.answer;
  if (!p.provider) return capabilitiesAnswer(p.ctx, deterministic.general);
  return answerWithModel({ message: p.message, ctx: p.ctx, repo: p.repo, provider: p.provider, history: p.history, focus: p.focus });
}

/** One structured log line per question: ids, route, tools and timings — never amounts, merchants or tokens. */
export function logRequest(a: AskAnswer, extra: { userId: string; conversationId: string | null }) {
  console.info(JSON.stringify({
    event: "ai_request", requestId: a.meta.requestId, userId: extra.userId, conversationId: extra.conversationId, intent: a.meta.intent,
    route: a.meta.route, provider: a.meta.provider, model: a.meta.model, status: a.status, tools: a.meta.tools, totalMs: a.meta.totalMs,
    groundingFallback: a.meta.groundingFallback ?? false, tokens: a.meta.tokens,
  }));
}

// POST /api/ai/chat, as a plain function with injectable dependencies so the security rules can be tested:
//   1. same-origin JSON only; body size capped; strict schema (a `userId`/`user_id` field is rejected)
//   2. user id ONLY from the verified session (authenticate())
//   3. per-user rate limit
//   4. the conversation must belong to the user (otherwise 404, indistinguishable from "doesn't exist")
//   5. the AI context, repository and store are all bound to that user id
import { AI_RATE_LIMITS } from "./config";
import { AiSetupError, ConversationStore, titleFor } from "./conversations";
import { ask, logRequest } from "./engine";
import type { HistoryTurn } from "./model";
import type { ChatProvider } from "./providers/types";
import type { FinanceRepository, MemoryStore } from "./repository";
import { chatRequestSchema, describeIssues } from "./schemas";
import { error, json, sameOrigin, type AuthResult } from "./server";
import { DEFAULT_TIME_ZONE, isValidTimeZone, localDateOf } from "./time";
import type { AiContext, AskAnswer } from "./types";

export interface ChatDeps {
  authenticate: (request: Request) => Promise<AuthResult>;
  repository: (auth: Extract<AuthResult, { ok: true }>) => FinanceRepository;
  store: (auth: Extract<AuthResult, { ok: true }>) => Pick<ConversationStore, "exists" | "create" | "rename" | "append" | "messages" | "questionsSince">;
  /** The user's own personal memory (rules). Bound to the authenticated user like everything else. */
  memory?: (auth: Extract<AuthResult, { ok: true }>) => MemoryStore;
  provider: () => ChatProvider | null;
  debug: boolean;
}

const MAX_BODY = 4096;

/** What the browser receives: the answer, minus internal diagnostics unless debugging. */
export function publicAnswer(a: AskAnswer, debug: boolean): AskAnswer {
  if (debug) return a;
  return { ...a, meta: { requestId: a.meta.requestId, intent: a.meta.intent, route: a.meta.route, provider: a.meta.provider, tools: a.meta.tools.map((t) => ({ ...t, ms: 0 })), totalMs: 0 } };
}

export async function handleChat(request: Request, deps: ChatDeps): Promise<Response> {
  if (!sameOrigin(request)) return error(403, "Cross-site requests aren't allowed.", "forbidden_origin");
  if (!(request.headers.get("content-type") ?? "").includes("application/json")) return error(415, "Send JSON.", "unsupported_media_type");
  const raw = await request.text();
  if (raw.length > MAX_BODY) return error(413, "That message is too long.", "too_large");
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return error(400, "Invalid JSON.", "invalid_json");
  }
  const parsed = chatRequestSchema.safeParse(body);
  if (!parsed.success) return error(400, `Invalid request: ${describeIssues(parsed.error)}`, "invalid_request");

  const auth = await deps.authenticate(request);
  if (!auth.ok) return auth.response;

  const timeZone = parsed.data.timeZone && isValidTimeZone(parsed.data.timeZone) ? parsed.data.timeZone : DEFAULT_TIME_ZONE;
  const ctx: AiContext = Object.freeze({ userId: auth.userId, timeZone, today: localDateOf(new Date(), timeZone), requestId: crypto.randomUUID() });
  const store = deps.store(auth);

  try {
    const now = Date.now();
    const [minute, hour] = await Promise.all([store.questionsSince(new Date(now - 60_000)), store.questionsSince(new Date(now - 3_600_000))]);
    if (minute >= AI_RATE_LIMITS.perMinute || hour >= AI_RATE_LIMITS.perHour)
      return error(429, "You're asking very quickly — please wait a moment and try again.", "rate_limited");

    let conversationId = parsed.data.conversationId ?? null;
    if (conversationId && !(await store.exists(conversationId))) return error(404, "That conversation wasn't found.", "conversation_not_found");
    const isNew = !conversationId;
    if (!conversationId) conversationId = await store.create("New conversation");

    const stored = isNew ? [] : await store.messages(conversationId, 20);
    const history: HistoryTurn[] = stored.map((m) => ({ role: m.role, content: m.content }));
    const focus = ConversationStore.focusOf(stored);
    await store.append(conversationId, "user", parsed.data.message);

    const answer = await ask({ message: parsed.data.message, ctx, repo: deps.repository(auth), provider: deps.provider(), history, focus, memory: deps.memory?.(auth) ?? null });
    const { meta, ...rest } = answer;
    await store.append(conversationId, "assistant", answer.text, { ...rest, meta: { requestId: meta.requestId, intent: meta.intent, route: meta.route, provider: meta.provider, model: meta.model, tools: meta.tools } });
    if (isNew) await store.rename(conversationId, titleFor(answer));
    logRequest(answer, { userId: ctx.userId, conversationId });
    return json({ conversationId, answer: publicAnswer(answer, deps.debug) });
  } catch (e) {
    if (e instanceof AiSetupError)
      return error(503, "SpenDrop AI isn't set up on this database yet. Apply Supabase/supabase/migrations/20261009000000_spendrop_ai.sql.", "not_set_up");
    console.error(`[ai] chat failed (request ${ctx.requestId}): ${e instanceof Error ? e.name : "error"}`);
    return error(500, "I'm having trouble processing that right now. Your financial data is still safe.", "internal");
  }
}

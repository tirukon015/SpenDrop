// GET /api/ai/conversations/:id — messages of one of YOUR conversations. DELETE removes it (and its messages).
// Another user's id is "not found" (RLS + explicit user filter), never revealed.
import { z } from "zod";
import { ConversationStore } from "@/lib/ai/conversations";
import { authenticate, error, json, sameOrigin } from "@/lib/ai/server";

const id = z.string().uuid();

export async function GET(request: Request, ctx: { params: Promise<{ id: string }> }) {
  const parsed = id.safeParse((await ctx.params).id);
  if (!parsed.success) return error(404, "That conversation wasn't found.", "conversation_not_found");
  const auth = await authenticate(request);
  if (!auth.ok) return auth.response;
  try {
    const store = new ConversationStore(auth.client, auth.userId);
    if (!(await store.exists(parsed.data))) return error(404, "That conversation wasn't found.", "conversation_not_found");
    return json({ messages: await store.messages(parsed.data) });
  } catch {
    return error(500, "Couldn't load that conversation.", "internal");
  }
}

export async function DELETE(request: Request, ctx: { params: Promise<{ id: string }> }) {
  if (!sameOrigin(request)) return error(403, "Cross-site requests aren't allowed.", "forbidden_origin");
  const parsed = id.safeParse((await ctx.params).id);
  if (!parsed.success) return error(404, "That conversation wasn't found.", "conversation_not_found");
  const auth = await authenticate(request);
  if (!auth.ok) return auth.response;
  try {
    const removed = await new ConversationStore(auth.client, auth.userId).remove(parsed.data);
    return removed ? json({ deleted: true }) : error(404, "That conversation wasn't found.", "conversation_not_found");
  } catch {
    return error(500, "Couldn't delete that conversation.", "internal");
  }
}

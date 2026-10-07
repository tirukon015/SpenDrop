// GET /api/ai/conversations — the signed-in user's own recent conversations.
import { AiSetupError, ConversationStore } from "@/lib/ai/conversations";
import { authenticate, error, json } from "@/lib/ai/server";

export async function GET() {
  const auth = await authenticate();
  if (!auth.ok) return auth.response;
  try {
    return json({ conversations: await new ConversationStore(auth.client, auth.userId).list() });
  } catch (e) {
    if (e instanceof AiSetupError) return json({ conversations: [], setupRequired: true });
    return error(500, "Couldn't load your conversations.", "internal");
  }
}

// POST /api/ai/chat — ask SpenDrop AI a question about your own money. See lib/ai/chat-handler.ts for the rules.
import { handleChat } from "@/lib/ai/chat-handler";
import { ConversationStore } from "@/lib/ai/conversations";
import { getProvider, serverConfig } from "@/lib/ai/providers";
import { authenticate } from "@/lib/ai/server";
import { SupabaseMemoryStore, SupabaseRepository } from "@/lib/ai/supabase-repository";

export const maxDuration = 60;

export async function POST(request: Request) {
  return handleChat(request, {
    authenticate,
    repository: (auth) => new SupabaseRepository(auth.client, auth.userId),
    store: (auth) => new ConversationStore(auth.client, auth.userId),
    memory: (auth) => new SupabaseMemoryStore(auth.client, auth.userId),
    provider: getProvider,
    debug: serverConfig().debug,
  });
}

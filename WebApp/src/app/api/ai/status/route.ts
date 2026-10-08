// GET /api/ai/status — which answer engine is configured (for the Ask screen). No secrets: provider and model name only.
import { getProvider, serverConfig } from "@/lib/ai/providers";
import { authenticate, json } from "@/lib/ai/server";

export async function GET(request: Request) {
  const auth = await authenticate(request);
  if (!auth.ok) return auth.response;
  const config = serverConfig();
  const provider = getProvider();
  return json({ provider: config.provider, model: config.model, available: provider ? await provider.available() : true, debug: config.debug });
}

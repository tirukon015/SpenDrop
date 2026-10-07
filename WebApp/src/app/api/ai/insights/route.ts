// GET /api/ai/insights — "I noticed…" cards for the Ask screen: at most two, only when the signed-in user's own
// data shows a meaningful change against their own normal (none is a perfectly good answer).
import { proactiveNoticesFor } from "@/lib/ai/proactive";
import { authenticate, error, json } from "@/lib/ai/server";
import { SupabaseRepository } from "@/lib/ai/supabase-repository";
import { DEFAULT_TIME_ZONE, isValidTimeZone, localDateOf } from "@/lib/ai/time";

export async function GET(request: Request) {
  const auth = await authenticate(request);
  if (!auth.ok) return auth.response;
  const tz = new URL(request.url).searchParams.get("tz") ?? "";
  const timeZone = isValidTimeZone(tz) ? tz : DEFAULT_TIME_ZONE;
  try {
    const ctx = { userId: auth.userId, timeZone, today: localDateOf(new Date(), timeZone), requestId: crypto.randomUUID() };
    return json({ notices: await proactiveNoticesFor(ctx, new SupabaseRepository(auth.client, auth.userId)) });
  } catch {
    return error(500, "Couldn't check for insights.", "internal");
  }
}

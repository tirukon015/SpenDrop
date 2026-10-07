// Request plumbing shared by the /api/ai routes: authentication (user id from the verified Supabase session — never
// from the request body), same-origin checks and safe JSON errors.
import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { isDemoMode, isSupabaseConfigured } from "@/lib/supabase/config";

export const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" } });
export const error = (status: number, message: string, code: string) => json({ error: { code, message } }, status);

/** Rejects cross-site requests (CSRF): a browser always sends Origin on POST/DELETE; it must be this site. */
export function sameOrigin(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return request.method === "GET";
  try {
    const host = request.headers.get("x-forwarded-host") ?? request.headers.get("host");
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

export type AuthResult = { ok: true; client: SupabaseClient; userId: string } | { ok: false; response: Response };

/** The signed-in user, verified by Supabase Auth (getClaims validates the JWT). */
export async function authenticate(): Promise<AuthResult> {
  if (isDemoMode) return { ok: false, response: error(400, "The demo answers questions in your browser.", "demo_mode") };
  if (!isSupabaseConfigured) return { ok: false, response: error(503, "SpenDrop isn't connected to its database.", "not_configured") };
  const client = await createClient();
  const { data, error: authError } = await client.auth.getClaims();
  const userId = data?.claims?.sub;
  if (authError || typeof userId !== "string" || !/^[0-9a-f-]{36}$/i.test(userId))
    return { ok: false, response: error(401, "Please sign in to use SpenDrop AI.", "unauthenticated") };
  return { ok: true, client, userId };
}

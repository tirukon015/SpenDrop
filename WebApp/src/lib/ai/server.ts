// Request plumbing shared by the /api/ai routes: authentication (user id from the verified Supabase session — never
// from the request body), same-origin checks and safe JSON errors.
//
// Two ways to authenticate, one rule: the user id comes ONLY from a JWT that Supabase Auth has verified.
//   • Web: the Supabase session cookie (same-origin requests).
//   • iOS / Android: `Authorization: Bearer <Supabase access token>`. The token is verified with getClaims(), and the
//     database client sends that same token, so Row Level Security sees the same user. Cookies are ignored then.
import { createClient as createSupabaseClient, type SupabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { isDemoMode, isSupabaseConfigured, supabasePublicKey, supabaseUrl } from "@/lib/supabase/config";

export const json = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" } });
export const error = (status: number, message: string, code: string) => json({ error: { code, message } }, status);

/** Rejects cross-site requests (CSRF): a browser always sends Origin on POST/DELETE; it must be this site. */
export function sameOrigin(request: Request): boolean {
  // A bearer token is never sent automatically by a browser, so a request carrying one can't be forged cross-site.
  if (bearerToken(request)) return true;
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

const JWT = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

/** The access token of an `Authorization: Bearer …` header, if it has the shape of a JWT. */
export function bearerToken(request: Request): string | null {
  const m = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization")?.trim() ?? "");
  return m && m[1].length <= 8192 && JWT.test(m[1]) ? m[1] : null;
}

const unauthenticated = (): AuthResult => ({ ok: false, response: error(401, "Please sign in to use SpenDrop AI.", "unauthenticated") });

/** The signed-in user, verified by Supabase Auth (getClaims validates the JWT's signature and expiry). */
export async function authenticate(request?: Request): Promise<AuthResult> {
  if (isDemoMode) return { ok: false, response: error(400, "The demo answers questions in your browser.", "demo_mode") };
  if (!isSupabaseConfigured) return { ok: false, response: error(503, "SpenDrop isn't connected to its database.", "not_configured") };
  // A malformed Authorization header is rejected outright (never silently falls back to cookies).
  if (request?.headers.has("authorization") && !bearerToken(request)) return unauthenticated();
  const token = request ? bearerToken(request) : null;
  const client = token
    ? createSupabaseClient(supabaseUrl, supabasePublicKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      })
    : await createClient();
  const { data, error: authError } = token ? await client.auth.getClaims(token) : await client.auth.getClaims();
  const claims = data?.claims;
  const userId = claims?.sub;
  if (authError || !claims || typeof userId !== "string" || !/^[0-9a-f-]{36}$/i.test(userId)) return unauthenticated();
  // Only a signed-in user's token (never the public anon key), and never an expired one.
  if (claims.role !== "authenticated" || (typeof claims.exp === "number" && claims.exp * 1000 <= Date.now())) return unauthenticated();
  return { ok: true, client, userId };
}

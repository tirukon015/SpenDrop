import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isDemoMode, isSupabaseConfigured, supabasePublicKey, supabaseUrl } from "./config";

/** Paths that never require a signed-in user. */
const PUBLIC_PATHS = ["/login", "/auth", "/offline", "/manifest.webmanifest", "/sw.js", "/icons"];
/** API routes authenticate every request themselves and answer 401 JSON instead of redirecting to the login page. */
const API_PREFIX = "/api/";

function isPublic(pathname: string) {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

/**
 * Runs in proxy.ts on every page request: refreshes the Supabase session cookie (getClaims validates the JWT)
 * and sends signed-out visitors to /login. Authorisation of the data itself is enforced by RLS in the database.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  if (isDemoMode || !isSupabaseConfigured) {
    // Demo mode needs no account; an unconfigured build shows a setup message on /login.
    if (!isDemoMode && !isPublic(request.nextUrl.pathname)) {
      return NextResponse.redirect(new URL("/login", request.url));
    }
    return response;
  }

  const supabase = createServerClient(supabaseUrl, supabasePublicKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  // Do not run code between createServerClient and getClaims (session refresh must happen first).
  const { data } = await supabase.auth.getClaims();
  const signedIn = Boolean(data?.claims?.sub);
  const { pathname, search } = request.nextUrl;

  if (!signedIn && !isPublic(pathname) && !pathname.startsWith(API_PREFIX)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = pathname === "/" ? "" : `?next=${encodeURIComponent(pathname + search)}`;
    return NextResponse.redirect(url);
  }
  if (signedIn && pathname === "/login") {
    return NextResponse.redirect(new URL("/", request.url));
  }
  return response;
}

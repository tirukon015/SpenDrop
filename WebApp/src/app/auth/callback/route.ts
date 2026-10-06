import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

/** Only same-site relative paths are allowed as the post-login destination (no open redirects). */
function safeNext(value: string | null) {
  return value && value.startsWith("/") && !value.startsWith("//") ? value : "/";
}

/** OAuth (Google) and email-link PKCE callback: exchanges the one-time code for a session cookie. */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = safeNext(searchParams.get("next"));
  const providerError = searchParams.get("error_description") ?? searchParams.get("error");

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${next}`);
    return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent("That sign-in link has expired or was already used. Please sign in again.")}`);
  }
  const message = providerError ? "Sign-in was cancelled or failed. Please try again." : "Missing sign-in code.";
  return NextResponse.redirect(`${origin}/login?error=${encodeURIComponent(message)}`);
}

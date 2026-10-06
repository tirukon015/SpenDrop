// Public client configuration only. Never put a service-role key, database password or any other secret in a
// NEXT_PUBLIC_* variable: everything here is shipped to the browser. Access is protected by RLS on the server.
export const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
/** Supabase "publishable" key (preferred) or the legacy anon key. Both are safe to expose; RLS does the protecting. */
export const supabasePublicKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

export const isSupabaseConfigured = supabaseUrl.length > 0 && supabasePublicKey.length > 0;

/**
 * Local demo mode for development and browser testing without a Supabase project: synthetic data kept in this
 * browser only, clearly labelled in the UI. Never enabled unless NEXT_PUBLIC_SPENDROP_DEMO=1 is set explicitly.
 */
export const isDemoMode = process.env.NEXT_PUBLIC_SPENDROP_DEMO === "1";

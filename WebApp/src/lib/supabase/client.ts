"use client";

import { createBrowserClient } from "@supabase/ssr";
import { supabasePublicKey, supabaseUrl } from "./config";

/** Browser Supabase client (singleton inside @supabase/ssr). Session lives in cookies managed by proxy.ts. */
export function createClient() {
  return createBrowserClient(supabaseUrl, supabasePublicKey);
}

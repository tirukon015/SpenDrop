import type { Metadata } from "next";
import { Suspense } from "react";
import { AuthExperience, type AuthMode } from "./auth-experience";
import { isDemoMode, isSupabaseConfigured } from "@/lib/supabase/config";

export const metadata: Metadata = { title: "Sign in" };

type Search = Promise<{ error?: string; next?: string; deleted?: string; mode?: string }>;

function modeFrom(value?: string): AuthMode {
  return value === "signup" ? "signUp" : value === "reset" ? "forgot" : "signIn";
}

/** Reads the query string at request time (streamed behind Suspense; the shell around it is static). */
async function AuthContent({ searchParams }: { searchParams: Search }) {
  const { error, next, deleted, mode } = await searchParams;
  const safeNext = next?.startsWith("/") && !next.startsWith("//") ? next : "/";
  return (
    <>
      {deleted && (
        <p role="status" className="glass mb-4 rounded-2xl px-4 py-3 text-center text-sm">Your account and cloud data were deleted.</p>
      )}
      <AuthExperience configured={isSupabaseConfigured} demo={isDemoMode} initialError={error ?? null} initialMode={modeFrom(mode)} next={safeNext} />
    </>
  );
}

export default function LoginPage({ searchParams }: { searchParams: Search }) {
  return (
    <main id="main" className="auth-shell flex px-4 py-10 pt-safe pb-safe sm:px-6">
      <div className="auth-light auth-light--1" aria-hidden />
      <div className="auth-light auth-light--2" aria-hidden />
      <div className="auth-light auth-light--3" aria-hidden />
      <div className="auth-texture" aria-hidden />
      <div className="m-auto flex w-full flex-col items-center py-2">
        <Suspense fallback={<div className="glass h-[640px] w-full max-w-[980px] rounded-[28px]" aria-hidden />}>
          <AuthContent searchParams={searchParams} />
        </Suspense>
      </div>
    </main>
  );
}

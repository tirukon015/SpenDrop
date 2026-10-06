import type { Metadata } from "next";
import { Suspense } from "react";
import { BrandMark } from "@/components/brand";
import { LoginForm } from "./login-form";
import { isDemoMode, isSupabaseConfigured } from "@/lib/supabase/config";

export const metadata: Metadata = { title: "Sign in" };

type Search = Promise<{ error?: string; next?: string; deleted?: string }>;

/** Reads the query string at request time (streamed behind Suspense; the rest of the page is static). */
async function LoginContent({ searchParams }: { searchParams: Search }) {
  const { error, next, deleted } = await searchParams;
  return (
    <>
      {deleted && <p role="status" className="mb-4 rounded-field bg-card p-3 text-center text-sm shadow-card">Your account and cloud data were deleted.</p>}
      <LoginForm configured={isSupabaseConfigured} demo={isDemoMode} initialError={error ?? null} next={next?.startsWith("/") && !next.startsWith("//") ? next : "/"} />
    </>
  );
}

export default function LoginPage({ searchParams }: { searchParams: Search }) {
  return (
    <main id="main" className="flex min-h-dvh items-center justify-center px-4 py-10 pt-safe">
      <div className="w-full max-w-[400px]">
        <div className="mb-8 flex flex-col items-center gap-3 text-center">
          <BrandMark size={64} />
          <div>
            <h1 className="text-[28px] font-bold tracking-tight">SpenDrop</h1>
            <p className="text-label-2">One SpenDrop account. One financial data set. Every device.</p>
          </div>
        </div>
        <Suspense fallback={<div className="h-72" aria-hidden />}>
          <LoginContent searchParams={searchParams} />
        </Suspense>
        <p className="mt-6 text-center text-xs text-label-2">Your financial data is private to your account. SpenDrop never sells or shares it.</p>
      </div>
    </main>
  );
}

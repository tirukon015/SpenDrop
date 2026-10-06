"use client";

import { Mail } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button, Card, ErrorBanner, Input, Segmented } from "@/components/ui/primitives";
import { createClient } from "@/lib/supabase/client";

type Mode = "signIn" | "signUp" | "forgot";

function GoogleLogo() {
  return (
    <svg aria-hidden viewBox="0 0 18 18" className="size-[18px]">
      <path fill="#4285F4" d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.48h4.84a4.14 4.14 0 0 1-1.8 2.72v2.26h2.92c1.7-1.57 2.68-3.88 2.68-6.62z" />
      <path fill="#34A853" d="M9 18c2.43 0 4.47-.8 5.96-2.18l-2.92-2.26c-.8.54-1.84.86-3.04.86-2.34 0-4.32-1.58-5.03-3.7H.96v2.33A9 9 0 0 0 9 18z" />
      <path fill="#FBBC05" d="M3.97 10.72A5.4 5.4 0 0 1 3.68 9c0-.6.1-1.18.29-1.72V4.95H.96A9 9 0 0 0 0 9c0 1.45.35 2.83.96 4.05l3.01-2.33z" />
      <path fill="#EA4335" d="M9 3.58c1.32 0 2.5.45 3.44 1.35l2.58-2.58A9 9 0 0 0 .96 4.95l3.01 2.33C4.68 5.16 6.66 3.58 9 3.58z" />
    </svg>
  );
}

export function LoginForm({ configured, demo, initialError, next }: { configured: boolean; demo: boolean; initialError: string | null; next: string }) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("signIn");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(initialError);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState<"google" | "email" | null>(null);

  if (demo) {
    return (
      <Card className="flex flex-col gap-3 text-center">
        <p className="font-semibold">Demo mode</p>
        <p className="text-sm text-label-2">This build uses synthetic data stored only in this browser. No account needed.</p>
        <Link href="/" className="rounded-control bg-[var(--sd-accent-fill)] py-3 font-semibold text-white">Open the demo</Link>
      </Card>
    );
  }
  if (!configured) {
    return (
      <Card className="flex flex-col gap-2">
        <p className="font-semibold">Sign-in isn&apos;t set up for this site yet</p>
        <p className="text-sm text-label-2">
          Set <code>NEXT_PUBLIC_SUPABASE_URL</code> and <code>NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY</code> (see <code>WebApp/.env.example</code> and
          Docs/WebApp-Setup.md), then reload.
        </p>
      </Card>
    );
  }

  const callback = (path = next) => `${window.location.origin}/auth/callback?next=${encodeURIComponent(path)}`;
  const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  const passwordProblem =
    mode === "forgot" ? null
      : password.length < 8 ? "Use at least 8 characters."
        : mode === "signUp" && password !== confirm ? "Passwords don't match." : null;

  async function google() {
    setBusy("google");
    setError(null);
    const { error } = await createClient().auth.signInWithOAuth({ provider: "google", options: { redirectTo: callback() } });
    if (error) {
      setError(error.message.includes("provider is not enabled") ? "Google sign-in isn't enabled for this project yet." : "Couldn't start Google sign-in. Please try again.");
      setBusy(null);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setMessage(null);
    if (!validEmail) return setError("Enter a valid email address.");
    if (passwordProblem) return setError(passwordProblem);
    setBusy("email");
    const supabase = createClient();
    try {
      if (mode === "signIn") {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw error;
        router.replace(next);
        router.refresh();
        return;
      }
      if (mode === "signUp") {
        const { data, error } = await supabase.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: callback("/") } });
        if (error) throw error;
        if (data.session) {
          router.replace("/");
          router.refresh();
          return;
        }
        setMessage("Check your email to confirm your account, then come back and sign in.");
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: callback("/auth/update-password") });
        if (error) throw error;
        setMessage("If an account exists for that email, a reset link is on its way.");
      }
    } catch (e) {
      const text = e instanceof Error ? e.message : "";
      setError(
        /invalid login credentials/i.test(text) ? "Email or password is incorrect."
          : /email not confirmed/i.test(text) ? "Please confirm your email first — check your inbox."
            : /already registered/i.test(text) ? "An account with this email already exists. Sign in instead."
              : /rate limit/i.test(text) ? "Too many attempts. Please wait a minute and try again."
                : /fetch|network/i.test(text) ? "You're offline or SpenDrop can't be reached. Try again."
                  : "That didn't work. Please try again.",
      );
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      {error && <ErrorBanner message={error} />}
      {message && <p role="status" className="rounded-field bg-[color-mix(in_srgb,var(--sd-green)_14%,transparent)] p-3 text-sm">{message}</p>}
      <Button variant="secondary" size="lg" onClick={google} loading={busy === "google"} disabled={busy !== null} className="w-full bg-card shadow-card">
        {busy !== "google" && <GoogleLogo />} Continue with Google
      </Button>
      <div className="flex items-center gap-3 text-xs text-label-2" aria-hidden>
        <span className="h-px flex-1 bg-separator" /> or use email <span className="h-px flex-1 bg-separator" />
      </div>
      <form onSubmit={submit} className="flex flex-col gap-3" noValidate>
        <Segmented<Mode>
          label="Account"
          value={mode}
          onChange={(m) => { setMode(m); setError(null); setMessage(null); }}
          options={[{ id: "signIn", label: "Sign In" }, { id: "signUp", label: "Create Account" }, { id: "forgot", label: "Reset" }]}
        />
        <label className="sr-only" htmlFor="email">Email</label>
        <Input id="email" type="email" autoComplete="email" inputMode="email" placeholder="Email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        {mode !== "forgot" && (
          <>
            <label className="sr-only" htmlFor="password">Password</label>
            <Input id="password" type="password" autoComplete={mode === "signUp" ? "new-password" : "current-password"} placeholder="Password"
              value={password} onChange={(e) => setPassword(e.target.value)} required minLength={8} />
          </>
        )}
        {mode === "signUp" && (
          <>
            <label className="sr-only" htmlFor="confirm">Confirm password</label>
            <Input id="confirm" type="password" autoComplete="new-password" placeholder="Confirm password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
          </>
        )}
        <Button type="submit" size="lg" loading={busy === "email"} disabled={busy !== null} className="w-full">
          {busy !== "email" && <Mail aria-hidden className="size-4" />}
          {mode === "signIn" ? "Sign In" : mode === "signUp" ? "Create Account" : "Send Reset Link"}
        </Button>
      </form>
    </div>
  );
}

"use client";

import { ArrowLeft, ArrowRight, Eye, EyeOff, LoaderCircle, Lock, Mail, MailCheck, PieChart, ShieldCheck, Users } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useId, useState, type ReactNode } from "react";
import { BrandMark } from "@/components/brand";
import { cx } from "@/components/ui/primitives";
import { createClient } from "@/lib/supabase/client";

export type AuthMode = "signIn" | "signUp" | "forgot";
type Done = { kind: "reset" | "confirm"; email: string } | null;

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

/** Glass input with icon, label above, error below (reserved space so the layout doesn't jump). */
function AuthField({ id, label, icon: Icon, error, trailing, disabled, ...input }: {
  id: string; label: string; icon: React.ComponentType<{ className?: string; "aria-hidden"?: boolean }>; error?: string | null;
  trailing?: ReactNode; disabled?: boolean;
} & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="px-1 text-[13px] font-semibold text-[var(--auth-text-2)]">{label}</label>
      <div className="auth-field" data-invalid={Boolean(error)} data-disabled={disabled}>
        <Icon aria-hidden className="size-[18px] shrink-0 text-[var(--auth-text-2)]" />
        <input id={id} disabled={disabled} aria-invalid={Boolean(error)} aria-describedby={error ? `${id}-error` : undefined} {...input} />
        {trailing}
      </div>
      <p id={`${id}-error`} className="min-h-[18px] px-1 text-[12.5px] text-[var(--auth-error)]" role={error ? "alert" : undefined}>{error ?? ""}</p>
    </div>
  );
}

function PasswordField({ id, label, value, onChange, autoComplete, error, disabled }: {
  id: string; label: string; value: string; onChange: (v: string) => void; autoComplete: string; error?: string | null; disabled?: boolean;
}) {
  const [visible, setVisible] = useState(false);
  return (
    <AuthField id={id} label={label} icon={Lock} type={visible ? "text" : "password"} autoComplete={autoComplete} value={value} disabled={disabled}
      onChange={(e) => onChange(e.target.value)} error={error} placeholder={autoComplete === "new-password" ? "At least 8 characters" : "Your password"}
      trailing={
        <button type="button" onClick={() => setVisible((v) => !v)} aria-label={visible ? "Hide password" : "Show password"} aria-pressed={visible} aria-controls={id}
          className="-mr-1 inline-flex size-9 shrink-0 items-center justify-center rounded-full text-[var(--auth-text-2)] hover:bg-black/5 hover:text-[var(--auth-text)] dark:hover:bg-white/10">
          {visible ? <EyeOff aria-hidden className="size-[18px]" /> : <Eye aria-hidden className="size-[18px]" />}
        </button>
      } />
  );
}

function Spinner() {
  return <LoaderCircle aria-hidden className="size-[18px] animate-spin" />;
}

const FEATURES = [
  { icon: PieChart, text: "See where every ringgit goes" },
  { icon: Users, text: "Split bills and settle up with friends" },
  { icon: ShieldCheck, text: "Private to your account — on every device" },
];

/** The welcome side of the card (desktop / tablet). Its content follows the mode it invites to. */
function WelcomePanel({ mode, onSwitch }: { mode: AuthMode; onSwitch: (m: AuthMode) => void }) {
  const signingUp = mode === "signUp";
  return (
    <div className="auth-panel relative flex h-full flex-col justify-between overflow-hidden p-10">
      <div aria-hidden className="pointer-events-none absolute -right-24 -top-24 size-72 rounded-full bg-[radial-gradient(circle,rgba(46,229,157,0.35),transparent_65%)]" />
      <div aria-hidden className="pointer-events-none absolute -bottom-28 -left-20 size-80 rounded-full bg-[radial-gradient(circle,rgba(51,153,242,0.28),transparent_65%)]" />
      <div className="relative flex items-center gap-2.5">
        <BrandMark size={34} />
        <span className="text-[17px] font-bold tracking-tight">SpenDrop</span>
      </div>
      <div key={signingUp ? "back" : "new"} className="auth-swap relative">
        <h2 className="text-[34px] font-bold leading-[1.1] tracking-tight">{signingUp ? "Welcome back." : "Welcome to SpenDrop."}</h2>
        <p className="mt-3 max-w-[30ch] text-[15px] leading-relaxed text-white/75">
          {signingUp
            ? "Already have an account? Sign in to pick up right where you left off."
            : "Take control of your spending and keep every expense organized."}
        </p>
        {!signingUp && (
          <ul className="mt-6 flex flex-col gap-3">
            {FEATURES.map(({ icon: Icon, text }) => (
              <li key={text} className="flex items-center gap-3 text-[14px] text-white/85">
                <span className="inline-flex size-8 items-center justify-center rounded-[10px] bg-white/10 ring-1 ring-white/15"><Icon aria-hidden className="size-4" /></span>
                {text}
              </li>
            ))}
          </ul>
        )}
        <button type="button" onClick={() => onSwitch(signingUp ? "signIn" : "signUp")}
          className="auth-ghost mt-8 inline-flex min-h-11 items-center gap-2 rounded-full px-6 text-[15px] font-semibold">
          {signingUp ? <><ArrowLeft aria-hidden className="size-4" /> Sign In</> : <>Start using SpenDrop <ArrowRight aria-hidden className="size-4" /></>}
        </button>
      </div>
      <p className="relative text-[12px] text-white/55">Same account as SpenDrop for iPhone.</p>
    </div>
  );
}

export function AuthExperience({ configured, demo, initialError, initialMode, next }: {
  configured: boolean; demo: boolean; initialError: string | null; initialMode: AuthMode; next: string;
}) {
  const router = useRouter();
  const ids = useId();
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(initialError);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; password?: string; confirm?: string }>({});
  const [busy, setBusy] = useState<"google" | "email" | null>(null);
  const [done, setDone] = useState<Done>(null);

  function switchMode(next: AuthMode) {
    setMode(next);
    setError(null);
    setFieldErrors({});
    setDone(null);
    setPassword("");
    setConfirm("");
    try {
      const url = new URL(window.location.href);
      if (next === "signIn") url.searchParams.delete("mode"); else url.searchParams.set("mode", next === "signUp" ? "signup" : "reset");
      window.history.replaceState(null, "", url);
    } catch {}
  }

  const callback = (path = next) => `${window.location.origin}/auth/callback?next=${encodeURIComponent(path)}`;

  async function google() {
    setBusy("google");
    setError(null);
    const { error } = await createClient().auth.signInWithOAuth({ provider: "google", options: { redirectTo: callback() } });
    if (error) {
      setError(error.message.includes("provider is not enabled") ? "Google sign-in isn't enabled for this project yet." : "Couldn't start Google sign-in. Please try again.");
      setBusy(null);
    }
  }

  function validate() {
    const errors: typeof fieldErrors = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) errors.email = "Enter a valid email address.";
    if (mode !== "forgot" && password.length < 8) errors.password = mode === "signUp" ? "Use at least 8 characters." : "Your password has at least 8 characters.";
    if (mode === "signUp" && !errors.password && confirm !== password) errors.confirm = "Passwords don't match.";
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!validate()) return;
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
        setDone({ kind: "confirm", email: email.trim() });
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: callback("/auth/update-password") });
        if (error) throw error;
        setDone({ kind: "reset", email: email.trim() });
      }
    } catch (e) {
      const text = e instanceof Error ? e.message : "";
      setError(
        /invalid login credentials/i.test(text) ? "Email or password is incorrect."
          : /email not confirmed/i.test(text) ? "Please confirm your email first — check your inbox."
            : /already registered|already been registered/i.test(text) ? "An account with this email already exists. Sign in instead."
              : /rate limit|too many/i.test(text) ? "Too many attempts. Please wait a minute and try again."
                : /password/i.test(text) && mode === "signUp" ? "Choose a stronger password (at least 8 characters)."
                  : /fetch|network/i.test(text) ? "You're offline or SpenDrop can't be reached. Try again."
                    : "That didn't work. Please try again.",
      );
    } finally {
      setBusy(null);
    }
  }

  const heading = { signIn: "Sign in", signUp: "Create your account", forgot: "Reset your password" }[mode];
  const sub = {
    signIn: "Sign in to continue managing your expenses.",
    signUp: "Start using SpenDrop. It takes less than a minute.",
    forgot: "Enter your email and we'll send you a link to choose a new password.",
  }[mode];
  const submitLabel = { signIn: "Sign In", signUp: "Create Account", forgot: "Send Reset Link" }[mode];
  const busyLabel = { signIn: "Signing in…", signUp: "Creating account…", forgot: "Sending reset link…" }[mode];

  let formContent: ReactNode;
  if (demo || !configured) {
    formContent = (
      <div className="flex flex-col gap-4">
        <h1 className="text-[28px] font-bold tracking-tight">{demo ? "Demo mode" : "Sign-in isn't set up yet"}</h1>
        <p className="text-[15px] text-[var(--auth-text-2)]">
          {demo ? "This build uses synthetic data stored only in this browser. No account needed."
            : "Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (see WebApp/.env.example), then reload."}
        </p>
        {demo && <Link href="/" className="auth-primary inline-flex min-h-[50px] items-center justify-center rounded-[14px] font-semibold">Open the demo</Link>}
      </div>
    );
  } else if (done) {
    formContent = (
      <div className="auth-swap flex flex-col items-start gap-4" role="status">
        <span className="inline-flex size-14 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--sd-green)_16%,transparent)] text-green">
          <MailCheck aria-hidden className="size-7" />
        </span>
        <h1 className="text-[28px] font-bold tracking-tight">Check your email</h1>
        <p className="text-[15px] leading-relaxed text-[var(--auth-text-2)]">
          {done.kind === "reset"
            ? <>If an account exists for <strong className="text-[var(--auth-text)]">{done.email}</strong>, a link to choose a new password is on its way.</>
            : <>We sent a confirmation link to <strong className="text-[var(--auth-text)]">{done.email}</strong>. Open it on this device to finish creating your account.</>}
        </p>
        <button type="button" onClick={() => switchMode("signIn")} className="inline-flex min-h-11 items-center gap-2 font-semibold text-[var(--sd-accent-text)]">
          <ArrowLeft aria-hidden className="size-4" /> Back to Sign In
        </button>
      </div>
    );
  } else {
    formContent = (
      <div key={mode} className="auth-swap flex flex-col">
        <h1 className="text-[28px] font-bold tracking-tight">{heading}</h1>
        <p className="mt-1.5 text-[15px] text-[var(--auth-text-2)]">{sub}</p>

        {mode !== "forgot" && (
          <>
            <button type="button" onClick={google} disabled={busy !== null}
              className="mt-6 inline-flex min-h-[50px] items-center justify-center gap-2.5 rounded-[14px] border border-[var(--auth-field-border)] bg-[var(--auth-glass-strong)] text-[15px] font-semibold transition-colors hover:bg-[var(--auth-field-hover)] disabled:opacity-60">
              {busy === "google" ? <Spinner /> : <GoogleLogo />} {busy === "google" ? "Opening Google…" : "Continue with Google"}
            </button>
            <div className="my-5 flex items-center gap-3 text-[12px] font-medium text-[var(--auth-text-2)]" aria-hidden>
              <span className="h-px flex-1 bg-[var(--auth-field-border)]" /> or with email <span className="h-px flex-1 bg-[var(--auth-field-border)]" />
            </div>
          </>
        )}

        <form onSubmit={submit} noValidate className={cx("flex flex-col gap-1", mode === "forgot" && "mt-6")}>
          <AuthField id={`${ids}-email`} label="Email" icon={Mail} type="email" inputMode="email" autoComplete="email" placeholder="you@example.com"
            value={email} onChange={(e) => setEmail(e.target.value)} error={fieldErrors.email} disabled={busy !== null} />
          {mode !== "forgot" && (
            <PasswordField id={`${ids}-password`} label="Password" value={password} onChange={setPassword} error={fieldErrors.password}
              autoComplete={mode === "signUp" ? "new-password" : "current-password"} disabled={busy !== null} />
          )}
          {mode === "signUp" && (
            <PasswordField id={`${ids}-confirm`} label="Confirm password" value={confirm} onChange={setConfirm} error={fieldErrors.confirm}
              autoComplete="new-password" disabled={busy !== null} />
          )}
          {mode === "signIn" && (
            <button type="button" onClick={() => switchMode("forgot")} className="-mt-1 mb-1 self-end text-[13.5px] font-semibold text-[var(--sd-accent-text)] hover:underline">
              Forgot password?
            </button>
          )}
          <div aria-live="assertive" className="min-h-[24px]">
            {error && (
              <p role="alert" className="auth-swap rounded-[12px] border border-[color-mix(in_srgb,var(--auth-error)_35%,transparent)] bg-[color-mix(in_srgb,var(--auth-error)_10%,transparent)] px-3.5 py-2.5 text-[13.5px] text-[var(--auth-error)]">
                {error}
              </p>
            )}
          </div>
          <button type="submit" disabled={busy !== null} aria-busy={busy === "email"}
            className="auth-primary mt-2 inline-flex min-h-[52px] items-center justify-center gap-2 rounded-[14px] text-[16px] font-semibold disabled:cursor-not-allowed disabled:opacity-70">
            {busy === "email" ? <><Spinner /> {busyLabel}</> : submitLabel}
          </button>
        </form>

        <p className="mt-6 text-center text-[14px] text-[var(--auth-text-2)] md:hidden">
          {mode === "signUp" ? "Already have an account? " : mode === "forgot" ? "Remembered it? " : "New to SpenDrop? "}
          <button type="button" onClick={() => switchMode(mode === "signIn" ? "signUp" : "signIn")} className="font-semibold text-[var(--sd-accent-text)]">
            {mode === "signIn" ? "Create account" : "Sign in"}
          </button>
        </p>
        {mode === "forgot" && (
          <button type="button" onClick={() => switchMode("signIn")} className="mt-4 hidden items-center gap-2 self-start text-[14px] font-semibold text-[var(--sd-accent-text)] md:inline-flex">
            <ArrowLeft aria-hidden className="size-4" /> Back to Sign In
          </button>
        )}
      </div>
    );
  }

  const signUpLayout = mode === "signUp";
  return (
    <div className="auth-enter w-full max-w-[980px]">
      {/* Phone: compact welcome above the card */}
      <div className="mb-6 flex flex-col items-center gap-3 text-center md:hidden">
        <BrandMark size={56} />
        <div>
          <p className="text-[24px] font-bold tracking-tight">SpenDrop</p>
          <p className="text-[14px] text-[var(--auth-text-2)]">Track expenses, split bills, see where your money goes.</p>
        </div>
      </div>

      <div className="glass relative overflow-hidden rounded-[28px] md:h-[640px]">
        <span className="glass-sheen" aria-hidden />
        {/* Form side: slides between left (Sign In / Reset) and right (Create Account) on wide screens */}
        <section aria-label={heading}
          className={cx("relative z-10 flex h-full flex-col justify-center px-6 py-8 sm:px-10 md:absolute md:inset-y-0 md:left-0 md:w-1/2 md:px-12",
            "md:transition-transform md:duration-[650ms] md:ease-[cubic-bezier(0.65,0,0.35,1)]",
            signUpLayout ? "md:translate-x-full" : "md:translate-x-0")}>
          {formContent}
        </section>
        {/* Welcome side: slides the opposite way */}
        <aside aria-label="About SpenDrop"
          className={cx("hidden md:absolute md:inset-y-0 md:right-0 md:block md:w-1/2 md:p-3",
            "md:transition-transform md:duration-[650ms] md:ease-[cubic-bezier(0.65,0,0.35,1)]",
            signUpLayout ? "md:-translate-x-full" : "md:translate-x-0")}>
          <div className="h-full overflow-hidden rounded-[22px]">
            <WelcomePanel mode={mode} onSwitch={switchMode} />
          </div>
        </aside>
      </div>
      <p className="mt-6 text-center text-[12px] text-[var(--auth-text-2)]">Your financial data is private to your account. SpenDrop never sells or shares it.</p>
    </div>
  );
}

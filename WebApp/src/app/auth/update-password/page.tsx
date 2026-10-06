"use client";

import Link from "next/link";
import { useState } from "react";
import { BrandMark } from "@/components/brand";
import { Button, Card, ErrorBanner, Input } from "@/components/ui/primitives";
import { createClient } from "@/lib/supabase/client";

export default function UpdatePasswordPage() {
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (password.length < 8) return setError("Use at least 8 characters.");
    if (password !== confirm) return setError("Passwords don't match.");
    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password });
    setBusy(false);
    if (error) return setError("Couldn't update your password. Open the reset link again.");
    setDone(true);
  }

  return (
    <main id="main" className="flex min-h-dvh items-center justify-center px-4">
      <Card className="flex w-full max-w-[400px] flex-col gap-4">
        <div className="flex items-center gap-3"><BrandMark size={36} /><h1 className="text-xl font-bold">Choose a new password</h1></div>
        {done ? (
          <>
            <p role="status">Your password was updated.</p>
            <Link href="/" className="rounded-control bg-[var(--sd-accent-fill)] py-3 text-center font-semibold text-white">Open SpenDrop</Link>
          </>
        ) : (
          <form onSubmit={submit} className="flex flex-col gap-3">
            {error && <ErrorBanner message={error} />}
            <label className="sr-only" htmlFor="new-password">New password</label>
            <Input id="new-password" type="password" autoComplete="new-password" placeholder="New password" value={password} onChange={(e) => setPassword(e.target.value)} />
            <label className="sr-only" htmlFor="confirm-password">Confirm password</label>
            <Input id="confirm-password" type="password" autoComplete="new-password" placeholder="Confirm password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
            <Button type="submit" loading={busy}>Update Password</Button>
          </form>
        )}
      </Card>
    </main>
  );
}

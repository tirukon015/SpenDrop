"use client";

import { LogOut, ShieldCheck, Trash2 } from "lucide-react";
import { useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { Avatar, Button, Card, Divider, Field, Input, SectionHeader, Sheet } from "@/components/ui/primitives";
import { friendlyError } from "@/lib/data/source";

export default function AccountPage() {
  const { source, signOut, deleteAccount, live } = useData();
  const [confirm, setConfirm] = useState(false);
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const provider = source?.provider === "google" ? "Google" : source?.provider === "email" ? "Email & password" : source?.provider === "demo" ? "Demo" : source?.provider ?? "—";
  return (
    <>
      <PageHeader title="Account" back={{ href: "/more", label: "More" }} />
      <Page className="flex max-w-3xl flex-col gap-5">
        <Card className="flex items-center gap-4">
          <Avatar name={source?.email ?? "?"} size={52} />
          <div className="min-w-0"><p className="truncate font-semibold">{source?.email ?? "Signed in"}</p><p className="text-sm text-label-2">Signed in with {provider}</p></div>
        </Card>
        <Card className="flex gap-3 text-sm text-label-2">
          <ShieldCheck aria-hidden className="mt-0.5 size-5 shrink-0 text-green" />
          <p>This is your SpenDrop sign-in. Your funding accounts (Maybank, Touch &apos;n Go…) are separate records under More → Accounts. Your data is visible only to you.</p>
        </Card>
        <section aria-labelledby="data-heading">
          <SectionHeader id="data-heading">Your data in the cloud</SectionHeader>
          <Card className="overflow-hidden p-0 text-[15px]">
            {[["Expenses", live.expenses.length], ["Money in / out", live.movements.length], ["People", live.people.length], ["Funding accounts", live.accounts.length]].map(([label, n], i) => (
              <div key={label as string}>{i > 0 && <Divider inset={16} />}<div className="flex justify-between px-4 py-2.5"><span className="text-label-2">{label}</span><span className="tabular font-medium">{n}</span></div></div>
            ))}
          </Card>
        </section>
        <Card className="overflow-hidden p-0">
          <button type="button" onClick={signOut} className="flex min-h-12 w-full items-center gap-3 px-4 text-left font-medium hover:bg-card-2"><LogOut aria-hidden className="size-5 text-label-2" /> Sign Out</button>
          <Divider inset={16} />
          <button type="button" onClick={() => setConfirm(true)} className="flex min-h-12 w-full items-center gap-3 px-4 text-left font-medium text-red hover:bg-card-2"><Trash2 aria-hidden className="size-5" /> Delete Account…</button>
        </Card>
        <p className="px-1 text-xs text-label-2">Signing out clears this browser&apos;s copy. Your data stays in your account.</p>
      </Page>
      <Sheet open={confirm} onClose={() => { setConfirm(false); setTyped(""); setError(null); }} title="Delete your SpenDrop account?"
        footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirm(false)}>Cancel</Button>
          <Button variant="destructive" disabled={typed !== "DELETE"} loading={busy} onClick={async () => {
            setBusy(true); setError(null);
            try { await deleteAccount(); } catch (e) { setError(friendlyError(e)); setBusy(false); }
          }}>Delete Forever</Button></div>}>
        <div className="flex flex-col gap-3 text-[15px]">
          <p>This permanently deletes your account, all cloud records, receipts and cloud backups. It can&apos;t be undone.</p>
          <p className="text-sm text-label-2">Data stored only on your iPhone stays on your iPhone.</p>
          <Field label="Type DELETE to confirm" htmlFor="confirm-delete" error={error}><Input id="confirm-delete" autoComplete="off" value={typed} onChange={(e) => setTyped(e.target.value)} /></Field>
        </div>
      </Sheet>
    </>
  );
}

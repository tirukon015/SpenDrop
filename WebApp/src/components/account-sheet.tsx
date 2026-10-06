"use client";

import { useState } from "react";
import { useData } from "@/components/providers/data-provider";
import { Button, Field, Input, Select, Sheet } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import { ACCOUNT_TYPES } from "@/lib/domain/constants";
import type { Account, AccountType } from "@/lib/domain/types";

export function AccountSheet({ open, onClose, account }: { open: boolean; onClose: () => void; account?: Account }) {
  const { saveRecords, live } = useData();
  const toast = useToast();
  const [name, setName] = useState(account?.name ?? "");
  const [type, setType] = useState<AccountType>(account?.type ?? "bank");
  const [busy, setBusy] = useState(false);
  const clash = live.accounts.some((a) => a.id !== account?.id && a.name.trim().toLowerCase() === name.trim().toLowerCase());
  async function save() {
    setBusy(true);
    try {
      const now = new Date().toISOString();
      await saveRecords("accounts", [account
        ? { ...account, name: name.trim(), type, updatedAt: now }
        : { id: crypto.randomUUID(), name: name.trim(), type, currency: "RM", icon: null, isArchived: false, sortIndex: live.accounts.length, createdAt: now, updatedAt: now, deletedAt: null }]);
      toast("Account saved");
      onClose();
    } catch (e) { toast(friendlyError(e), { tone: "error" }); } finally { setBusy(false); }
  }
  return (
    <Sheet open={open} onClose={onClose} title={account ? "Edit Account" : "Add Account"}
      footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!name.trim() || clash} loading={busy} onClick={save}>Save</Button></div>}>
      <div className="flex flex-col gap-4">
        <Field label="Name" htmlFor="acc-name" error={clash ? "You already have an account with this name." : null}><Input id="acc-name" autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Maybank, Touch 'n Go, Cash" /></Field>
        <Field label="Type" htmlFor="acc-type"><Select id="acc-type" value={type} onChange={(e) => setType(e.target.value as AccountType)}>{ACCOUNT_TYPES.map((t) => <option key={t.id} value={t.id}>{t.label}</option>)}</Select></Field>
      </div>
    </Sheet>
  );
}


"use client";

import { useState } from "react";
import { useData } from "@/components/providers/data-provider";
import { Button, Field, Input, Sheet, TextArea, Toggle } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { friendlyError } from "@/lib/data/source";
import type { Person } from "@/lib/domain/types";

export function PersonSheet({ open, onClose, person, onSaved }: { open: boolean; onClose: () => void; person?: Person; onSaved?: (p: Person) => void }) {
  const { saveRecords, live } = useData();
  const toast = useToast();
  const [name, setName] = useState(person?.name ?? "");
  const [notes, setNotes] = useState(person?.notes ?? "");
  const [frequent, setFrequent] = useState(person?.isFrequent ?? false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const trimmed = name.trim();
  const clash = live.people.some((p) => p.id !== person?.id && p.name.trim().toLowerCase() === trimmed.toLowerCase());

  async function save() {
    if (!trimmed) return setError("Enter a name.");
    setBusy(true);
    setError(null);
    try {
      const now = new Date().toISOString();
      const record: Person = person
        ? { ...person, name: trimmed.slice(0, 80), notes: notes.trim() || null, isFrequent: frequent, updatedAt: now }
        : { id: crypto.randomUUID(), name: trimmed.slice(0, 80), notes: notes.trim() || null, isFrequent: frequent, isArchived: false, createdAt: now, updatedAt: now, deletedAt: null };
      await saveRecords("people", [record]);
      toast(person ? "Saved" : `${record.name} added to PayBook`);
      onSaved?.(record);
      onClose();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Sheet open={open} onClose={onClose} title={person ? "Edit Person" : "Add Person"}
      footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={onClose}>Cancel</Button><Button onClick={save} loading={busy} disabled={!trimmed}>Save</Button></div>}>
      <div className="flex flex-col gap-4">
        <Field label="Name" htmlFor="person-name" error={error} hint={clash ? "Someone with this name is already in your PayBook." : undefined}>
          <Input id="person-name" autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Bijoy" />
        </Field>
        <Field label="Notes" htmlFor="person-notes"><TextArea id="person-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" /></Field>
        <Toggle id="person-frequent" checked={frequent} onChange={setFrequent} label="Frequent" description="Shown as a quick pick when splitting." />
      </div>
    </Sheet>
  );
}

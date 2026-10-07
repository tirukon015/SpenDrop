"use client";

import { ImagePlus, Images, ShieldCheck } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type DragEvent } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { BulkProgress, BulkReview, type BulkShot } from "@/components/bulk-import";
import { useData } from "@/components/providers/data-provider";
import { Button, Card, ErrorBanner, cx } from "@/components/ui/primitives";
import { useToast } from "@/components/ui/toast";
import { MAX_SCREENSHOTS, OCR_CONCURRENCY, draftsFromScreenshot, runPool, todayInput, type BulkDraft } from "@/lib/bulk-import";
import { friendlyError } from "@/lib/data/source";
import type { Account } from "@/lib/domain/types";
import { persistDraft } from "@/lib/transaction-draft";

type Stage = "pick" | "processing" | "review";

export default function BulkImportPage() {
  const router = useRouter();
  const toast = useToast();
  const data = useData();
  // Latest data for the save loop (each save re-syncs; later saves must see accounts / rules created by earlier ones).
  const dataRef = useRef(data);
  useEffect(() => { dataRef.current = data; }, [data]);

  const [stage, setStage] = useState<Stage>("pick");
  const [shots, setShots] = useState<BulkShot[]>([]);
  const [drafts, setDrafts] = useState<BulkDraft[]>([]);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [dragging, setDragging] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const alive = useRef(true);
  // Preview URLs of this session; all released when the page goes away (screenshots never leave the browser until saved).
  const urls = useRef(new Set<string>());
  useEffect(() => {
    alive.current = true;
    const owned = urls.current;
    return () => {
      alive.current = false;
      owned.forEach((u) => URL.revokeObjectURL(u));
      owned.clear();
    };
  }, []);

  const setShot = (n: number, patch: Partial<BulkShot>) => {
    if (alive.current) setShots((list) => list.map((s) => (s.n === n ? { ...s, ...patch } : s)));
  };

  async function start(list: FileList | File[] | null) {
    if (!list || stage !== "pick") return;
    const all = [...list];
    const images = all.filter((f) => f.type.startsWith("image/"));
    const picked = images.slice(0, MAX_SCREENSHOTS);
    const notes = [
      images.length < all.length ? `${all.length - images.length} file${all.length - images.length === 1 ? " isn't an image" : "s aren't images"} and ${all.length - images.length === 1 ? "was" : "were"} skipped.` : null,
      images.length > MAX_SCREENSHOTS ? `Only the first ${MAX_SCREENSHOTS} screenshots are imported at a time.` : null,
    ].filter(Boolean);
    setNotice(notes.length ? notes.join(" ") : null);
    if (picked.length === 0) { setError("Choose one or more screenshots (images)."); return; }
    setError(null);
    setShots(picked.map((f, i) => ({ n: i + 1, blob: null, url: null, takenAt: new Date(f.lastModified || Date.now()), state: "queued", progress: 0, removed: false })));
    setStage("processing");
    const importDate = todayInput();
    const { compressImage, recognizeText } = await import("@/lib/ocr/recognize");
    // Bounded concurrency: OCR runs in tesseract web workers, a couple at a time, so the page stays responsive.
    const results = await runPool(picked, OCR_CONCURRENCY, async (file, i) => {
      const n = i + 1;
      if (!alive.current) return [];
      setShot(n, { state: "reading" });
      let blob: Blob | null = null;
      try {
        blob = await compressImage(file);
        const url = URL.createObjectURL(blob);
        urls.current.add(url);
        setShot(n, { blob, url });
        const lines = await recognizeText(blob, (p) => setShot(n, { progress: p }));
        const found = draftsFromScreenshot(lines, n, blob, importDate, new Date(file.lastModified || Date.now()));
        setShot(n, { state: "done", progress: 1 });
        return found;
      } catch {
        setShot(n, { state: "failed" });
        return [];
      }
    });
    if (!alive.current) return;
    // Screenshot order: a draft is checked against the drafts before it (duplicates inside the batch).
    setDrafts(results.flat());
    setStage("review");
  }

  function removeShot(n: number) {
    setShots((list) => list.map((s) => {
      if (s.n !== n) return s;
      if (s.url) { URL.revokeObjectURL(s.url); urls.current.delete(s.url); }
      return { ...s, removed: true, blob: null, url: null };
    }));
  }

  async function add(toAdd: BulkDraft[]) {
    if (saving || toAdd.length === 0) return;
    setSaving(true);
    setError(null);
    const saved = new Set<string>();
    const created: Account[] = [];
    let failure: string | null = null;
    for (const b of toAdd) {
      const { live, dataset, source, saveExpense, saveRecords } = dataRef.current;
      if (!source) { failure = "Not ready yet — try again in a moment."; break; }
      const accounts = [...live.accounts, ...created.filter((a) => !live.accounts.some((x) => x.id === a.id))];
      try {
        // Each draft is its own record: its own expense, shares and receipt (its own screenshot).
        const result = await persistDraft(b.draft, { live: { ...live, accounts }, dataset, source, saveExpense, saveRecords, movementSourceType: "screenshot" });
        if (result.kind === "expense" && result.createdAccount) created.push(result.createdAccount);
        saved.add(b.key);
      } catch (e) {
        failure = friendlyError(e);
        break;
      }
      await new Promise((r) => setTimeout(r, 0)); // let the synced data reach dataRef before the next save
    }
    if (!alive.current) return;
    setSaving(false);
    if (!failure) {
      toast(`Added ${saved.size} transaction${saved.size === 1 ? "" : "s"}`);
      router.push("/transactions");
      return;
    }
    // Keep only what wasn't saved, so trying again never adds anything twice.
    setDrafts((list) => list.filter((b) => !saved.has(b.key)));
    setError(`${saved.size ? `${saved.size} added. ` : ""}The rest weren't saved: ${failure}`);
  }

  function onDrop(e: DragEvent) {
    e.preventDefault();
    setDragging(false);
    start(e.dataTransfer.files);
  }

  return (
    <>
      <PageHeader title="Bulk Import" back={{ href: "/add", label: "Add Transaction" }} />
      <Page className="flex max-w-3xl flex-col gap-5">
        {error && <ErrorBanner message={error} />}
        {notice && <p role="status" className="rounded-field bg-[color-mix(in_srgb,var(--sd-orange)_12%,transparent)] p-3 text-sm">{notice}</p>}

        {stage === "pick" && (
          <>
            <div
              onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
              onDragLeave={() => setDragging(false)}
              onDrop={onDrop}
              className={cx("flex flex-col items-center gap-3 rounded-card border-2 border-dashed bg-card px-4 py-10 text-center shadow-card transition-colors",
                dragging ? "border-[var(--sd-accent)] bg-[color-mix(in_srgb,var(--sd-accent)_8%,var(--sd-card))]" : "border-separator")}
            >
              <Images aria-hidden className="size-10 text-blue" />
              <p className="text-[17px] font-semibold">Drop screenshots here</p>
              <p className="max-w-md text-sm text-label-2">
                Payment receipts or transaction history from your banking and e-wallet apps — up to {MAX_SCREENSHOTS} at a time.
                Each transaction becomes its own draft for you to check before anything is saved.
              </p>
              <input ref={fileInput} type="file" accept="image/*" multiple className="sr-only" tabIndex={-1} aria-hidden
                onChange={(e) => { start(e.target.files); e.target.value = ""; }} />
              <Button variant="primary" onClick={() => fileInput.current?.click()}><ImagePlus aria-hidden className="size-4" /> Choose Screenshots</Button>
            </div>
            <Card className="flex gap-3 text-sm text-label-2">
              <ShieldCheck aria-hidden className="mt-0.5 size-5 shrink-0 text-green" />
              <p>Screenshots are read on this device and stay in this browser until you add the transactions; each saved transaction keeps its own screenshot as its receipt.</p>
            </Card>
          </>
        )}

        {stage === "processing" && <BulkProgress shots={shots} />}

        {stage === "review" && (
          <BulkReview shots={shots} drafts={drafts} onDraftsChange={setDrafts} onRemoveShot={removeShot} onAdd={add} saving={saving} />
        )}
      </Page>
    </>
  );
}

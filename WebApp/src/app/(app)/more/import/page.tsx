"use client";

import { CloudDownload, FileUp, Smartphone } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { Button, Card, Divider, ErrorBanner, SectionHeader, Sheet, Toggle } from "@/components/ui/primitives";
import type { ImportSummary } from "@/lib/data/backup-import";
import { friendlyError, type BackupMeta } from "@/lib/data/source";
import { formatDate, formatTime } from "@/lib/domain/dates";

export default function ImportPage() {
  const { source, importBackup } = useData();
  const [backups, setBackups] = useState<BackupMeta[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [includeSample, setIncludeSample] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ImportSummary | null>(null);
  const [confirm, setConfirm] = useState<{ label: string; load: () => Promise<unknown> } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!source) return;
    source.listBackups().then(setBackups).catch((e) => { setBackups([]); setLoadError(friendlyError(e)); });
  }, [source]);

  async function run(key: string, load: () => Promise<unknown>) {
    setBusy(key);
    setError(null);
    setResult(null);
    try {
      const payload = await load();
      setResult(await importBackup(payload, includeSample));
    } catch (e) {
      setError(e instanceof Error && /backup|newer SpenDrop/i.test(e.message) ? e.message : friendlyError(e));
    } finally {
      setBusy(null);
      setConfirm(null);
    }
  }

  const total = (r: Record<string, number>) => Object.values(r).reduce((a, b) => a + b, 0);

  return (
    <>
      <PageHeader title="Bring in iPhone data" back={{ href: "/more", label: "More" }} />
      <Page className="flex max-w-3xl flex-col gap-5">
        <Card className="flex gap-3 text-[15px]">
          <Smartphone aria-hidden className="mt-0.5 size-5 shrink-0 text-blue" />
          <div className="flex flex-col gap-1.5">
            <p>Copies the records from an iPhone backup into your SpenDrop cloud records, so they appear here.</p>
            <p className="text-sm text-label-2">Safe to repeat: records keep their identity (no duplicates), anything newer in the cloud is kept, nothing is deleted, accounts with the same name are merged. Screenshots and people&apos;s photos are not in backups, so they don&apos;t come across.</p>
          </div>
        </Card>
        <Card><Toggle id="include-sample" checked={includeSample} onChange={setIncludeSample} label="Include sample data" description="Off: records you loaded as SpenDrop sample data are skipped." /></Card>
        {error && <ErrorBanner message={error} />}
        {result && (
          <Card className="flex flex-col gap-1 text-[15px]"><span role="status" className="sr-only">Import finished</span>
            <p className="font-semibold">Done — {total(result.added)} added, {total(result.updated)} updated.</p>
            <p className="text-sm text-label-2">
              {[result.keptNewer ? `${result.keptNewer} kept because the cloud copy was newer` : null,
                result.accountsMergedByName ? `${result.accountsMergedByName} account${result.accountsMergedByName === 1 ? "" : "s"} merged by name` : null,
                result.skippedSample ? `${result.skippedSample} sample record${result.skippedSample === 1 ? "" : "s"} skipped` : null,
                result.missingReferences ? `${result.missingReferences} missing link${result.missingReferences === 1 ? "" : "s"} left empty` : null,
                result.exportDate ? `backup from ${formatDate(result.exportDate)}` : null].filter(Boolean).join(" · ") || "Everything was already up to date."}
            </p>
          </Card>
        )}
        <section aria-labelledby="cloud-heading">
          <SectionHeader id="cloud-heading">iPhone cloud backups</SectionHeader>
          <Card className="overflow-hidden p-0">
            {backups === null ? <p className="p-4 text-sm text-label-2">Loading backups…</p>
              : backups.length === 0 ? <p className="p-4 text-sm text-label-2">{loadError ?? "No cloud backups yet. On your iPhone: More → Account → turn on cloud backup, then Back Up Now."}</p>
                : backups.map((b, i) => (
                  <div key={b.id}>{i > 0 && <Divider inset={16} />}
                    <div className="flex min-h-14 items-center gap-3 px-4 py-2.5">
                      <div className="min-w-0 flex-1">
                        <p className="font-medium">{formatDate(b.createdAt, { weekday: "short", day: "numeric", month: "short", year: "numeric" })} · {formatTime(b.createdAt)}</p>
                        <p className="text-xs text-label-2">{b.deviceName || "iPhone"} · {b.expensesCount} expenses · {b.peopleCount} people · {b.movementsCount} money in/out{i === 0 ? " · latest" : ""}</p>
                      </div>
                      <Button size="sm" variant={i === 0 ? "primary" : "tinted"} loading={busy === b.id} disabled={busy !== null}
                        onClick={() => setConfirm({ label: `the backup from ${formatDate(b.createdAt)}`, load: () => source!.downloadBackup(b.objectPath) })}>
                        <CloudDownload aria-hidden className="size-4" /> Bring in
                      </Button>
                    </div>
                  </div>
                ))}
          </Card>
        </section>
        <section aria-labelledby="file-heading">
          <SectionHeader id="file-heading">Backup file</SectionHeader>
          <Card className="flex flex-col gap-3">
            <p className="text-sm text-label-2">A SpenDrop backup (.json) exported from the iPhone app (More → Settings → Backup).</p>
            <input ref={fileRef} type="file" accept="application/json,.json" className="sr-only" tabIndex={-1} aria-hidden
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) setConfirm({ label: file.name, load: async () => JSON.parse(await file.text()) });
                e.target.value = "";
              }} />
            <Button variant="tinted" className="self-start" disabled={busy !== null} onClick={() => fileRef.current?.click()}><FileUp aria-hidden className="size-4" /> Choose backup file</Button>
          </Card>
        </section>
      </Page>
      <Sheet open={confirm !== null} onClose={() => setConfirm(null)} title="Bring in this data?"
        footer={<div className="flex justify-end gap-2"><Button variant="secondary" onClick={() => setConfirm(null)}>Cancel</Button>
          <Button loading={busy !== null} onClick={() => confirm && run("confirm", confirm.load)}>Bring In</Button></div>}>
        <p className="text-[15px]">Records from {confirm?.label} will be added to your SpenDrop cloud records{includeSample ? " (including sample data)" : ""}. Nothing is deleted and newer records are kept.</p>
      </Sheet>
    </>
  );
}

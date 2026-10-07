"use client";

import { ChevronDown, Circle, CircleCheck, Copy, Eye, LoaderCircle, PencilLine, Trash2, TriangleAlert } from "lucide-react";
import { useMemo, useState, type Dispatch, type SetStateAction } from "react";
import { useData } from "@/components/providers/data-provider";
import { TransactionForm } from "@/components/transaction-form";
import { Button, Card, Sheet, cx } from "@/components/ui/primitives";
import { channelInfo } from "@/lib/domain/constants";
import { formatDate, formatTime, fromInputs } from "@/lib/domain/dates";
import { formatMoney, parseMinor } from "@/lib/domain/money";
import { draftStatus, findDuplicates, manualDraft, summarize, willAdd, type BulkDraft, type DraftStatus, type DuplicateMatch } from "@/lib/bulk-import";
import type { PaymentChannelId } from "@/lib/domain/types";
import { deriveDraft, type TransactionDraft } from "@/lib/transaction-draft";

/** One selected screenshot during a Bulk Import session (kept only in memory, in this browser). */
export interface BulkShot {
  /** 1-based screenshot number. */
  n: number;
  /** Compressed image (also each draft's receipt); null until read. */
  blob: Blob | null;
  /** Object URL of `blob` for previews; revoked by the page when the session ends. */
  url: string | null;
  /** The file's own date (used only when a receipt shows no date). */
  takenAt: Date;
  state: "queued" | "reading" | "done" | "failed";
  progress: number;
  removed: boolean;
}

export function BulkProgress({ shots }: { shots: BulkShot[] }) {
  const done = shots.filter((s) => s.state === "done" || s.state === "failed").length;
  return (
    <Card className="flex flex-col gap-3">
      <div className="flex items-center justify-between gap-3">
        <p className="font-semibold">Reading screenshots on this device…</p>
        <span role="status" className="tabular text-sm text-label-2">{done} of {shots.length}</span>
      </div>
      <div aria-hidden className="h-1.5 overflow-hidden rounded-full bg-card-2">
        <div className="h-full rounded-full bg-[var(--sd-accent-fill)] transition-[width] duration-300" style={{ width: `${shots.length ? (done / shots.length) * 100 : 0}%` }} />
      </div>
      <ul className="flex flex-col gap-1.5" aria-label="Screenshots">
        {shots.map((s) => (
          <li key={s.n} className="flex items-center gap-2.5 text-[15px]">
            {s.state === "done" ? <CircleCheck aria-label="Done" className="size-4 shrink-0 text-green" />
              : s.state === "failed" ? <TriangleAlert aria-label="Couldn't read" className="size-4 shrink-0 text-orange" />
                : s.state === "reading" ? <LoaderCircle aria-label="Reading" className="size-4 shrink-0 animate-spin text-blue" />
                  : <Circle aria-label="Waiting" className="size-4 shrink-0 text-label-3" />}
            <span className="flex-1">Screenshot {s.n}</span>
            {s.state === "reading" && <span className="tabular text-xs text-label-2">{Math.round(s.progress * 100)}%</span>}
            {s.state === "failed" && <span className="text-xs text-label-2">Couldn&apos;t read</span>}
          </li>
        ))}
      </ul>
    </Card>
  );
}

const STATUS: Record<DraftStatus, { label: string; tint: string; icon: typeof CircleCheck }> = {
  ready: { label: "Ready", tint: "var(--sd-green)", icon: CircleCheck },
  review: { label: "Needs Review", tint: "var(--sd-orange)", icon: TriangleAlert },
  duplicate: { label: "Possible Duplicate", tint: "var(--sd-red)", icon: Copy },
};

function StatusBadge({ status }: { status: DraftStatus }) {
  const { label, tint, icon: Icon } = STATUS[status];
  return (
    <span className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold"
      style={{ color: `color-mix(in srgb, ${tint} 55%, var(--sd-label))`, background: `color-mix(in srgb, ${tint} 14%, transparent)` }}>
      <Icon aria-hidden className="size-3.5" /> {label}
    </span>
  );
}

function paymentInfo(d: TransactionDraft, channel: PaymentChannelId): string | null {
  if (d.type === "moneyIn") return "Money In";
  if (d.type !== "expense") return null;
  const parts = [d.funding && d.funding !== "Unknown" ? d.funding : null, channel !== "UNKNOWN" ? channelInfo(channel).label : null].filter(Boolean);
  return parts.length ? parts.join(" · ") : null;
}

function DuplicateNotice({ match, decision, onDecide }: { match: DuplicateMatch; decision: BulkDraft["decision"]; onDecide: (d: "add" | "skip") => void }) {
  const adding = decision === "add";
  return (
    <div className="flex flex-col gap-2 rounded-field bg-[color-mix(in_srgb,var(--sd-red)_8%,transparent)] p-3 text-sm">
      <p>
        {match.kind === "saved"
          ? <>Possible duplicate of a recorded expense: <strong>{match.expense.merchant}</strong> · {formatMoney(match.expense.amountMinor, match.expense.currency)} on {formatDate(match.expense.date)}.</>
          : <>Looks like the same payment as a transaction from Screenshot {match.screenshot} in this import.</>}
      </p>
      <div className="flex flex-wrap gap-2" role="group" aria-label="Duplicate action">
        <Button size="sm" variant={!adding ? "primary" : "secondary"} aria-pressed={!adding} onClick={() => onDecide("skip")}>Skip</Button>
        <Button size="sm" variant={adding ? "primary" : "secondary"} aria-pressed={adding} onClick={() => onDecide("add")}>Add Anyway</Button>
      </div>
    </div>
  );
}

interface ReviewProps {
  shots: BulkShot[];
  drafts: BulkDraft[];
  onDraftsChange: Dispatch<SetStateAction<BulkDraft[]>>;
  onRemoveShot: (n: number) => void;
  onAdd: (toAdd: BulkDraft[]) => void;
  saving?: boolean;
}

/** The review queue: a summary, collapsed cards (one expands into the full transaction editor), and "Add N". */
export function BulkReview({ shots, drafts, onDraftsChange, onRemoveShot, onAdd, saving }: ReviewProps) {
  const { live, dataset } = useData();
  const [open, setOpen] = useState<string | null>(null);
  const [viewing, setViewing] = useState<BulkShot | null>(null);
  const duplicates = useMemo(() => findDuplicates(drafts, live.expenses), [drafts, live.expenses]);
  const visibleShots = shots.filter((s) => !s.removed);
  const summary = summarize(visibleShots.length, drafts, duplicates, dataset);
  const unable = visibleShots.filter((s) => (s.state === "done" || s.state === "failed") && !drafts.some((b) => b.screenshot === s.n));
  const shotUrl = (n: number) => shots.find((s) => s.n === n)?.url ?? null;

  const update = (key: string, fn: (b: BulkDraft) => BulkDraft) => onDraftsChange((list) => list.map((b) => (b.key === key ? fn(b) : b)));
  const setDraftFor = (key: string): Dispatch<SetStateAction<TransactionDraft>> => (action) =>
    update(key, (b) => ({ ...b, draft: typeof action === "function" ? action(b.draft) : action }));

  function enterManually(shot: BulkShot) {
    const b = manualDraft(shot.n, shot.blob, shot.takenAt);
    onDraftsChange((list) => {
      const at = list.findIndex((x) => x.screenshot > shot.n);
      return at < 0 ? [...list, b] : [...list.slice(0, at), b, ...list.slice(at)];
    });
    setOpen(b.key);
  }

  const toAdd = drafts.filter((b) => willAdd(b, duplicates.get(b.key), dataset));
  const facts = [
    `${summary.screenshots} screenshot${summary.screenshots === 1 ? "" : "s"}`,
    `${summary.detected} detected`,
    `${summary.ready} ready`,
    `${summary.review} need${summary.review === 1 ? "s" : ""} review`,
    `${summary.duplicates} possible duplicate${summary.duplicates === 1 ? "" : "s"}`,
  ];

  return (
    <div className="flex flex-col gap-4">
      <Card className="flex flex-col gap-1" aria-label="Import summary">
        <p className="text-sm text-label-2" data-testid="bulk-summary">{facts.join(" · ")}</p>
        <p className="text-[15px]">Total <strong className="tabular">{formatMoney(summary.totalMinor)}</strong></p>
      </Card>

      <ul className="flex flex-col gap-2.5" aria-label="Detected transactions">
        {drafts.filter((b) => !b.removed).map((b) => {
          const match = duplicates.get(b.key);
          const status = draftStatus(b, match, dataset);
          const derived = deriveDraft(b.draft, dataset);
          const expanded = open === b.key;
          const amount = parseMinor(b.draft.amountText);
          const info = paymentInfo(b.draft, derived.channel);
          const when = b.draft.date ? fromInputs(b.draft.date, b.draft.time) : null;
          return (
            <li key={b.key}>
              <Card className="p-0">
                <button type="button" aria-expanded={expanded} onClick={() => setOpen(expanded ? null : b.key)}
                  className="flex w-full items-center gap-3 rounded-card px-4 py-3 text-left hover:bg-card-2">
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center justify-between gap-2">
                      <span className={cx("truncate font-medium", !b.draft.merchant.trim() && "text-label-2")}>{b.draft.merchant.trim() || "No merchant"}</span>
                      <span className="tabular shrink-0 font-semibold">{amount && amount > 0 ? `${b.draft.type === "moneyIn" ? "+" : ""}${formatMoney(amount)}` : "RM —"}</span>
                    </span>
                    <span className="mt-0.5 flex items-center justify-between gap-2">
                      <span className="truncate text-xs text-label-2">
                        {[when ? formatDate(when) : null, when ? formatTime(when) : null, info].filter(Boolean).join(" · ")}
                        {" · "}Screenshot {b.screenshot}
                      </span>
                      <StatusBadge status={status} />
                    </span>
                  </span>
                  <ChevronDown aria-hidden className={cx("size-4 shrink-0 text-label-3 transition-transform", expanded && "rotate-180")} />
                </button>
                {expanded && (
                  <div className="flex flex-col gap-4 border-t border-separator px-4 py-4">
                    {match && <DuplicateNotice match={match} decision={b.decision} onDecide={(decision) => update(b.key, (x) => ({ ...x, decision }))} />}
                    {b.reviewReason && (
                      <p className="flex items-start gap-1.5 text-xs text-orange"><TriangleAlert aria-hidden className="mt-0.5 size-3.5 shrink-0" />{b.reviewReason}</p>
                    )}
                    <TransactionForm value={b.draft} onChange={setDraftFor(b.key)} receiptPreviewUrl={shotUrl(b.screenshot)} />
                    <div className="flex flex-wrap justify-between gap-2">
                      <Button variant="destructive" size="sm" onClick={() => { update(b.key, (x) => ({ ...x, removed: true })); setOpen(null); }}>
                        <Trash2 aria-hidden className="size-4" /> Remove
                      </Button>
                      <Button variant="secondary" size="sm" onClick={() => setOpen(null)}>Done</Button>
                    </div>
                  </div>
                )}
              </Card>
            </li>
          );
        })}
        {unable.map((s) => (
          <li key={`shot-${s.n}`}>
            <Card className="flex flex-wrap items-center gap-3">
              <p className="flex min-w-0 flex-1 items-center gap-2 text-[15px]">
                <TriangleAlert aria-hidden className="size-4 shrink-0 text-orange" />
                <span>Unable to detect transaction · Screenshot {s.n}</span>
              </p>
              <div className="flex flex-wrap gap-2">
                {s.url && <Button size="sm" variant="secondary" onClick={() => setViewing(s)}><Eye aria-hidden className="size-4" /> View</Button>}
                <Button size="sm" variant="tinted" onClick={() => enterManually(s)}><PencilLine aria-hidden className="size-4" /> Enter Manually</Button>
                <Button size="sm" variant="destructive" onClick={() => onRemoveShot(s.n)}><Trash2 aria-hidden className="size-4" /> Remove</Button>
              </div>
            </Card>
          </li>
        ))}
      </ul>
      {summary.detected === 0 && unable.length === 0 && <p className="px-1 text-sm text-label-2">Nothing left to add.</p>}

      <div className="sticky bottom-[calc(64px+env(safe-area-inset-bottom))] z-10 -mx-4 border-t border-separator bg-bg/90 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-t-card md:px-0">
        <Button size="lg" className="w-full" disabled={toAdd.length === 0} loading={saving} onClick={() => onAdd(toAdd)}>
          {saving ? "Adding…" : `Add ${toAdd.length} Transaction${toAdd.length === 1 ? "" : "s"}`}
        </Button>
      </div>

      <Sheet open={viewing !== null} onClose={() => setViewing(null)} title={viewing ? `Screenshot ${viewing.n}` : "Screenshot"} wide>
        {/* eslint-disable-next-line @next/next/no-img-element -- local blob preview, not optimisable */}
        {viewing?.url && <img src={viewing.url} alt={`Screenshot ${viewing.n}`} className="mx-auto max-h-[70dvh] w-auto rounded-lg object-contain" />}
      </Sheet>
    </div>
  );
}

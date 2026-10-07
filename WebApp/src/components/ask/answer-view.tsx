"use client";

// Renders one SpenDrop AI answer: the short answer (plain text — never HTML), then the evidence the tools returned
// (figures, comparisons, breakdowns, transaction cards that open the real record) and "Based on N transactions".
import { ArrowDownRight, ArrowUpRight, ChevronDown, HelpCircle, Info, Lightbulb, Paperclip, Target, TriangleAlert } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { IconTile, cx, tintText, tintVar } from "@/components/ui/primitives";
import type { AnswerBlock, AskAnswer, TxnCard } from "@/lib/ai/types";
import { categoryTint, channelInfo, type Tint } from "@/lib/domain/constants";
import { formatMoney } from "@/lib/domain/money";
import { formatSpan } from "@/lib/ai/time";

const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;

function TransactionCard({ t }: { t: TxnCard }) {
  const Icon = CATEGORY_ICONS[t.category];
  const ChannelIcon = CHANNEL_ICONS[t.paymentChannel];
  return (
    <Link href={`/transactions/${t.id}`} className="flex items-center gap-3 rounded-[12px] px-2 py-2 transition-colors hover:bg-card-2">
      <IconTile icon={Icon} tint={categoryTint(t.category)} size={36} />
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-1.5 font-medium"><span className="truncate">{t.merchant}</span>{t.hasReceipt && <Paperclip aria-label="Has receipt" className="size-3.5 shrink-0 text-label-2" />}</span>
        <span className="block truncate text-xs text-label-2">
          {formatSpan({ from: t.localDate, to: t.localDate })}, {t.localTime} · {t.category}
        </span>
        {/* Funding account (where from) and payment channel (how) are always shown separately. */}
        <span className="flex items-center gap-1 truncate text-xs text-label-2">
          {t.fundingAccount !== "Unknown" ? t.fundingAccount : "Account unknown"} ·
          <ChannelIcon aria-hidden className="size-3" style={{ color: tintVar(channelInfo(t.paymentChannel).tint) }} />
          {channelInfo(t.paymentChannel).label}
        </span>
      </span>
      <span className="shrink-0 text-right">
        <span className="tabular block font-semibold">{formatMoney(t.amountMinor, t.currency)}</span>
        {t.isShared && t.spendMinor !== t.amountMinor && <span className="tabular block text-xs text-label-2">yours {formatMoney(t.spendMinor, t.currency)}</span>}
      </span>
    </Link>
  );
}

const KIND_TINT: Record<string, Tint> = { category: "orange", merchant: "pink", account: "blue", channel: "indigo", day: "teal" };

function Block({ b }: { b: AnswerBlock }) {
  switch (b.type) {
    case "metric":
      return (
        <div className="rounded-[14px] bg-card-2 px-4 py-3">
          <div className="section-header">{b.label}</div>
          <div className="tabular text-[28px] font-bold tracking-tight">{formatMoney(b.valueMinor, b.currency)}</div>
          {b.caption && <div className="text-xs text-label-2">{b.caption}</div>}
        </div>
      );
    case "comparison": {
      const up = b.diffMinor > 0;
      const max = Math.max(1, b.a.valueMinor, b.b.valueMinor);
      return (
        <div className="rounded-[14px] bg-card-2 px-4 py-3">
          <div className="mb-2 flex items-center gap-1.5 font-semibold" style={{ color: tintText(up ? "orange" : "green") }}>
            {b.diffMinor !== 0 && (up ? <ArrowUpRight aria-hidden className="size-4" /> : <ArrowDownRight aria-hidden className="size-4" />)}
            <span className="tabular">{b.diffMinor === 0 ? "No change" : `${up ? "+" : "−"}${formatMoney(Math.abs(b.diffMinor), b.currency)}`}{b.pct !== null && b.diffMinor !== 0 ? ` (${up ? "+" : "−"}${Math.abs(b.pct)}%)` : ""}</span>
          </div>
          {[b.a, b.b].map((p, i) => (
            <div key={i} className="mb-1.5 last:mb-0">
              <div className="flex justify-between gap-2 text-sm"><span className="text-label-2">{p.label} · {plural(p.count, "transaction")}</span><span className="tabular font-medium">{formatMoney(p.valueMinor, b.currency)}</span></div>
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-[var(--sd-separator)]"><div className="h-full rounded-full" style={{ width: `${(p.valueMinor / max) * 100}%`, background: tintVar(i === 0 ? "blue" : "gray") }} /></div>
            </div>
          ))}
        </div>
      );
    }
    case "breakdown": {
      const max = Math.max(1, ...b.items.map((i) => Math.abs(i.diffMinor ?? i.valueMinor)));
      const items = b.items.slice(0, 8);
      return (
        <div className="rounded-[14px] bg-card-2 px-4 py-3">
          <div className="section-header mb-2">{b.title}</div>
          <ul className="flex flex-col gap-2">
            {items.map((i) => {
              const value = i.diffMinor ?? i.valueMinor;
              const tint: Tint = i.diffMinor !== undefined ? (i.diffMinor > 0 ? "orange" : "green") : b.kind === "category" && i.key in CATEGORY_ICONS ? categoryTint(i.key as never) : KIND_TINT[b.kind];
              return (
                <li key={i.key}>
                  <div className="flex justify-between gap-2 text-sm">
                    <span className="truncate">{i.label}{i.count > 0 && <span className="text-label-2"> · {i.count}</span>}</span>
                    <span className="tabular shrink-0 font-medium">{i.diffMinor !== undefined ? `${value > 0 ? "+" : "−"}${formatMoney(Math.abs(value), b.currency)}` : formatMoney(value, b.currency)}</span>
                  </div>
                  <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-[var(--sd-separator)]"><div className="h-full rounded-full" style={{ width: `${(Math.abs(value) / max) * 100}%`, background: tintVar(tint) }} /></div>
                </li>
              );
            })}
          </ul>
          {b.items.length > items.length && <p className="mt-2 text-xs text-label-2">+{b.items.length - items.length} more</p>}
        </div>
      );
    }
    case "transactions":
      return (
        <div className="rounded-[14px] bg-card-2 px-2 py-2">
          <div className="section-header mb-1 px-2">{b.title}</div>
          {b.items.map((t) => <TransactionCard key={t.id} t={t} />)}
          {!!b.more && <p className="px-2 pb-1 text-xs text-label-2">+{b.more} more not shown</p>}
        </div>
      );
    case "findings":
      return (
        <div className="rounded-[14px] bg-card-2 px-4 py-3">
          <div className="section-header mb-2">{b.title}</div>
          <ul className="flex flex-col gap-2.5">
            {b.items.map((f, i) => (
              <li key={i} className="flex gap-2.5">
                <TriangleAlert aria-hidden className="mt-0.5 size-4 shrink-0" style={{ color: tintVar("orange") }} />
                <span><span className="block text-sm font-medium">{f.title}</span><span className="block text-xs text-label-2">{f.detail}</span></span>
              </li>
            ))}
          </ul>
        </div>
      );
  }
}

const TOOL_LABEL: Record<string, string> = {
  search_transactions: "Searched your transactions", calculate_spending: "Calculated your spending", compare_periods: "Compared two periods",
  get_transaction: "Opened one transaction", get_weekly_summary: "Built your weekly summary", find_unusual_spending: "Compared with your previous weeks",
  get_spending_insights: "Compared with your own normal",
};

const STATUS_CHIP: Partial<Record<AskAnswer["status"], { label: string; tint: Tint }>> = {
  clarify: { label: "Needs one more detail", tint: "indigo" },
  no_match: { label: "No matching records", tint: "gray" },
  no_data: { label: "No data yet", tint: "gray" },
  refused: { label: "Can't help with that", tint: "orange" },
  error: { label: "Couldn't check right now", tint: "red" },
};

/** First sentence = the direct answer (money like "RM 15.00" never splits a sentence). */
function splitAnswer(text: string): [string, string] {
  const m = /^([\s\S]+?[.?!])\s+(?=[A-Z“"(])/.exec(text);
  return m ? [m[1], text.slice(m[0].length)] : [text, ""];
}

export function AnswerView({ answer, onFollowUp, debug }: { answer: AskAnswer; onFollowUp: (q: string) => void; debug?: boolean }) {
  const [showDetails, setShowDetails] = useState(false);
  const [why, setWhy] = useState(false);
  // "Based on N" describes the answer's own dataset (the first evidence), never a supporting lookup's history.
  const count = answer.evidence[0]?.transactionCount ?? 0;
  const chip = STATUS_CHIP[answer.status];
  const [lead, rest] = splitAnswer(answer.text);
  // The block that IS the answer stays visible (a figure, a comparison, findings, or the matches of a lookup);
  // everything else is one tap away.
  const lookup = answer.meta.intent === "SEARCH" || answer.meta.intent === "TRANSACTION_DETAIL";
  const primaryCount = answer.blocks.length && (["metric", "comparison", "findings"].includes(answer.blocks[0].type) || lookup) ? 1 : 0;
  const primary = answer.blocks.slice(0, primaryCount);
  const details = answer.blocks.slice(primaryCount);
  const txCount = details.reduce((n, b) => n + (b.type === "transactions" ? b.items.length : 0), 0);
  return (
    <div className="flex flex-col gap-3">
      {chip && (
        <span className="inline-flex w-fit items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold" style={{ color: tintText(chip.tint), background: `color-mix(in srgb, ${tintVar(chip.tint)} 14%, transparent)` }}>
          {answer.status === "error" || answer.status === "refused" ? <TriangleAlert aria-hidden className="size-3.5" /> : <HelpCircle aria-hidden className="size-3.5" />}
          {chip.label}
        </span>
      )}
      {answer.preface && <p className="text-[15px]">{answer.preface}</p>}
      {answer.understoodAs && <p className="text-xs italic text-label-2">I read this as “{answer.understoodAs}”</p>}
      <div className={cx("leading-relaxed", answer.status === "error" && "text-red")}>
        <p className="whitespace-pre-line text-[16px] font-semibold">{lead}</p>
        {rest && <p className="mt-1 whitespace-pre-line text-[15px] text-label">{rest}</p>}
      </div>
      {primary.map((b, i) => <Block key={`p${i}`} b={b} />)}
      {answer.insight && (
        <div className="flex gap-2.5 rounded-[14px] px-4 py-3" style={{ background: "color-mix(in srgb, var(--sd-accent) 9%, transparent)" }}>
          <Lightbulb aria-hidden className="mt-0.5 size-4 shrink-0 text-[var(--sd-accent-text)]" />
          <div><div className="section-header mb-0.5">Insight</div><p className="text-[14px]">{answer.insight}</p></div>
        </div>
      )}
      {answer.suggestion && (
        <div className="flex gap-2.5 rounded-[14px] border border-separator px-4 py-3">
          <Target aria-hidden className="mt-0.5 size-4 shrink-0" style={{ color: tintVar("green") }} />
          <div>
            <div className="section-header mb-0.5">Suggestion</div>
            <p className="text-[14px]">{answer.suggestion}</p>
            <p className="mt-1 text-[11px] text-label-2">Based on your own records — not financial advice.</p>
          </div>
        </div>
      )}
      {details.length > 0 && (
        <>
          <button type="button" aria-expanded={showDetails} onClick={() => setShowDetails((v) => !v)}
            className="inline-flex w-fit items-center gap-1 rounded-full bg-card-2 px-3 py-1.5 text-[13px] font-medium text-[var(--sd-accent-text)]">
            {showDetails ? "Hide details" : txCount && details.every((b) => b.type === "transactions") ? `View ${plural(txCount, "transaction")}` : `Show details${txCount ? ` · ${plural(txCount, "transaction")}` : ""}`}
            <ChevronDown aria-hidden className={cx("size-3.5 transition-transform", showDetails && "rotate-180")} />
          </button>
          {showDetails && <div className="flex flex-col gap-2.5">{details.map((b, i) => <Block key={`d${i}`} b={b} />)}</div>}
        </>
      )}
      {answer.evidence.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-label-2">
          <span className="inline-flex items-center gap-1"><Info aria-hidden className="size-3.5" />Based on {plural(count, "transaction")} · {answer.evidence[0].period}</span>
          <button type="button" className="inline-flex items-center gap-0.5 font-medium text-[var(--sd-accent-text)]" aria-expanded={why} onClick={() => setWhy((v) => !v)}>
            Why this answer? <ChevronDown aria-hidden className={cx("size-3.5 transition-transform", why && "rotate-180")} />
          </button>
        </div>
      )}
      {why && (
        <ul className="rounded-[12px] border border-separator px-3 py-2 text-xs text-label-2">
          {answer.evidence.map((e, i) => (
            <li key={i}>{TOOL_LABEL[e.tool] ?? "Checked your records"}: {e.filters} · {e.period} · {plural(e.transactionCount, "transaction")}</li>
          ))}
          <li className="mt-1">{answer.meta.route === "model" ? `Explained by ${answer.meta.model ?? "the AI model"}; every figure was checked against SpenDrop's own calculation.` : "Calculated by SpenDrop from your records — no guessing."}</li>
        </ul>
      )}
      {debug && (
        <pre className="overflow-x-auto rounded-[10px] bg-card-2 p-2 text-[11px] text-label-2">{JSON.stringify({ ...answer.meta, confidence: answer.confidence, status: answer.status }, null, 1)}</pre>
      )}
      {answer.followUps.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {answer.followUps.map((q) => (
            <button key={q} type="button" onClick={() => onFollowUp(q)} className="rounded-full border border-separator px-3 py-1.5 text-[13px] font-medium text-[var(--sd-accent-text)] hover:bg-card-2">{q}</button>
          ))}
        </div>
      )}
    </div>
  );
}

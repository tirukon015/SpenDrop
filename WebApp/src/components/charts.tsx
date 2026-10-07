"use client";

// Small, dependency-free SVG charts. Each chart has a text alternative (aria-label / visually hidden table).
import { formatMoney } from "@/lib/domain/money";
import { AnimatedMoney } from "@/components/motion";
import { cx, tintVar } from "@/components/ui/primitives";
import type { Tint } from "@/lib/domain/constants";

export interface BarDatum { label: string; shortLabel?: string; valueMinor: number; secondaryMinor?: number }

/** Vertical bars (e.g. daily spending). Optional secondary series drawn side by side (Money In / Money Out). */
export function BarChart({ data, tint = "blue", secondaryTint = "gray", height = 160, title, currency = "RM" }: {
  data: BarDatum[]; tint?: Tint; secondaryTint?: Tint; height?: number; title: string; currency?: string;
}) {
  const max = Math.max(1, ...data.map((d) => Math.max(d.valueMinor, d.secondaryMinor ?? 0)));
  const dual = data.some((d) => d.secondaryMinor !== undefined);
  const labelEvery = Math.ceil(data.length / 8);
  return (
    <figure className="w-full">
      <div className="flex items-end gap-[3px]" style={{ height }} role="img" aria-label={`${title}. ${data.map((d) => `${d.label}: ${formatMoney(d.valueMinor, currency)}`).join(", ")}`}>
        {data.map((d, i) => (
          <div key={i} className="group relative flex h-full flex-1 items-end justify-center gap-[2px]" title={`${d.label}: ${formatMoney(d.valueMinor, currency)}${dual ? ` / ${formatMoney(d.secondaryMinor ?? 0, currency)}` : ""}`}>
            <div className="sd-bar w-full max-w-[28px] rounded-t-[4px]" style={{ ["--i" as string]: i, height: `${(d.valueMinor / max) * 100}%`, minHeight: d.valueMinor > 0 ? 2 : 0, background: tintVar(tint) }} />
            {dual && <div className="sd-bar w-full max-w-[28px] rounded-t-[4px]" style={{ ["--i" as string]: i, height: `${((d.secondaryMinor ?? 0) / max) * 100}%`, minHeight: (d.secondaryMinor ?? 0) > 0 ? 2 : 0, background: tintVar(secondaryTint), opacity: 0.55 }} />}
          </div>
        ))}
      </div>
      <div aria-hidden className="mt-1.5 flex gap-[3px] text-[10px] text-label-2">
        {data.map((d, i) => <span key={i} className="flex-1 truncate text-center">{i % labelEvery === 0 ? d.shortLabel ?? d.label : ""}</span>)}
      </div>
    </figure>
  );
}

export interface ShareDatum { key: string; label: string; valueMinor: number; tint: Tint; icon?: React.ComponentType<{ className?: string }>; count?: number }

/** Donut + legend (category / channel / account share of spending). */
export function Donut({ data, title, currency = "RM", size = 148 }: { data: ShareDatum[]; title: string; currency?: string; size?: number }) {
  const total = data.reduce((s, d) => s + d.valueMinor, 0);
  const r = 42, c = 2 * Math.PI * r;
  let offset = 0;
  return (
    <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-start">
      <svg width={size} height={size} viewBox="0 0 100 100" role="img" aria-label={`${title}: ${data.map((d) => `${d.label} ${formatMoney(d.valueMinor, currency)}`).join(", ")}`} className="shrink-0 -rotate-90">
        <circle cx="50" cy="50" r={r} fill="none" stroke="var(--sd-card-2)" strokeWidth="13" />
        {total > 0 && data.map((d) => {
          const length = (d.valueMinor / total) * c;
          const el = <circle key={d.key} className="sd-arc" cx="50" cy="50" r={r} fill="none" stroke={tintVar(d.tint)} strokeWidth="13" strokeDasharray={`${Math.max(length - 0.8, 0.01)} ${c}`} strokeDashoffset={-offset} />;
          offset += length;
          return el;
        })}
      </svg>
      <ShareList data={data} currency={currency} total={total} />
    </div>
  );
}

export function ShareList({ data, currency = "RM", total, limit }: { data: ShareDatum[]; currency?: string; total?: number; limit?: number }) {
  const sum = total ?? data.reduce((s, d) => s + d.valueMinor, 0);
  return (
    <ul className="flex w-full flex-col gap-2.5">
      {data.slice(0, limit ?? data.length).map((d) => {
        const pct = sum > 0 ? Math.round((d.valueMinor / sum) * 100) : 0;
        const Icon = d.icon;
        return (
          <li key={d.key} className="flex flex-col gap-1">
            <div className="flex items-center justify-between gap-2 text-sm">
              <span className="flex min-w-0 items-center gap-2">
                {Icon ? <span style={{ color: tintVar(d.tint) }}><Icon className="size-4" /></span> : <span aria-hidden className="size-2.5 shrink-0 rounded-[3px]" style={{ background: tintVar(d.tint) }} />}
                <span className="truncate">{d.label}</span>
                {d.count !== undefined && <span className="text-xs text-label-2">· {d.count}</span>}
              </span>
              <span className="tabular shrink-0 font-semibold"><AnimatedMoney minor={d.valueMinor} currency={currency} /> <span className="text-xs font-normal text-label-2">{pct}%</span></span>
            </div>
            <div aria-hidden className="h-1.5 overflow-hidden rounded-full bg-card-2">
              <div className={cx("sd-fill h-full rounded-full")} style={{ width: `${pct}%`, background: tintVar(d.tint) }} />
            </div>
          </li>
        );
      })}
    </ul>
  );
}

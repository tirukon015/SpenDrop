"use client";

// SpenDrop motion primitives: small, dependency-free, reduced-motion aware.
// Values animate only when they change (first mount counts up from 0); nothing replays on re-render.
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { formatMoney } from "@/lib/domain/money";

const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);

/**
 * Tweens an integer (e.g. sen) from its previous value to `value`. Always integers → money never shows odd
 * fractions; the final frame is exactly `value`.
 */
export function useCountUp(value: number, duration = 750) {
  const [shown, setShown] = useState(0);
  const from = useRef(0);
  const frame = useRef<number | null>(null);
  useEffect(() => {
    const start = from.current;
    if (start === value) return;
    if (prefersReducedMotion() || document.visibilityState === "hidden") {
      from.current = value;
      frame.current = requestAnimationFrame(() => setShown(value));
      return () => { if (frame.current) cancelAnimationFrame(frame.current); };
    }
    const t0 = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - t0) / duration);
      const next = t >= 1 ? value : Math.round(start + (value - start) * easeOutCubic(t));
      from.current = next;
      setShown(next);
      if (t < 1) frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
    return () => { if (frame.current) cancelAnimationFrame(frame.current); };
  }, [value, duration]);
  return shown;
}

/** "RM 1,234.50" that counts to its value (accessible name is always the final value). */
export function AnimatedMoney({ minor, currency = "RM", sign, className, style }: {
  minor: number; currency?: string; sign?: boolean; className?: string; style?: CSSProperties;
}) {
  const shown = useCountUp(minor);
  const text = (n: number) => `${sign && n >= 0 ? "+" : ""}${formatMoney(n, currency)}`;
  return (
    <span className={className} style={style} data-value={text(minor)}>
      <span aria-hidden>{text(shown)}</span>
      <span className="sr-only">{text(minor)}</span>
    </span>
  );
}

export function AnimatedNumber({ value, className, suffix = "" }: { value: number; className?: string; suffix?: string }) {
  const shown = useCountUp(value, 600);
  return <span className={className} data-value={`${value}${suffix}`}><span aria-hidden>{shown}{suffix}</span><span className="sr-only">{value}{suffix}</span></span>;
}

/** Stagger index for the entrance animation (`sd-rise`), capped so long lists never wait. */
export const rise = (i: number, max = 10): CSSProperties => ({ ["--i" as string]: Math.min(i, max) });

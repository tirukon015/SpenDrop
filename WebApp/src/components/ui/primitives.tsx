"use client";

import { LoaderCircle, TriangleAlert, X } from "lucide-react";
import Link from "next/link";
import { forwardRef, useEffect, useRef, useState, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from "react";
import type { Tint } from "@/lib/domain/constants";

export const cx = (...classes: (string | false | null | undefined)[]) => classes.filter(Boolean).join(" ");

/** Tint → CSS colour var (Apple system colours, light/dark aware). */
export const tintVar = (tint: Tint) => `var(--sd-${tint === "primary" ? "primary" : tint})`;
/** Same tint, deepened (light) / lightened (dark) so small text meets WCAG AA contrast. Use for TEXT. */
export const tintText = (tint: Tint) => (tint === "primary" ? "var(--sd-label)" : `color-mix(in srgb, var(--sd-${tint}) 50%, var(--sd-label))`);

type ButtonVariant = "primary" | "secondary" | "plain" | "destructive" | "tinted";

export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: ButtonVariant; loading?: boolean; size?: "md" | "sm" | "lg" }>(
  function Button({ variant = "primary", loading, size = "md", className, children, disabled, type = "button", ...props }, ref) {
    return (
      <button
        ref={ref}
        // Never submit a surrounding form by accident (sheets live inside the transaction form); Save uses type="submit".
        type={type}
        disabled={disabled || loading}
        className={cx(
          "inline-flex select-none items-center justify-center gap-2 rounded-control font-semibold transition-[opacity,background-color,transform] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45",
          size === "sm" && "min-h-9 px-3 text-sm",
          size === "md" && "min-h-11 px-4 text-[15px]",
          size === "lg" && "min-h-[52px] px-5 text-[17px]",
          variant === "primary" && "bg-[var(--sd-accent-fill)] text-white hover:opacity-90",
          variant === "secondary" && "bg-card-2 text-label hover:bg-separator",
          variant === "tinted" && "bg-[color-mix(in_srgb,var(--sd-accent)_14%,transparent)] text-[var(--sd-accent-text)] hover:bg-[color-mix(in_srgb,var(--sd-accent)_22%,transparent)]",
          variant === "plain" && "text-[var(--sd-accent-text)] hover:bg-card-2",
          variant === "destructive" && "bg-[color-mix(in_srgb,var(--sd-red)_12%,transparent)] text-red hover:bg-[color-mix(in_srgb,var(--sd-red)_20%,transparent)]",
          className,
        )}
        {...props}
      >
        {loading && <LoaderCircle aria-hidden className="size-4 animate-spin" />}
        {children}
      </button>
    );
  },
);

export function ButtonLink({ href, children, variant = "primary", className }: { href: string; children: ReactNode; variant?: ButtonVariant; className?: string }) {
  return (
    <Link
      href={href}
      className={cx(
        "inline-flex min-h-11 items-center justify-center gap-2 rounded-control px-4 text-[15px] font-semibold transition-opacity hover:opacity-90",
        variant === "primary" && "bg-[var(--sd-accent-fill)] text-white",
        variant === "tinted" && "bg-[color-mix(in_srgb,var(--sd-accent)_14%,transparent)] text-[var(--sd-accent-text)]",
        variant === "secondary" && "bg-card-2 text-label",
        variant === "plain" && "text-[var(--sd-accent-text)]",
        className,
      )}
    >
      {children}
    </Link>
  );
}

export function Card({ children, className, as: As = "section", ...rest }: { children: ReactNode; className?: string; as?: "section" | "div" | "article"; "aria-label"?: string; id?: string; style?: React.CSSProperties }) {
  return <As className={cx("rounded-card bg-card p-4 shadow-card", className)} {...rest}>{children}</As>;
}

export function SectionHeader({ children, action, id }: { children: ReactNode; action?: ReactNode; id?: string }) {
  return (
    <div className="mb-2 flex items-center justify-between gap-2 px-1">
      <h2 id={id} className="section-header">{children}</h2>
      {action}
    </div>
  );
}

export function Field({ label, hint, error, children, htmlFor }: { label: string; hint?: ReactNode; error?: string | null; children: ReactNode; htmlFor?: string }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={htmlFor} className="section-header px-1">{label}</label>
      {children}
      {error ? <p role="alert" className="px-1 text-xs text-red">{error}</p> : hint ? <p className="px-1 text-xs text-label-2">{hint}</p> : null}
    </div>
  );
}

const fieldClass =
  "w-full min-h-11 rounded-field border border-transparent bg-card px-3.5 py-2.5 text-[16px] text-label placeholder:text-label-3 focus:border-[var(--sd-accent)] focus:outline-none shadow-card";

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input({ className, ...props }, ref) {
  return <input ref={ref} className={cx(fieldClass, className)} {...props} />;
});

export const TextArea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function TextArea({ className, ...props }, ref) {
  return <textarea ref={ref} className={cx(fieldClass, "min-h-20 resize-y", className)} {...props} />;
});

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select({ className, children, ...props }, ref) {
  return (
    <select ref={ref} className={cx(fieldClass, "appearance-none bg-[length:12px] bg-[right_14px_center] bg-no-repeat pr-9", className)}
      style={{ backgroundImage: "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 8'><path fill='none' stroke='%238e8e93' stroke-width='1.6' d='M1 1.5l5 5 5-5'/></svg>\")" }}
      {...props}>
      {children}
    </select>
  );
});

/** iOS-style segmented control (radio group semantics). */
export function Segmented<T extends string>({ value, options, onChange, label, className, size = "md" }: {
  value: T; options: { id: T; label: string }[]; onChange: (v: T) => void; label: string; className?: string; size?: "md" | "sm";
}) {
  return (
    <div role="radiogroup" aria-label={label} className={cx("flex w-full rounded-[10px] bg-card-2 p-0.5", className)}>
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="radio"
          aria-checked={value === o.id}
          onClick={() => onChange(o.id)}
          onKeyDown={(e) => {
            const i = options.findIndex((x) => x.id === value);
            if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); onChange(options[(i + 1) % options.length].id); }
            if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); onChange(options[(i - 1 + options.length) % options.length].id); }
          }}
          tabIndex={value === o.id ? 0 : -1}
          className={cx(
            "flex-1 rounded-[8px] px-2 font-medium transition-colors",
            size === "md" ? "min-h-9 text-[13px]" : "min-h-8 text-[12px]",
            value === o.id ? "bg-card text-label shadow-[0_1px_3px_rgba(0,0,0,0.12)] dark:bg-[#636366]" : "text-label-2 hover:text-label",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Toggle({ checked, onChange, label, description, id }: { checked: boolean; onChange: (v: boolean) => void; label: ReactNode; description?: ReactNode; id?: string }) {
  return (
    <label className="flex min-h-11 cursor-pointer items-center justify-between gap-3" htmlFor={id}>
      <span className="flex flex-col">
        <span className="text-[15px] font-medium">{label}</span>
        {description && <span className="text-xs text-label-2">{description}</span>}
      </span>
      <span className="relative inline-flex shrink-0">
        <input id={id} type="checkbox" role="switch" aria-checked={checked} checked={checked} onChange={(e) => onChange(e.target.checked)} className="peer sr-only" />
        <span aria-hidden className={cx("h-[31px] w-[51px] rounded-full transition-colors peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-[var(--sd-accent)]", checked ? "bg-green" : "bg-card-2 dark:bg-[#39393d]")} />
        <span aria-hidden className={cx("absolute top-[2px] size-[27px] rounded-full bg-white shadow transition-transform", checked ? "translate-x-[22px]" : "translate-x-[2px]")} />
      </span>
    </label>
  );
}

export function Chip({ selected, onClick, children, tint }: { selected?: boolean; onClick?: () => void; children: ReactNode; tint?: Tint }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className={cx(
        "inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-medium transition-colors",
        selected ? "bg-[var(--sd-accent-fill)] text-white" : "bg-card-2 text-label hover:bg-separator",
      )}
      style={selected && tint ? { background: tintVar(tint) } : undefined}
    >
      {children}
    </button>
  );
}

/** Coloured rounded tile with an icon (like the iOS category tiles). */
export function IconTile({ icon: Icon, tint, size = 44 }: { icon: React.ComponentType<{ className?: string; "aria-hidden"?: boolean; style?: React.CSSProperties }>; tint: Tint; size?: number }) {
  return (
    <span
      aria-hidden
      className="inline-flex shrink-0 items-center justify-center rounded-[12px]"
      style={{ width: size, height: size, background: `color-mix(in srgb, ${tintVar(tint)} 15%, transparent)`, color: tintVar(tint) }}
    >
      <Icon aria-hidden className={size >= 40 ? "size-5" : "size-4"} />
    </span>
  );
}

export function Avatar({ name, size = 40 }: { name: string; size?: number }) {
  const initials = name.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase()).join("") || "?";
  return (
    <span aria-hidden className="inline-flex shrink-0 items-center justify-center rounded-full font-semibold"
      style={{ width: size, height: size, fontSize: size * 0.38, background: "color-mix(in srgb, var(--sd-blue) 15%, transparent)", color: tintText("blue") }}>
      {initials}
    </span>
  );
}

export function EmptyState({ icon: Icon, title, message, action }: { icon: React.ComponentType<{ className?: string }>; title: string; message: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-12 text-center">
      <Icon aria-hidden className="size-11 text-label-3" />
      <div>
        <p className="text-[17px] font-semibold">{title}</p>
        <p className="mx-auto mt-1 max-w-sm text-sm text-label-2">{message}</p>
      </div>
      {action}
    </div>
  );
}

export function Skeleton({ className }: { className?: string }) {
  return <div aria-hidden className={cx("skeleton h-4", className)} />;
}

export function ListSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div role="status" aria-label="Loading" className="flex flex-col gap-4 p-4">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="flex items-center gap-3">
          <Skeleton className="size-11 rounded-[12px]" />
          <div className="flex flex-1 flex-col gap-2">
            <Skeleton className="h-4 w-2/5" />
            <Skeleton className="h-3 w-3/5" />
          </div>
          <Skeleton className="h-4 w-16" />
        </div>
      ))}
    </div>
  );
}

export function ErrorBanner({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div role="alert" className="flex items-start gap-3 rounded-field bg-[color-mix(in_srgb,var(--sd-orange)_12%,transparent)] p-3 text-sm">
      <TriangleAlert aria-hidden className="mt-0.5 size-4 shrink-0 text-orange" />
      <p className="flex-1">{message}</p>
      {onRetry && <button type="button" onClick={onRetry} className="font-semibold text-[var(--sd-accent-text)]">Retry</button>}
    </div>
  );
}

/**
 * Modal sheet on the native <dialog> (focus trap, Escape, inert background for free). Bottom sheet on phones,
 * centred dialog on larger screens.
 */
export function Sheet({ open, onClose, title, children, footer, wide }: { open: boolean; onClose: () => void; title: string; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  // Content stays rendered during the close animation, then unmounts.
  const [lingering, setLingering] = useState(false);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    if (open) {
      if (!dialog.open) dialog.showModal();
      timer = setTimeout(() => setLingering(true), 0);
    } else if (dialog.open) {
      // Close right away so the page behind is usable immediately; CSS animates the exit (display/overlay
      // allow-discrete) while the content stays rendered for the length of that animation.
      dialog.close();
      timer = setTimeout(() => setLingering(false), 260);
    }
    return () => clearTimeout(timer);
  }, [open]);
  // Close immediately when this screen is hidden or unmounted (e.g. navigating away): a modal dialog left open on a
  // hidden screen would make the whole page inert. It reopens if the screen comes back with the sheet open.
  useEffect(() => () => {
    const dialog = ref.current;
    if (dialog?.open) dialog.close();
  }, []);
  return (
    <dialog
      ref={ref}
      // Only user actions close the sheet (Escape, backdrop, Close button). The native "close" event is not used:
      // it also fires after our own programmatic close and would close a sheet that was just reopened.
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }}
      aria-label={title}
      className={cx(
        "sd-sheet m-0 mt-auto max-h-[92dvh] w-full max-w-none overflow-hidden rounded-t-[20px] bg-bg p-0 text-label",
        "sm:m-auto sm:max-h-[86dvh] sm:rounded-[20px]",
        wide ? "sm:max-w-2xl" : "sm:max-w-lg",
      )}
    >
      {(open || lingering) && (
        <div className="flex max-h-[92dvh] flex-col sm:max-h-[86dvh]">
          <header className="flex items-center justify-between gap-3 border-b border-separator bg-bg px-4 py-3">
            <h2 className="text-[17px] font-semibold">{title}</h2>
            <button type="button" onClick={onClose} aria-label="Close" className="inline-flex size-9 items-center justify-center rounded-full bg-card-2 text-label-2 hover:text-label">
              <X aria-hidden className="size-4" />
            </button>
          </header>
          <div className="flex-1 overflow-y-auto px-4 py-4">{children}</div>
          {footer && <footer className="border-t border-separator bg-bg px-4 py-3 pb-safe">{footer}</footer>}
        </div>
      )}
    </dialog>
  );
}

export function Row({ children, className, onClick, href }: { children: ReactNode; className?: string; onClick?: () => void; href?: string }) {
  const classes = cx("flex min-h-12 w-full items-center gap-3 px-4 py-2.5 text-left", (onClick || href) && "hover:bg-card-2 focus-visible:bg-card-2", className);
  if (href) return <Link href={href} className={classes}>{children}</Link>;
  if (onClick) return <button type="button" onClick={onClick} className={classes}>{children}</button>;
  return <div className={classes}>{children}</div>;
}

export function Divider({ inset = 0 }: { inset?: number }) {
  return <div aria-hidden className="h-px bg-separator" style={{ marginLeft: inset }} />;
}

"use client";

import { BookUser, ChartColumn, CircleEllipsis, CloudOff, House, PanelLeftClose, PanelLeftOpen, Plus, ReceiptText, RefreshCw } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { BrandMark } from "@/components/brand";
import { useData } from "@/components/providers/data-provider";
import { cx } from "@/components/ui/primitives";
import { isDemoMode } from "@/lib/supabase/config";
import { SIDEBAR_KEY } from "@/lib/theme";
import { useStored } from "@/lib/use-stored";

/** Same five sections as the iOS tab bar (Common/Design/tokens.json → navigation). */
export const NAV = [
  { href: "/", label: "Home", icon: House },
  { href: "/transactions", label: "Transactions", icon: ReceiptText },
  { href: "/paybook", label: "PayBook", icon: BookUser },
  { href: "/breakdown", label: "Breakdown", icon: ChartColumn },
  { href: "/more", label: "More", icon: CircleEllipsis },
];

const isActive = (pathname: string, href: string) => (href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(href + "/"));

function relative(iso: string | null) {
  if (!iso) return "Not synced yet";
  const seconds = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 45) return "Synced just now";
  if (seconds < 3600) return `Synced ${Math.round(seconds / 60)} min ago`;
  return `Synced ${new Intl.DateTimeFormat("en-MY", { hour: "numeric", minute: "2-digit" }).format(new Date(iso))}`;
}

export function SyncStatus({ compact }: { compact?: boolean }) {
  const { status, lastSyncedAt, refresh, online } = useData();
  const [, tick] = useState(0);
  useEffect(() => {
    const t = window.setInterval(() => tick((n) => n + 1), 30_000);
    return () => window.clearInterval(t);
  }, []);
  if (!online || status === "offline")
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-orange" role="status">
        <CloudOff aria-hidden className="size-3.5" /> {compact ? "Offline" : "Offline · showing saved data"}
      </span>
    );
  return (
    <button type="button" onClick={() => refresh()} className="inline-flex items-center gap-1.5 text-xs text-label-2 hover:text-label" aria-label="Sync now">
      <RefreshCw aria-hidden className={cx("size-3.5", (status === "syncing" || status === "loading") && "animate-spin")} />
      <span role="status">{status === "syncing" || status === "loading" ? "Syncing…" : relative(lastSyncedAt)}</span>
    </button>
  );
}

type SidebarState = "open" | "hidden";
const isMac = () => typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);

/**
 * Desktop/tablet sidebar visibility. The state lives on <html data-sidebar> (set before paint from localStorage,
 * so a hidden sidebar never flashes) and in localStorage; toggling changes only that attribute — the pages
 * themselves don't re-render, so nothing inside them restarts.
 */
function useSidebar() {
  const [stored, store] = useStored<SidebarState>("local", SIDEBAR_KEY, "open");
  const toggle = useCallback(() => {
    const next: SidebarState = document.documentElement.dataset.sidebar === "hidden" ? "open" : "hidden";
    document.documentElement.dataset.sidebar = next;
    store(next);
  }, [store]);
  useEffect(() => {
    // Enable transitions only after the first paint (no animation on page load).
    const id = requestAnimationFrame(() => { document.documentElement.dataset.sidebarReady = "1"; });
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || e.shiftKey || e.altKey || e.key.toLowerCase() !== "b") return;
      const t = e.target as HTMLElement | null;
      if (t && (t.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName))) return;
      if (!window.matchMedia("(min-width: 768px)").matches) return;
      e.preventDefault();
      toggle();
    };
    window.addEventListener("keydown", onKey);
    return () => { cancelAnimationFrame(id); window.removeEventListener("keydown", onKey); };
  }, [toggle]);
  return { hidden: stored === "hidden", toggle };
}

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { source } = useData();
  const adding = pathname.startsWith("/add");
  const { hidden, toggle } = useSidebar();
  // Sliding active highlight: positioned from the active link (measured only on route change / resize).
  const listRef = useRef<HTMLUListElement>(null);
  const indicatorRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const place = () => {
      const indicator = indicatorRef.current;
      const active = listRef.current?.querySelector<HTMLElement>('[aria-current="page"]')?.parentElement;
      if (!indicator) return;
      if (!active) { indicator.style.opacity = "0"; return; }
      indicator.style.opacity = "1";
      indicator.style.height = `${active.offsetHeight}px`;
      indicator.style.transform = `translateY(${active.offsetTop}px)`;
      requestAnimationFrame(() => { indicator.dataset.ready = "1"; });
    };
    place();
    window.addEventListener("resize", place);
    return () => window.removeEventListener("resize", place);
  }, [pathname]);
  const shortcut = isMac() ? "⌘B" : "Ctrl+B";

  return (
    <div className="min-h-dvh md:flex">
      {/* Desktop sidebar (lg) / tablet rail (md) */}
      <nav aria-label="Main" inert={hidden || undefined} aria-hidden={hidden || undefined}
        className="sd-sidebar sticky top-0 hidden h-dvh shrink-0 overflow-hidden border-r border-separator bg-card/60 backdrop-blur md:flex md:w-[84px] lg:w-[248px]">
        <div className="flex h-full shrink-0 flex-col md:w-[84px] lg:w-[248px]">
        <div className="flex items-center justify-between gap-2 px-5 pb-4 pt-6 max-lg:flex-col max-lg:px-0">
          <Link href="/" className="flex items-center gap-2.5">
            <BrandMark size={32} />
            <span className="text-[19px] font-bold tracking-tight max-lg:sr-only">SpenDrop</span>
          </Link>
          <button type="button" onClick={toggle} aria-label="Hide sidebar" data-tip={`Hide sidebar (${shortcut})`} suppressHydrationWarning
            className="sd-tip inline-flex size-9 items-center justify-center rounded-[10px] text-label-2 transition-colors hover:bg-card-2 hover:text-label">
            <PanelLeftClose aria-hidden className="size-[18px]" />
          </button>
        </div>
        <div className="px-3 pb-3 max-lg:px-2">
          <Link href="/add" className="flex min-h-11 items-center justify-center gap-2 rounded-control bg-[var(--sd-accent-fill)] font-semibold text-white hover:opacity-90" aria-label="Add transaction">
            <Plus aria-hidden className="size-5" /> <span className="max-lg:sr-only">Add Transaction</span>
          </Link>
        </div>
        <ul ref={listRef} className="relative flex flex-1 flex-col gap-1 px-3 max-lg:px-2">
          <li aria-hidden className="pointer-events-none absolute inset-x-3 top-0 max-lg:inset-x-2"><div ref={indicatorRef} className="sd-nav-indicator" /></li>
          {NAV.map(({ href, label, icon: Icon }) => {
            const active = isActive(pathname, href);
            return (
              <li key={href}>
                <Link
                  href={href}
                  aria-current={active ? "page" : undefined}
                  className={cx(
                    "flex min-h-11 items-center gap-3 rounded-control px-3 text-[15px] font-medium transition-colors max-lg:flex-col max-lg:justify-center max-lg:gap-1 max-lg:px-1 max-lg:py-2 max-lg:text-[11px]",
                    "relative transition-colors duration-200",
                    active ? "text-[var(--sd-accent-text)]" : "text-label-2 hover:bg-card-2 hover:text-label",
                  )}
                >
                  <Icon aria-hidden className="size-5 shrink-0" />
                  {label}
                </Link>
              </li>
            );
          })}
        </ul>
        <div className="flex flex-col gap-1 border-t border-separator px-5 py-4 max-lg:items-center max-lg:px-2">
          <SyncStatus compact />
          <span className="truncate text-xs text-label-2 max-lg:hidden">{source?.email ?? ""}</span>
        </div>
        </div>
      </nav>

      {/* Shown only while the sidebar is hidden (desktop/tablet) */}
      <button type="button" onClick={toggle} aria-label="Show sidebar" data-tip={`Show sidebar (${shortcut})`} data-tip-side="right"
        tabIndex={hidden ? 0 : -1} aria-hidden={!hidden || undefined} suppressHydrationWarning
        style={{ top: isDemoMode ? 40 : 12 }}
        className="sd-sidebar-reopen sd-tip fixed left-3 z-40 hidden size-10 items-center justify-center rounded-[12px] border border-separator bg-card/80 text-label-2 shadow-card backdrop-blur hover:text-label md:inline-flex">
        <PanelLeftOpen aria-hidden className="size-5" />
      </button>

      <div className="flex min-w-0 flex-1 flex-col">
        {isDemoMode && (
          <div role="note" className="bg-[color-mix(in_srgb,var(--sd-orange)_16%,transparent)] px-4 py-1.5 text-center text-xs font-medium text-label">
            Demo · synthetic data stored only in this browser · nothing is sent anywhere
          </div>
        )}
        <main id="main" className="flex-1 pb-[calc(88px+env(safe-area-inset-bottom))] md:pb-10">{children}</main>
      </div>

      {/* Phone: floating Add + bottom tab bar */}
      {!adding && (
        <Link
          href="/add"
          aria-label="Add transaction"
          className="fixed bottom-[calc(72px+env(safe-area-inset-bottom))] right-4 z-30 flex size-14 items-center justify-center rounded-full bg-[var(--sd-accent-fill)] text-white shadow-[0_6px_20px_rgba(13,115,217,0.35)] md:hidden"
        >
          <Plus aria-hidden className="size-7" />
        </Link>
      )}
      <nav aria-label="Main" className="fixed inset-x-0 bottom-0 z-20 border-t border-separator bg-card/85 pb-safe backdrop-blur-xl md:hidden">
        <ul className="grid grid-cols-5">
          {NAV.map(({ href, label, icon: Icon }) => {
            const active = isActive(pathname, href);
            return (
              <li key={href}>
                <Link href={href} aria-current={active ? "page" : undefined}
                  className={cx("flex min-h-[56px] flex-col items-center justify-center gap-0.5 text-[10px] font-medium", active ? "text-[var(--sd-accent-text)]" : "text-label-2")}>
                  <Icon aria-hidden className="size-6" strokeWidth={active ? 2.3 : 1.8} />
                  {label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}

/**
 * Large iOS-style page title with optional subtitle and actions. Top spacing includes the safe area in one value: the
 * unlayered `.pt-safe` helper used to override `pt-5`/`md:pt-8`, leaving titles flush against the top edge.
 */
export function PageHeader({ title, subtitle, actions, back }: { title: string; subtitle?: ReactNode; actions?: ReactNode; back?: { href: string; label: string } }) {
  return (
    <header className="sd-page-header mx-auto flex w-full max-w-6xl items-end justify-between gap-3 px-4 pb-3 pt-[calc(1.5rem+env(safe-area-inset-top))] md:px-8 md:pt-[calc(2.25rem+env(safe-area-inset-top))]">
      <div className="min-w-0">
        {back && (
          <Link href={back.href} className="mb-1 inline-flex items-center gap-1 text-[15px] font-medium text-[var(--sd-accent-text)]">
            ‹ {back.label}
          </Link>
        )}
        {subtitle && <p className="text-sm font-medium text-label-2">{subtitle}</p>}
        <h1 className="truncate text-[30px] font-bold leading-tight tracking-tight md:text-[34px]">{title}</h1>
      </div>
      {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
    </header>
  );
}

export function Page({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cx("mx-auto w-full max-w-6xl px-4 md:px-8", className)}>{children}</div>;
}

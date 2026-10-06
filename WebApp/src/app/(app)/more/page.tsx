"use client";

import { BookOpen, ChevronRight, CloudDownload, Landmark, LogOut, Monitor, Moon, ShieldCheck, Sun, UserRound } from "lucide-react";
import { useEffect } from "react";
import { Page, PageHeader, SyncStatus } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { Card, Divider, IconTile, Row, SectionHeader, Segmented } from "@/components/ui/primitives";
import { APPEARANCE_KEY, saveAppearance, type Appearance } from "@/lib/theme";
import { useStored } from "@/lib/use-stored";

export default function MorePage() {
  const { source, signOut, live } = useData();
  const [appearance] = useStored<Appearance>("local", APPEARANCE_KEY, "system");
  useEffect(() => {
    if (appearance !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => saveAppearance("system");
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [appearance]);

  const rows = [
    { href: "/more/account", icon: UserRound, tint: "blue" as const, title: "Account", detail: source?.email ?? "Your SpenDrop account" },
    { href: "/more/accounts", icon: Landmark, tint: "blue" as const, title: "Accounts", detail: `${live.accounts.length} funding account${live.accounts.length === 1 ? "" : "s"} · recorded money in and out` },
    { href: "/more/import", icon: CloudDownload, tint: "teal" as const, title: "Bring in iPhone data", detail: "From your iPhone's cloud backup or a backup file" },
    { href: "/more/reference", icon: BookOpen, tint: "indigo" as const, title: "Categories & Payment Channels", detail: "What each one means" },
  ];
  return (
    <>
      <PageHeader title="More" />
      <Page className="flex max-w-3xl flex-col gap-5">
        <Card className="overflow-hidden p-0">
          {rows.map((r, i) => (
            <div key={r.href}>{i > 0 && <Divider inset={72} />}
              <Row href={r.href}>
                <IconTile icon={r.icon} tint={r.tint} size={36} />
                <span className="min-w-0 flex-1"><span className="block font-medium">{r.title}</span><span className="block truncate text-xs text-label-2">{r.detail}</span></span>
                <ChevronRight aria-hidden className="size-4 text-label-3" />
              </Row>
            </div>
          ))}
        </Card>
        <section aria-labelledby="appearance-heading">
          <SectionHeader id="appearance-heading">Appearance</SectionHeader>
          <Card>
            <Segmented label="Appearance" value={appearance} onChange={(a) => saveAppearance(a)}
              options={[{ id: "system", label: "System" }, { id: "light", label: "Light" }, { id: "dark", label: "Dark" }]} />
            <p className="mt-2 flex items-center gap-1.5 text-xs text-label-2">
              {appearance === "system" ? <Monitor aria-hidden className="size-3.5" /> : appearance === "dark" ? <Moon aria-hidden className="size-3.5" /> : <Sun aria-hidden className="size-3.5" />}
              Saved on this browser.
            </p>
          </Card>
        </section>
        <section aria-labelledby="sync-heading">
          <SectionHeader id="sync-heading">Sync</SectionHeader>
          <Card className="flex flex-col gap-2 text-sm">
            <SyncStatus />
            <p className="text-label-2">Your records are stored in your SpenDrop account and cached on this browser for speed. Changes made here are saved to the cloud straight away.</p>
            <p className="flex items-start gap-1.5 text-label-2"><ShieldCheck aria-hidden className="mt-0.5 size-4 shrink-0 text-green" /> Only you can read your data (enforced by the database, not just the app).</p>
          </Card>
        </section>
        <Card className="p-0">
          <Row onClick={signOut} className="text-red"><LogOut aria-hidden className="size-5" /> Sign Out</Row>
        </Card>
        <p className="text-center text-xs text-label-2">SpenDrop Web · same rules as SpenDrop for iPhone</p>
      </Page>
    </>
  );
}

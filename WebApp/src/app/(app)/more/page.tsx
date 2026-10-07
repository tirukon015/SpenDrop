"use client";

import { BookOpen, ChevronRight, CloudDownload, Images, Landmark, LogOut, Monitor, Moon, ShieldCheck, Sparkles, Sun, UserRound } from "lucide-react";
import { useEffect } from "react";
import { Page, PageHeader, SyncStatus } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { Card, Divider, IconTile, Row, SectionHeader, Segmented, Toggle } from "@/components/ui/primitives";
import { useAiSettings } from "@/lib/ai-settings";
import { APPEARANCE_KEY, saveAppearance, type Appearance } from "@/lib/theme";
import { useStored } from "@/lib/use-stored";

export default function MorePage() {
  const { source, signOut, live } = useData();
  const [appearance] = useStored<Appearance>("local", APPEARANCE_KEY, "system");
  const [ai, setAi] = useAiSettings();
  useEffect(() => {
    if (appearance !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => saveAppearance("system");
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [appearance]);

  const rows = [
    { href: "/ask", icon: Sparkles, tint: "indigo" as const, title: "Ask SpenDrop", detail: "Ask anything about your spending" },
    { href: "/more/account", icon: UserRound, tint: "blue" as const, title: "Account", detail: source?.email ?? "Your SpenDrop account" },
    { href: "/more/accounts", icon: Landmark, tint: "blue" as const, title: "Bank Accounts", detail: `${live.accounts.length} funding account${live.accounts.length === 1 ? "" : "s"} · recorded money in and out` },
    { href: "/add/bulk", icon: Images, tint: "indigo" as const, title: "Bulk Screenshot Import", detail: "Add many transactions from payment screenshots at once" },
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
        <section aria-labelledby="ai-heading">
          <SectionHeader id="ai-heading">SpenDrop AI</SectionHeader>
          <Card className="flex flex-col gap-3">
            <Toggle id="ai-floating" checked={ai.floatingAssistant} onChange={(v) => setAi({ floatingAssistant: v })}
              label="Floating AI Assistant" description="Show the SpenDrop AI robot as a shortcut to Ask SpenDrop." />
            <Divider />
            <Toggle id="ai-name" checked={ai.showMyName} onChange={(v) => setAi({ showMyName: v })}
              label="Show My Name" description="Use your first name in SpenDrop AI. Only changes what's shown on screen — it doesn't affect your sign-in or your data." />
            <p className="text-xs text-label-2">Saved on this browser.</p>
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

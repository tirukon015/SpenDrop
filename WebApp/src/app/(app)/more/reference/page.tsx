"use client";

import { Page, PageHeader } from "@/components/app-shell";
import { ACCOUNT_ICONS, CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { Card, Divider, IconTile, SectionHeader } from "@/components/ui/primitives";
import { ACCOUNT_TYPES, CATEGORIES, PAYMENT_CHANNELS } from "@/lib/domain/constants";

const CHANNEL_HELP: Record<string, string> = {
  APPLE_PAY: "Paid with Apple Pay (the card behind it is the funding account).",
  QR_PAYMENT: "A QR payment that isn't DuitNow or Touch 'n Go QR.",
  DUITNOW_QR: "Paid by scanning a DuitNow QR code.",
  TNG_QR: "Paid by scanning a Touch 'n Go QR code.",
  BANK_TRANSFER: "DuitNow Transfer, IBG, Instant Transfer, FPX, JomPAY…",
  ONLINE_BANKING: "Paid through online banking.",
  CARD: "Card purchase (debit or credit, contactless or chip).",
  E_WALLET: "Paid from an e-wallet without QR wording.",
  CASH: "Paid in cash.",
  OTHER: "Another channel, e.g. an online payment.",
  UNKNOWN: "The receipt doesn't say how it was paid. That's fine — SpenDrop never guesses.",
};

export default function ReferencePage() {
  return (
    <>
      <PageHeader title="Categories & Channels" back={{ href: "/more", label: "More" }} />
      <Page className="flex max-w-3xl flex-col gap-5">
        <Card className="text-[15px]">
          <p className="font-semibold">Funding account vs payment channel</p>
          <p className="mt-1 text-label-2"><strong className="text-label">Funding account</strong> is where the money came from — Maybank, CIMB, RHB, Wise, Touch &apos;n Go, Cash.</p>
          <p className="mt-1 text-label-2"><strong className="text-label">Payment channel</strong> is how the payment was made — Apple Pay, DuitNow QR, Card, Bank Transfer. Apple Pay and QR are never accounts.</p>
          <p className="mt-1 text-label-2">Your <strong className="text-label">SpenDrop account</strong> (your sign-in) is something else again.</p>
        </Card>
        <section aria-labelledby="channels-heading">
          <SectionHeader id="channels-heading">Payment channels</SectionHeader>
          <Card className="overflow-hidden p-0">
            {PAYMENT_CHANNELS.map((c, i) => (
              <div key={c.id}>{i > 0 && <Divider inset={64} />}
                <div className="flex items-center gap-3 px-4 py-2.5"><IconTile icon={CHANNEL_ICONS[c.id]} tint={c.tint} size={36} />
                  <div><p className="font-medium">{c.label}</p><p className="text-xs text-label-2">{CHANNEL_HELP[c.id]}</p></div></div>
              </div>
            ))}
          </Card>
        </section>
        <section aria-labelledby="categories-heading">
          <SectionHeader id="categories-heading">Categories</SectionHeader>
          <Card className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {CATEGORIES.map((c) => <div key={c.id} className="flex items-center gap-2.5"><IconTile icon={CATEGORY_ICONS[c.id]} tint={c.tint} size={36} /><span className="font-medium">{c.id}</span></div>)}
          </Card>
        </section>
        <section aria-labelledby="types-heading">
          <SectionHeader id="types-heading">Funding account types</SectionHeader>
          <Card className="grid grid-cols-2 gap-3">
            {ACCOUNT_TYPES.map((t) => <div key={t.id} className="flex items-center gap-2.5"><IconTile icon={ACCOUNT_ICONS[t.id]} tint="blue" size={36} /><span className="font-medium">{t.label}</span></div>)}
          </Card>
        </section>
      </Page>
    </>
  );
}

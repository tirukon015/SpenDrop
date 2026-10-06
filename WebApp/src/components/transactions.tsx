"use client";

import { Users } from "lucide-react";
import Link from "next/link";
import { CATEGORY_ICONS, CHANNEL_ICONS, movementIcon } from "@/components/icons";
import { IconTile, cx, tintText, tintVar } from "@/components/ui/primitives";
import { categoryTint, channelInfo, kindInfo } from "@/lib/domain/constants";
import { formatDate, formatTime } from "@/lib/domain/dates";
import { myShareMinor } from "@/lib/domain/ledger";
import { formatMoney } from "@/lib/domain/money";
import type { ActivityItem } from "@/lib/domain/activity";
import type { CategoryId, Expense, ExpenseShare, MoneyMovement, PaymentChannelId, Person } from "@/lib/domain/types";

export function CategoryBadge({ category }: { category: CategoryId }) {
  const Icon = CATEGORY_ICONS[category];
  return (
    <span className="inline-flex items-center gap-1 text-xs font-semibold" style={{ color: tintText(categoryTint(category)) }}>
      <Icon aria-hidden className="size-3.5" /> {category}
    </span>
  );
}

/** HOW it was paid. Unknown is shown as Unknown (never guessed). */
export function ChannelBadge({ channel, withLabel = true }: { channel: PaymentChannelId; withLabel?: boolean }) {
  const info = channelInfo(channel);
  const Icon = CHANNEL_ICONS[channel];
  return (
    <span className="inline-flex items-center gap-1 text-xs text-label-2">
      <Icon aria-hidden className="size-3.5" style={{ color: tintVar(info.tint) }} />
      {withLabel && info.label}
    </span>
  );
}

/** "Maybank • DuitNow QR": funding account (where from) and channel (how) are always shown separately. */
export function fundingAndChannel(e: Expense) {
  const funding = e.fundingAccount && e.fundingAccount !== "Unknown" ? e.fundingAccount : null;
  const channel = e.paymentChannel !== "UNKNOWN" ? channelInfo(e.paymentChannel).label : null;
  return [funding, channel].filter(Boolean).join(" • ") || "Unknown";
}

export function ExpenseRow({ expense, shares, people, compact }: { expense: Expense; shares: ExpenseShare[]; people: Map<string, Person>; compact?: boolean }) {
  const shared = shares.length > 0;
  const mine = myShareMinor(expense, shares);
  const payer = expense.payerId ? people.get(expense.payerId)?.name ?? expense.payerNameSnapshot : expense.payerNameSnapshot;
  const shown = expense.paidByMe ? expense.amountMinor : mine;
  return (
    <Link href={`/transactions/${expense.id}`} className="flex min-h-[64px] items-center gap-3 px-4 py-2.5 hover:bg-card-2 focus-visible:bg-card-2">
      <IconTile icon={CATEGORY_ICONS[expense.category]} tint={categoryTint(expense.category)} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-[15px] font-semibold">{expense.merchant}</span>
          {shared && (
            <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-[color-mix(in_srgb,var(--sd-blue)_14%,transparent)] px-1.5 text-[11px] font-semibold text-blue" aria-label={`Shared with ${shares.length - 1} ${shares.length - 1 === 1 ? "person" : "people"}`}>
              <Users aria-hidden className="size-3" /> {shares.length}
            </span>
          )}
        </div>
        <div className="flex min-w-0 items-center gap-1.5 text-xs">
          <span className="shrink-0 font-semibold" style={{ color: tintText(categoryTint(expense.category)) }}>{expense.category}</span>
          <span aria-hidden className="text-label-3">•</span>
          <span className="truncate text-label-2">{fundingAndChannel(expense)}</span>
        </div>
        {!compact && expense.notes && <p className="truncate text-xs text-label-2">{expense.notes}</p>}
      </div>
      <div className="flex shrink-0 flex-col items-end">
        <span className="tabular text-[15px] font-bold">−{formatMoney(shown, expense.currency)}</span>
        {shared ? (
          <span className="text-[11px] font-medium text-blue">{expense.paidByMe ? `You ${formatMoney(mine, expense.currency)}` : `Paid by ${payer ?? "someone"}`}</span>
        ) : null}
        <span className="text-[11px] text-label-2">{compact ? formatTime(expense.date) : formatDate(expense.date, { day: "numeric", month: "short" })}</span>
      </div>
    </Link>
  );
}

export function MovementRow({ movement, people, accounts }: { movement: MoneyMovement; people: Map<string, Person>; accounts: Map<string, { name: string }> }) {
  const info = kindInfo(movement.kind);
  const Icon = movementIcon(movement.kind);
  const person = movement.personId ? people.get(movement.personId)?.name ?? movement.personNameSnapshot : movement.personNameSnapshot;
  const from = movement.accountId ? accounts.get(movement.accountId)?.name : null;
  const to = movement.counterAccountId ? accounts.get(movement.counterAccountId)?.name : null;
  const detail = movement.kind === "ownTransfer" ? [from, to].filter(Boolean).join(" → ") : [person, from].filter(Boolean).join(" · ");
  const sign = info.direction === "in" ? "+" : info.direction === "out" ? "−" : "";
  const tint = info.direction === "in" ? "green" : info.direction === "out" ? "orange" : "teal";
  return (
    <Link href={`/transactions/m/${movement.id}`} className="flex min-h-[64px] items-center gap-3 px-4 py-2.5 hover:bg-card-2 focus-visible:bg-card-2">
      <IconTile icon={Icon} tint={tint} />
      <div className="min-w-0 flex-1">
        <span className="block truncate text-[15px] font-semibold">{movement.note || info.label}</span>
        <span className="block truncate text-xs text-label-2">{[movement.note ? info.label : null, detail].filter(Boolean).join(" · ") || info.label}</span>
      </div>
      <div className="flex shrink-0 flex-col items-end">
        <span className={cx("tabular text-[15px] font-bold", info.direction === "in" && "text-green")}>{sign}{formatMoney(movement.amountMinor, movement.currency)}</span>
        <span className="text-[11px] text-label-2">{formatDate(movement.date, { day: "numeric", month: "short" })}</span>
      </div>
    </Link>
  );
}

export function ActivityRow({ item, people, accounts, compact }: { item: ActivityItem; people: Map<string, Person>; accounts: Map<string, { name: string }>; compact?: boolean }) {
  return item.type === "expense"
    ? <ExpenseRow expense={item.expense} shares={item.shares} people={people} compact={compact} />
    : <MovementRow movement={item.movement} people={people} accounts={accounts} />;
}

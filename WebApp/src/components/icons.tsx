// One icon system (lucide outline icons, the closest web match to SF Symbols) mapped from the shared ids.
import {
  Apple, ArrowDownLeft, ArrowLeftRight, ArrowUpRight, Banknote, BookOpen, Car, CircleEllipsis, CircleHelp, CreditCard, Globe, HandCoins,
  Heart, Landmark, Plane, QrCode, Repeat, ScanQrCode, ShoppingBag, ShoppingCart, Smartphone, Tv, User, Utensils, Wallet, Zap,
  type LucideIcon,
} from "lucide-react";
import type { AccountType, CategoryId, MovementKind, PaymentChannelId } from "@/lib/domain/types";

export const CATEGORY_ICONS: Record<CategoryId, LucideIcon> = {
  Food: Utensils, Groceries: ShoppingCart, Transport: Car, Shopping: ShoppingBag, Bills: Zap, Entertainment: Tv, Education: BookOpen,
  Health: Heart, Travel: Plane, Personal: User, Subscription: Repeat, Other: CircleEllipsis,
};

export const CHANNEL_ICONS: Record<PaymentChannelId, LucideIcon> = {
  APPLE_PAY: Apple, QR_PAYMENT: QrCode, DUITNOW_QR: ScanQrCode, TNG_QR: QrCode, BANK_TRANSFER: ArrowLeftRight, ONLINE_BANKING: Globe,
  CARD: CreditCard, E_WALLET: Smartphone, CASH: Banknote, OTHER: CircleEllipsis, UNKNOWN: CircleHelp,
};

export const ACCOUNT_ICONS: Record<AccountType, LucideIcon> = { bank: Landmark, eWallet: Smartphone, cash: Banknote, other: Wallet };

export function movementIcon(kind: MovementKind): LucideIcon {
  if (kind === "ownTransfer") return ArrowLeftRight;
  if (kind === "loanGiven" || kind === "loanReceived" || kind === "repaymentMade" || kind === "repaymentReceived") return HandCoins;
  return ["income", "refund", "otherIn"].includes(kind) ? ArrowDownLeft : ArrowUpRight;
}

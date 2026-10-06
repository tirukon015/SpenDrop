// Platform constants. The source of truth is Common/Constants/*.json; tests/domain/common-contract.test.ts
// checks that these lists match it exactly, so iOS and Web never drift apart.
import type { AccountType, CategoryId, MovementDirection, MovementKind, PaymentChannelId, PaymentType, SplitMethod } from "./types";

/** Tint names map to the --sd-* colour tokens in globals.css (Apple system colours). */
export type Tint =
  | "blue" | "green" | "indigo" | "orange" | "pink" | "purple" | "red" | "teal" | "yellow" | "mint" | "cyan" | "gray" | "primary";

export const CATEGORIES: { id: CategoryId; tint: Tint }[] = [
  { id: "Food", tint: "orange" },
  { id: "Groceries", tint: "green" },
  { id: "Transport", tint: "blue" },
  { id: "Shopping", tint: "pink" },
  { id: "Bills", tint: "red" },
  { id: "Entertainment", tint: "purple" },
  { id: "Education", tint: "indigo" },
  { id: "Health", tint: "mint" },
  { id: "Travel", tint: "teal" },
  { id: "Personal", tint: "cyan" },
  { id: "Subscription", tint: "yellow" },
  { id: "Other", tint: "gray" },
];

export const PAYMENT_CHANNELS: { id: PaymentChannelId; label: string; tint: Tint }[] = [
  { id: "APPLE_PAY", label: "Apple Pay", tint: "primary" },
  { id: "QR_PAYMENT", label: "QR Payment", tint: "indigo" },
  { id: "DUITNOW_QR", label: "DuitNow QR", tint: "pink" },
  { id: "TNG_QR", label: "Touch 'n Go QR", tint: "blue" },
  { id: "BANK_TRANSFER", label: "Bank Transfer", tint: "teal" },
  { id: "ONLINE_BANKING", label: "Online Banking", tint: "cyan" },
  { id: "CARD", label: "Card", tint: "purple" },
  { id: "E_WALLET", label: "E-Wallet", tint: "blue" },
  { id: "CASH", label: "Cash", tint: "green" },
  { id: "OTHER", label: "Other", tint: "orange" },
  { id: "UNKNOWN", label: "Unknown", tint: "gray" },
];

export const MOVEMENT_KINDS: { id: MovementKind; label: string; direction: MovementDirection; personBalanceSign: -1 | 0 | 1 }[] = [
  { id: "income", label: "Income", direction: "in", personBalanceSign: 0 },
  { id: "loanReceived", label: "Loan received", direction: "in", personBalanceSign: -1 },
  { id: "repaymentReceived", label: "Repayment received", direction: "in", personBalanceSign: -1 },
  { id: "refund", label: "Refund", direction: "in", personBalanceSign: 0 },
  { id: "otherIn", label: "Other money in", direction: "in", personBalanceSign: 0 },
  { id: "loanGiven", label: "Loan given", direction: "out", personBalanceSign: 1 },
  { id: "repaymentMade", label: "Repayment made", direction: "out", personBalanceSign: 1 },
  { id: "otherOut", label: "Other money out", direction: "out", personBalanceSign: 0 },
  { id: "ownTransfer", label: "Own transfer", direction: "internal", personBalanceSign: 0 },
];

export const ACCOUNT_TYPES: { id: AccountType; label: string }[] = [
  { id: "bank", label: "Bank" },
  { id: "eWallet", label: "E-Wallet" },
  { id: "cash", label: "Cash" },
  { id: "other", label: "Other" },
];

export const COMMON_FUNDING_ACCOUNTS = ["Maybank", "CIMB", "RHB", "Public Bank", "Bank Islam", "Wise", "Touch 'n Go", "Cash", "Other"];

export const SPLIT_METHODS: { id: SplitMethod; label: string }[] = [
  { id: "equal", label: "Split Equally" },
  { id: "parts", label: "Parts" },
  { id: "amounts", label: "Custom Amount" },
];

export const PAYMENT_TYPES: PaymentType[] = ["Bank Account", "E-Wallet", "Payment ID", "Other"];

export const MAX_PARTS = 99;
export const DEFAULT_CURRENCY = "RM";

export const categoryTint = (id: CategoryId): Tint => CATEGORIES.find((c) => c.id === id)?.tint ?? "gray";
export const channelInfo = (id: PaymentChannelId) => PAYMENT_CHANNELS.find((c) => c.id === id) ?? PAYMENT_CHANNELS[PAYMENT_CHANNELS.length - 1];
export const kindInfo = (id: MovementKind) => MOVEMENT_KINDS.find((k) => k.id === id)!;
export const isCategory = (value: string): value is CategoryId => CATEGORIES.some((c) => c.id === value);
export const isChannel = (value: string): value is PaymentChannelId => PAYMENT_CHANNELS.some((c) => c.id === value);

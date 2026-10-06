// SpenDrop records as used by the Web App. They mirror the cloud tables (Supabase/supabase/migrations) and the
// iOS SwiftData models (Common/DataModels). Money is always integer minor units (sen). Dates are ISO strings.

export type ID = string;

export type CategoryId =
  | "Food" | "Groceries" | "Transport" | "Shopping" | "Bills" | "Entertainment"
  | "Education" | "Health" | "Travel" | "Personal" | "Subscription" | "Other";

export type PaymentChannelId =
  | "APPLE_PAY" | "QR_PAYMENT" | "DUITNOW_QR" | "TNG_QR" | "BANK_TRANSFER" | "ONLINE_BANKING"
  | "CARD" | "E_WALLET" | "CASH" | "OTHER" | "UNKNOWN";

export type MovementKind =
  | "income" | "loanReceived" | "repaymentReceived" | "refund" | "otherIn"
  | "loanGiven" | "repaymentMade" | "otherOut" | "ownTransfer";

export type MovementDirection = "in" | "out" | "internal";
export type AccountType = "bank" | "eWallet" | "cash" | "other";
export type SplitMethod = "equal" | "parts" | "amounts";
export type PaymentType = "Bank Account" | "E-Wallet" | "Payment ID" | "Other";

/** Sync metadata shared by every record (Docs/Sync-Architecture.md). */
export interface SyncMeta {
  id: ID;
  createdAt: string;
  /** Last edit time on the device that made it (last-writer-wins). */
  updatedAt: string;
  /** Tombstone: set instead of deleting so other devices learn about the deletion. */
  deletedAt: string | null;
}

/** A funding account: WHERE the money came from (Maybank, Touch 'n Go, Cash…). Not a payment channel. */
export interface Account extends SyncMeta {
  name: string;
  type: AccountType;
  currency: string;
  icon: string | null;
  isArchived: boolean;
  sortIndex: number;
}

/** A PayBook person. */
export interface Person extends SyncMeta {
  name: string;
  notes: string | null;
  isFrequent: boolean;
  isArchived: boolean;
}

export interface PersonPaymentMethod extends SyncMeta {
  personId: ID;
  paymentType: PaymentType;
  provider: string;
  customProviderName: string | null;
  accountIdentifier: string;
  label: string | null;
  notes: string | null;
}

export interface Expense extends SyncMeta {
  amountMinor: number;
  currency: string;
  merchant: string;
  category: CategoryId;
  /** HOW it was paid. UNKNOWN is valid and explicit. */
  paymentChannel: PaymentChannelId;
  /** WHERE the money came from (text, like iOS) … */
  fundingAccount: string;
  fundingInstrument: string | null;
  /** … optionally linked to an Account record. */
  accountId: ID | null;
  paymentSource: string | null;
  date: string;
  notes: string | null;
  transactionReference: string | null;
  sourceType: string;
  /** false = someone else paid (payerId). */
  paidByMe: boolean;
  payerId: ID | null;
  payerNameSnapshot: string | null;
  splitMethod: SplitMethod | null;
  receiptPath: string | null;
  isSampleData: boolean;
}

export interface ExpenseShare extends SyncMeta {
  expenseId: ID;
  personId: ID | null;
  isMe: boolean;
  nameSnapshot: string;
  amountMinor: number;
  parts: number | null;
  enteredMinor: number | null;
  sortIndex: number;
}

export interface MoneyMovement extends SyncMeta {
  kind: MovementKind;
  direction: MovementDirection;
  amountMinor: number;
  currency: string;
  date: string;
  personId: ID | null;
  personNameSnapshot: string | null;
  linkedExpenseId: ID | null;
  linkedExpenseSnapshot: string | null;
  accountId: ID | null;
  counterAccountId: ID | null;
  note: string | null;
  transactionReference: string | null;
  sourceType: string;
  paymentChannel: PaymentChannelId;
}

export type AllocationKind = "payment" | "assign" | "offset";

/** Which payment settled which debt (never changes the original expense/loan). */
export interface SettlementAllocation extends SyncMeta {
  groupId: ID;
  kind: AllocationKind;
  paymentId: ID | null;
  expenseId: ID | null;
  loanId: ID | null;
  personId: ID;
  /** +1 the person owes me, -1 I owe the person. */
  direction: 1 | -1;
  amountMinor: number;
  currency: string;
  date: string;
}

export interface ClassificationRule extends SyncMeta {
  merchantKey: string;
  category: CategoryId | null;
  suggestedType: string | null;
  accountId: ID | null;
  hitCount: number;
}

export interface ChannelRule extends SyncMeta {
  merchantKey: string;
  fundingKey: string;
  channel: PaymentChannelId;
  hitCount: number;
}

/** Everything the app works with, already filtered to non-deleted records where noted by callers. */
export interface Dataset {
  accounts: Account[];
  people: Person[];
  paymentMethods: PersonPaymentMethod[];
  expenses: Expense[];
  shares: ExpenseShare[];
  movements: MoneyMovement[];
  allocations: SettlementAllocation[];
  classificationRules: ClassificationRule[];
  channelRules: ChannelRule[];
}

export type TableName =
  | "accounts" | "people" | "person_payment_methods" | "expenses" | "expense_shares"
  | "money_movements" | "settlement_allocations" | "classification_rules" | "channel_rules";

export const emptyDataset = (): Dataset => ({
  accounts: [], people: [], paymentMethods: [], expenses: [], shares: [], movements: [], allocations: [],
  classificationRules: [], channelRules: [],
});

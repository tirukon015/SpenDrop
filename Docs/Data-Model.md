# SpenDrop data model

All clients store the same records. Field names: iOS (Swift) → cloud column (snake_case) → Web (camelCase, same as
cloud but camelCase). Machine-readable enums: `Common/Constants/*.json`. Money is **always integer minor units (sen)**.

## Common to every record (sync metadata)

| Field | Meaning |
|---|---|
| `id` (uuid) | Stable identity, created on the device that made the record. Never reused, never derived from content. iOS writes uppercase UUIDs; the cloud stores them lowercase (case-insensitive equal). |
| `user_id` | Owner (the SpenDrop login). Set by the database (`auth.uid()`); never sent by clients. |
| `created_at` | When the record was created. |
| `updated_at` | Last edit time on the editing device — used for last-writer-wins. |
| `deleted_at` | Tombstone. Deleting sets this; the row stays so other devices learn about the deletion. |
| `server_updated_at` | Set by the server on every write. The sync cursor. |

## Records

### accounts — funding accounts (iOS `Account`)
`name`, `type` (`bank` · `eWallet` · `cash` · `other`), `currency` (`RM`), `icon`, `is_archived`, `sort_index`.
Totals shown for an account are *recorded* in/out, never a bank balance.

### people — PayBook (iOS `PayBookProfile`)
`name`, `notes`, `is_frequent`, `is_archived`. Photos are device-only (not synced).

### person_payment_methods (iOS `PayBookPaymentMethod`)
`person_id`, `payment_type` (`Bank Account` · `E-Wallet` · `Payment ID` · `Other`), `provider`, `custom_provider_name`,
`account_identifier`, `label`, `notes`.

### expenses (iOS `Expense`)
| Cloud | iOS | Notes |
|---|---|---|
| `amount_minor` | `amount` (Double) → `Money.minorUnits(from:)` | > 0 |
| `currency` | `currency` | `RM` |
| `merchant` | `merchant` | |
| `category` | `categoryRaw` | `Common/Constants/categories.json` |
| `payment_channel` | `paymentChannelRaw` | `Common/Constants/payment-channels.json`; default `UNKNOWN` |
| `funding_account` | `fundingAccount` | text, e.g. "Maybank" (where the money came from) |
| `funding_instrument` | `fundingInstrument` | e.g. "Visa Debit" |
| `account_id` | `account` | optional link to `accounts` |
| `payment_source` | `paymentSourceRaw` | legacy iOS field, kept for fidelity |
| `date` | `date` | timestamptz |
| `notes`, `transaction_reference`, `source_type`, `is_sample_data` | same | |
| `paid_by_me`, `payer_id`, `payer_name_snapshot` | same | someone else paid → `payer_id` |
| `split_method` | `splitMethodRaw` | `equal` · `parts` · `amounts`; null = not split |
| `receipt_path` | — | Web receipts in the private `receipts` bucket. iOS screenshots stay on the device. |

### expense_shares (iOS `ExpenseShare`)
`expense_id`, `person_id` (null for Me), `is_me`, `name_snapshot`, `amount_minor` (≥ 0), `parts`, `entered_minor`,
`sort_index`. **Invariant:** the live shares of an expense add up exactly to its `amount_minor` (enforced by
`save_expense_with_shares`).

### money_movements (iOS `MoneyMovement`)
`kind` (`Common/Constants/money-movement-kinds.json`), `direction` (`in` · `out` · `internal`, must match the kind),
`amount_minor`, `currency`, `date`, `person_id`, `person_name_snapshot`, `linked_expense_id`, `linked_expense_snapshot`,
`account_id`, `counter_account_id` (own transfers), `note`, `transaction_reference`, `source_type`, `payment_channel`.

### settlement_allocations (iOS `SettlementAllocation`)
`group_id` (one settlement action = one Undo), `kind` (`payment` · `assign` · `offset`), `payment_id`, `expense_id`,
`loan_id`, `person_id`, `direction` (+1 they owe me / −1 I owe them), `amount_minor`, `currency`, `date`.
Settlements never modify the original expense or loan.

### classification_rules / channel_rules (iOS `ClassificationRule` / `ChannelRule`)
Learned corrections. Category per merchant key; channel per merchant key **and** funding key (never a global
"Touch 'n Go = DuitNow QR" rule). Keys are normalised merchant names, never transaction data.

## Derived values (never stored)

- **Spending** of an expense: full amount if I paid, my share if someone else paid.
- **Person balance**: `FinancialCalculator.personBalances` / `ledger.personBalances` — positive = they owe me.
- **Debts**: per transaction from shares/loans minus active allocations.
- **Cash flow**: money in − money out; own transfers excluded.

Rules and test vectors: `Common/BusinessRules/`.

## Not synced (device-only)

iOS screenshots/receipt images, PayBook photos, sample-data register, iOS-only learned state (Apple Pay automation).

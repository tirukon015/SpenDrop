# SpenDrop iOS — Code Audit (feature inventory)

Audit date: 2026-10-07 · Branch: `feature/multi-platform-webapp` · App version in project: 1.4.0 (`MARKETING_VERSION`), schema V5, backup format v4.

This document reflects only what was found by reading the source. It was written as groundwork for a multi-platform (web) version. Paths are relative to the repository root.

## Status tags

| Tag | Meaning |
|---|---|
| IMPLEMENTED | Present and wired into the UI. Confirmed by reading the code. |
| PARTIALLY IMPLEMENTED | Exists, but some part is missing or limited (details given). |
| NOT IMPLEMENTED | Not in the code. |
| IOS-SPECIFIC | Relies on an Apple framework or OS feature. A web app needs another approach. |
| NEEDS WEB EQUIVALENT | Pure product or business logic that the web app must re-implement, ideally in shared code. |
| NEEDS SHARED BACKEND SUPPORT | Needs server tables, APIs or storage that do not exist yet. |
| NEEDS FUTURE PLATFORM ADAPTATION | Works on iOS but its design assumes one device. It must be revisited for multi-device use. |
| KNOWN BUG / GAP | Defect, inconsistency or risk found during the audit. |

## 1. Architecture summary

| Aspect | Finding | Evidence |
|---|---|---|
| Persistence | SwiftData, **local-first**. The store is in the App Group `group.com.spendrop.shared` and is shared with the Share Extension. | `iOS/SpenDrop/Data/ExpenseDataContainer.swift` |
| Safe mode | If the store cannot be opened, the app runs on an in-memory store and the file is left on disk. The user can choose "Move Aside & Use Backup". Before a schema change, a pre-upgrade snapshot is taken (3 are kept). | `ExpenseDataContainer.swift`, `iOS/SpenDrop/App/SpenDropApp.swift` |
| Money representation | `Expense.amount` is a `Double`. Every new calculation uses integer sen through `Money.minorUnits(from:)`, which rounds half away from zero. `MoneyMovement.amountMinor` and `ExpenseShare.amountMinor` are `Int`. | `iOS/SpenDrop/Data/Money.swift`, `Data/FinancialCalculator.swift` |
| Currency | The default everywhere is `"RM"`. Totals never add different currencies together. In practice the UI only aggregates RM. | `FinancialCalculator.summary(... currency: "RM")` |
| Cloud | **Backup only.** JSON snapshots go to a private Supabase Storage bucket `backups`, plus one metadata row per snapshot in `public.backups`. There is **no live two-way sync and there are no per-record cloud tables.** | `Data/Cloud/CloudBackupService.swift`, `Supabase/supabase/migrations/20260929000000_spendrop_cloud_backup.sql` |
| Account requirement | None. The app is fully usable when signed out. Signing in or out never touches local data. | `Data/Cloud/AuthService.swift` (doc comments + `clearSession`), `Views/Account/AccountView.swift` |
| Tests | In-app test runner driven by launch arguments (21 suites + an isolation check), plus 16 XCUITests. | `Data/Tests/TestKit.swift`, `iOS/SpenDropUITests/SpenDropUITests.swift` |

## 2. Navigation

| Feature | Status | Evidence / notes |
|---|---|---|
| 5 tabs: Home, Transactions, PayBook, Breakdown, More | IMPLEMENTED · NEEDS WEB EQUIVALENT | `Views/MainTabView.swift`: `DashboardView` "Home" `house.fill` (tag 0), `ExpensesView` "Transactions" `list.bullet.rectangle.portrait.fill` (1), `PayBookView` "PayBook" `person.crop.rectangle.stack.fill` (2), `AnalyticsView` "Breakdown" `chart.bar.xaxis` (3), `MoreView` "More" `ellipsis.circle.fill` (4). `.tint(.blue)`. |
| More hub: Account, Accounts, Settings | IMPLEMENTED | `Views/More/MoreView.swift` |
| `--tab N` launch argument | IMPLEMENTED (test hook) | `MainTabView.swift` |
| PayBook title spelling | KNOWN BUG / GAP | The tab label is "PayBook" but `navigationTitle("Paybook")` (`Views/PayBook/PayBookView.swift:112`). |

## 3. Authentication (Supabase)

All auth calls are made directly against Supabase's GoTrue HTTP API with `URLSession`. The Supabase Swift SDK is not used. Config is loaded from `Resources/CloudConfig/SupabaseConfig.plist` (git-ignored; this audit did not open it). If the file is missing, the state is `.notConfigured` and cloud features are hidden.

| Feature | Status | Evidence / notes |
|---|---|---|
| Email/password sign-up with PKCE | IMPLEMENTED · NEEDS WEB EQUIVALENT | `AuthService.signUp`: POST `/auth/v1/signup?redirect_to=spendrop://auth-callback` with `code_challenge` (S256). The verifier is stored in the Keychain as `pendingEmailFlow`. Returns `.signedIn` or `.confirmationRequired`. |
| Email verification deep link `spendrop://auth-callback` | IMPLEMENTED · IOS-SPECIFIC (custom URL scheme) | `AuthService.handleAuthCallback`. Handles `?code=` (PKCE exchange via `/auth/v1/token?grant_type=pkce`), implicit `#access_token` links, and `error_code`. A link opened without a stored verifier gives `.verifiedSignInNeeded`. The URL scheme is registered in `Resources/Info.plist`. The handler is the `AuthLinkHandling` modifier in `Views/Account/AccountView.swift`. |
| Email/password sign-in | IMPLEMENTED | `signIn` → `/auth/v1/token?grant_type=password` |
| Password reset (PKCE) + set new password | IMPLEMENTED | `requestPasswordReset` (`/auth/v1/recover`), then `awaitingNewPassword` opens a `NewPasswordView` sheet, then `updatePassword` (PUT `/auth/v1/user`) and a forced sign-out. |
| Client-side validation | IMPLEMENTED | `AuthValidation`: at least 8 characters, with upper case, lower case and a digit; basic email check. |
| Google sign-in (OAuth + PKCE) | IMPLEMENTED · IOS-SPECIFIC (`ASWebAuthenticationSession`) | `signInWithGoogle` / `googleAuthorizeURL` (`/auth/v1/authorize?provider=google&redirect_to=spendrop://auth-callback`), then `completeGoogleSignIn`. |
| Session storage | IMPLEMENTED · IOS-SPECIFIC | `KeychainStore` (`Data/Cloud/CloudCore.swift`), service `com.spendrop.SpenDrop.auth`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Never stored in SwiftData or UserDefaults. |
| Session refresh | IMPLEMENTED | `validAccessToken()` refreshes when less than 60 s remain. Offline keeps the session. A 4xx refresh failure clears the session (sessionExpired). Also called at launch through `refreshSessionIfNeeded()`. |
| Sign out | IMPLEMENTED | POST `/auth/v1/logout` (best effort), then the Keychain entry is cleared. Local data is untouched. |
| Delete account | IMPLEMENTED · NEEDS SHARED BACKEND SUPPORT (already exists) | `deleteAccount` deletes all cloud backups first (`CloudBackupService.deleteAllCloudData`), then calls RPC `/rest/v1/rpc/delete_my_account` (a SECURITY DEFINER function in the migration). Local data is kept. |
| Local-first (fully usable signed out) | IMPLEMENTED | `MoreView` shows "Optional sign-in for cloud backup". The no-config state says everything works without an account. |
| Profile header in Settings | KNOWN BUG / GAP | `Views/Settings/SettingsView.swift:53-88` always shows the hard-coded developer name and email (`UserDataBackupService.defaultAccountName/Email`) with a verified badge, whatever the auth state. |
| Setup hint path | KNOWN BUG / GAP (minor) | `AccountView.swift:31` mentions `docs/SUPABASE_SETUP.md`, but the folder is now `Docs/`. |

## 4. Transactions

### 4.1 Expense model (`iOS/SpenDrop/Models/Expense.swift`)

| Field group | Status | Notes |
|---|---|---|
| `amount: Double`, `currency` (default "RM"), `merchant` (empty becomes "Unknown"), `date` (date and time in one `Date`), `notes`, `categoryRaw` | IMPLEMENTED | `amountMinor`, `myShareMinor`, `spendingMinor`, `cashOutMinor` and `sharesMatchAmount` are extensions in `Data/FinancialCalculator.swift`. |
| Funding account: `fundingAccount: String` (default "Unknown") **and** `account: Account?` link | IMPLEMENTED | The text is a historical snapshot. The link is kept in step by `AccountLinker.relink` on every save. `effectiveFundingAccount` falls back to `underlyingBankRaw` / `paymentSourceRaw`. |
| `paymentChannelRaw` (default `UNKNOWN`) | IMPLEMENTED | Kept separate from funding. See §5. |
| Legacy `paymentSourceRaw`, `underlyingBankRaw`, `paymentMethodRaw`, `fundingInstrument` | IMPLEMENTED (legacy) | `PaymentSource` enum (`Models/PaymentSource.swift`) is used for logos and derivation. |
| `transactionReference`, `externalTransactionId`, `matchingStatusRaw` ("UNMATCHED"/"MATCHED"/"RECONCILED"), `matchingConfidence` | IMPLEMENTED | Used for duplicate detection and reconciliation. |
| `imageRelativePath` (file name only; bytes are on disk) | IMPLEMENTED · IOS-SPECIFIC storage | See §10. |
| `sourceTypeRaw`: manual, screenshot, photo, receipt, shareExtension, appleWallet | IMPLEMENTED | `Models/ExpenseSourceType.swift` |
| `ocrText`, `confidence` | IMPLEMENTED | |
| `isSampleData` | IMPLEMENTED | Also tracked by `SampleDataRecord`. |
| Payer / split: `paidByMe` (default true), `payer: PayBookProfile?`, `payerNameSnapshot`, `splitMethodRaw` (nil = not shared), `shares: [ExpenseShare]` (cascade delete), `linkedMovements` (nullify) | IMPLEMENTED | See §7. |

### 4.2 Money movements (`Models/MoneyMovement.swift`)

`MoneyMovementKind` (raw value equals the case name) and its direction:

| Kind | Raw | Direction (`MoneyDirection` raw) | `personBalanceSign` |
|---|---|---|---|
| income | `income` | moneyIn (`in`) | 0 |
| loanReceived | `loanReceived` | in | −1 |
| repaymentReceived | `repaymentReceived` | in | −1 |
| refund | `refund` | in | 0 |
| otherIn | `otherIn` | in | 0 |
| loanGiven | `loanGiven` | moneyOut (`out`) | +1 |
| repaymentMade | `repaymentMade` | out | +1 |
| otherOut | `otherOut` | out | 0 |
| ownTransfer | `ownTransfer` | internal (`internal`) | 0 |

| Feature | Status | Notes |
|---|---|---|
| Money In / Money Out / Transfer entry | IMPLEMENTED · NEEDS WEB EQUIVALENT | `AddExpenseView` has a record-type switch (`TransactionEntryType`: expense, moneyIn, moneyOut, transfer) and uses `MoneyMovementFormView` (`Views/Money/`). Validation is in `MoneyMovementDraft` (`Data/MoneyMovementDraft.swift`). |
| Validation | IMPLEMENTED | Amount must be > 0. A person is required for loan and repayment kinds. Own transfers need two different accounts. |
| Refund linked to original expense | IMPLEMENTED | `linkedExpense` + `linkedExpenseSnapshot`. The original expense is not changed. Net spending = spending − refunds. |
| Scanned screenshot saved as a movement | IMPLEMENTED | `MoneyMovementDraft.fromParsed`; `DirectionDetector` suggests the kind. |

### 4.3 Add / edit / delete, timeline, search, filter, sort

| Feature | Status | Evidence / notes |
|---|---|---|
| Add expense (manual, quick cash, scan from Photos) | IMPLEMENTED | `Views/AddExpense/AddExpenseView.swift`, `Views/Dashboard/Components/QuickCashButton.swift` |
| Edit expense | IMPLEMENTED | `Views/Expenses/EditExpenseView.swift`. On save it relinks the account, learns category and channel, and re-applies or removes the split. |
| Delete expense | IMPLEMENTED · KNOWN BUG / GAP | `ExpenseDetailView.swift:202`, `ExpensesView.swift:411`. The screenshot file is **not** deleted, so files are orphaned. Linked movements are kept (nullify). |
| Expense detail | IMPLEMENTED | `Views/Expenses/ExpenseDetailView.swift`: split editor, debts and settlements. |
| Unified timeline (expenses + movements) | IMPLEMENTED | `Data/ActivityFeed.swift`. `ActivityFilter`: all, expenses, moneyIn, moneyOut, shared, transfers. Items are de-duplicated by id. |
| Search | IMPLEMENTED | `.searchable` "Search merchant, amount, category...". Expenses match on merchant, category, funding, channel, notes or amount (`%.2f`). Movements match on kind, note, person, accounts or amount. |
| Filters | IMPLEMENTED | `Data/TransactionFilterEngine.swift` (shared singleton). `QuickDateFilter`: Today, Yesterday, Last 3/7/30 Days, This/Last Week, This/Last Month, Custom Range. Multi-select categories, payment channels and funding accounts (OR within a dimension, AND across). An active category filter hides movements. |
| Sort | PARTIALLY IMPLEMENTED | Newest First / Oldest First only (`ExpensesView.ExpenseSortOrder`). No sorting by amount or merchant. |
| Grouping by day | IMPLEMENTED | `ExpensesView.groupedItems` |

## 5. Funding accounts vs payment channels (separate concepts)

**Funding account** = where the money came from (Maybank, Touch 'n Go balance, Cash). **Payment channel** = how the payment was made (DuitNow QR, card, Apple Pay). The code keeps them apart on purpose. A bank or wallet name is never treated as channel evidence (`PaymentChannel.suggest`), and channel names are never funding accounts (`AccountLinker.ignoredKeys` excludes all channel display names except Cash and E-Wallet).

| Feature | Status | Evidence / notes |
|---|---|---|
| `Account` model (no balance by design) | IMPLEMENTED | `Models/Account.swift`. `AccountType`: `bank`, `eWallet`, `cash`, `other`. |
| Auto-creation and linking from `fundingAccount` text | IMPLEMENTED | `Data/AccountLinker.swift`: `normalizedKey`, `inferredType`, `resolveAccount`, `relink`, `linkUnlinkedExpenses` (run at launch and in the V1→V2 migration). |
| Accounts screen: recorded in/out per account, archive, add/edit, "Not Linked" movements | IMPLEMENTED | `Views/Accounts/AccountsView.swift`, `FinancialCalculator.accountActivity`. Labelled "not your real bank balance". |
| `PaymentChannel` enum | IMPLEMENTED | `Models/PaymentChannel.swift`. Cases (raw): applePay `APPLE_PAY`, qrPayment `QR_PAYMENT`, bankTransfer `BANK_TRANSFER`, card `CARD`, cash `CASH`, duitNowQR `DUITNOW_QR`, onlineBanking `ONLINE_BANKING`, eWallet `E_WALLET`, other `OTHER`, unknown `UNKNOWN`, tngQR `TNG_QR`. |
| Evidence-first channel detection with confidence and reason | IMPLEMENTED · NEEDS WEB EQUIVALENT | `PaymentChannel.suggest(evidenceText:)` returns `ChannelSuggestion`. Unknown when the receipt has no wording ("Never guess"). |

## 6. Categories

| Feature | Status | Notes |
|---|---|---|
| `ExpenseCategory` (12 fixed cases, raw value is the display name) | IMPLEMENTED · NEEDS WEB EQUIVALENT | `Models/ExpenseCategory.swift` |
| Custom categories | NOT IMPLEMENTED | |

| Case | Raw | SF Symbol | Color |
|---|---|---|---|
| food | Food | `fork.knife` | orange |
| groceries | Groceries | `cart.fill` | green |
| transport | Transport | `car.fill` | blue |
| shopping | Shopping | `bag.fill` | pink |
| bills | Bills | `bolt.fill` | red |
| entertainment | Entertainment | `tv.fill` | purple |
| education | Education | `book.fill` | indigo |
| health | Health | `heart.fill` | mint |
| travel | Travel | `airplane` | teal |
| personal | Personal | `person.fill` | cyan |
| subscription | Subscription | `repeat.circle.fill` | yellow |
| other | Other | `ellipsis.circle.fill` | gray |

## 7. Expense splitting

| Feature | Status | Evidence / notes |
|---|---|---|
| Storage: `ExpenseShare` rows on one `Expense` (integer sen, exactly one `isMe`, sum equals amount) | IMPLEMENTED | `Models/ExpenseShare.swift` |
| Methods `equal` / `parts` (1–99) / `amounts` | IMPLEMENTED · NEEDS WEB EQUIVALENT | `Data/SplitCalculator.swift` |
| Purpose: `shared` / `paidFor` ("Paid for Someone": I paid for them, so my share is 0, or they paid for me, so only my share is stored) | IMPLEMENTED | `Data/SplitDraft.swift` (`Purpose`, `iPaidForOthers`, `paidForMe`) |
| Payer: Me or another PayBook person (`Expense.setPayer`) | IMPLEMENTED | |
| Auto Calculate (Amounts method; **per split, default ON**, never a saved preference) | IMPLEMENTED | `SplitDraft.autoCalculate = true`. When ON, typed amounts are kept and the remainder is shared equally among people with no typed amount. When OFF, typed amounts must add up exactly. |
| Fixed amounts (fixed + equal part of the remainder) | IMPLEMENTED (editor) · KNOWN BUG / GAP | `Participant.fixedMinor` is editor-only. It is **not persisted** on `ExpenseShare`. Re-opening (`SplitDraft(expense:)`) sets `autoCalculate = false` and loads the final amounts as typed amounts, so the "fixed" configuration is lost after saving. |
| Remainder / validation messages | IMPLEMENTED | `SplitDraft.problem(totalMinor:)`: fixed exceeds total, remainder unassigned, shares exceed total, missing amount, and others. |
| Rounding: largest remainder in integer sen; ties go to Me first **when I paid**, then list order | IMPLEMENTED | `SplitCalculator.largestRemainder`. Friends never owe the extra sen. |
| Same-as-last-time suggestion | IMPLEMENTED | `SplitDraft.lastTimeSuggestion` (prefers the same merchant, skips archived people) |
| Amount changed on a shared expense | IMPLEMENTED | `recalculateAfterAmountChange`: equal and parts are recalculated, amounts are flagged. Edit re-applies the draft. |
| Inline split UI | IMPLEMENTED | `InlineSplitSection` (`Views/Split/SplitEditorView.swift`) used in `AddExpenseView`, `EditExpenseView`, `Views/Review/ExpenseReviewView.swift`, and `ShareExtension/ShareExtensionView.swift`. The full-sheet `SplitEditorView` is used for Paid for Someone and from expense detail. |

## 8. PayBook (people, balances, settlements)

| Feature | Status | Evidence / notes |
|---|---|---|
| People (`PayBookProfile`: name, photo, notes, frequent, archived) | IMPLEMENTED | `Models/PayBookProfile.swift`, `Views/PayBook/*` |
| Payment methods (`PayBookPaymentMethod`: type Bank Account / E-Wallet / Payment ID / Other; provider list; identifier; label; notes; copy to clipboard) | IMPLEMENTED | `Models/PayBookPaymentMethod.swift`, `PayBookDetailView.swift` |
| Legacy `PayBookContact`, migrated to profile + method at launch | IMPLEMENTED (legacy) | `ExpenseDataContainer.migrateLegacyContactsIfNeeded` |
| Net balances per person per currency (**positive = they owe me**) | IMPLEMENTED · NEEDS WEB EQUIVALENT | `FinancialCalculator.personBalances`, `PersonLedger.balances`. Nothing is stored; balances are always derived. |
| Per-transaction debts (`Debt`, `DebtLedger`) | IMPLEMENTED | `Data/PersonLedger.swift` |
| Settlement actions: Mark Paid, Settle Selected, Different Amount (auto-allocate oldest first), Apply Credit, Settle All (credit, then offsets, then one payment), Undo per group | IMPLEMENTED | `SettlementService` (`markPaid`, `recordPayment`, `applyCredit`, `autoAllocate`, `settleAll`, `undo`) |
| `SettlementAllocation` (kinds `payment`/`assign`/`offset`, linked by id, not by relationship) | IMPLEMENTED | `Models/MoneyMovement.swift` |
| Filter All / They Owe Me / I Owe Them (default They Owe Me) | IMPLEMENTED | `PayBookBalanceFilter`, `PersonLedger.outstanding`, `PayBookView.swift:18` |
| Grouping Frequent / Other People / Archived; delete blocked while a balance is non-zero (archive offered) | IMPLEMENTED | `PayBookGrouping`, `PersonLedger.canDelete` |
| Settlement error feedback | KNOWN BUG / GAP | `PayBookDetailView.swift` calls `try? SettlementService.markPaid/settleAll/recordPayment`, so validation errors are silently ignored. |

## 9. Home dashboard and Breakdown (analytics)

| Feature | Status | Evidence / notes |
|---|---|---|
| Home: Today / This Week / This Month spending cards | IMPLEMENTED | `Views/Dashboard/DashboardView.swift` using `spendingAmount` (my share when someone else paid). |
| Home: "My share of N shared expenses this month" | IMPLEMENTED | Shown only if there are any. |
| Home: Cash Flow · This Month (Money In, Money Out, Net) | IMPLEMENTED | Shown only when movements exist this month. |
| Home: Balances (Owed to you, You owe; RM only) | IMPLEMENTED | `PersonLedger.summary` |
| Home: Today's Expenses list + Recent Activity, scan button, Quick Cash | IMPLEMENTED | |
| Breakdown modes Spending / Cash Flow (`@AppStorage("breakdown_mode")`) | IMPLEMENTED | `Views/Analytics/AnalyticsView.swift` |
| Spending: Total spent, Avg/day, Avg/transaction, period comparison, daily chart (7/30 days), category donut, by channel, by funding account (tap to multi-select filter), shared and refunds, top merchants, spending trend (Daily/Weekly/Monthly) | IMPLEMENTED | Swift Charts, `TransactionFilterEngine`, `Data/PeriodGrouping.swift` |
| Cash Flow: Money In, Money Out, Net Cash Flow, by type, cash-flow trend | IMPLEMENTED | `FinancialCalculator.summary` (own transfers excluded) |
| Multi-currency aggregation | PARTIALLY IMPLEMENTED · KNOWN BUG / GAP | Dashboard card totals sum `spendingAmount` across currencies with no currency filter. The Cash Flow and Balances cards use RM only. |

## 10. OCR, screenshots, PDF, Share Extension, duplicates

| Feature | Status | Evidence / notes |
|---|---|---|
| On-device OCR (Apple Vision `VNRecognizeTextRequest`, `.accurate`, languages en-US / ms-MY / zh-Hans, language correction) | IMPLEMENTED · IOS-SPECIFIC | `OCR/OCRService.swift` |
| Rule-based parsing: amount candidates, merchant, date/time, reference, status (completed / failed / balance-only) | IMPLEMENTED · NEEDS WEB EQUIVALENT (logic is portable; OCR engine is not) | `OCR/TransactionParser.swift`, `MonetaryCandidate.swift`, `ParsedTransaction.swift` |
| Merchant detection (about 55 known-merchant entries) | IMPLEMENTED | `OCR/MerchantDetector.swift` |
| Category detection with confidence and reason (review threshold 0.7) | IMPLEMENTED | `OCR/CategoryDetector.swift` (`CategorySuggestion`) |
| Provider / funding detection (`DetectedTransactionSource`: APPLE_WALLET, BANK_APP, PHYSICAL_RECEIPT, UNKNOWN) | IMPLEMENTED | `OCR/PaymentProviderDetector.swift` |
| Direction suggestion (refund, incoming, top-up as own transfer) | IMPLEMENTED | `OCR/DirectionDetector.swift` |
| Overall confidence High / Medium / Low; per-field confidence and reasons | IMPLEMENTED | `ParsingConfidence`, `categoryConfidence/Reason`, `channelConfidence/Reason`, `directionReason` |
| Screenshot storage (App Group folder `SpenDropReceipts`, only the relative path in SwiftData) | IMPLEMENTED · IOS-SPECIFIC | `OCR/ImageStorageService.swift` |
| HEIC optimisation (long edge ≤1800 px, floor 1440, target 150 KB, qualities 0.72→0.45; JPEG fallback `-opt.jpg`; files under 200 KB skipped; original deleted only after the copy is verified) | IMPLEMENTED · IOS-SPECIFIC | `ScreenshotOptimizer`, `ScreenshotStorageMigrator` (same file). Settings has "Optimize Existing Screenshots". |
| PDF import (up to 5 pages for text, up to 3 OCR'd pages) | PARTIALLY IMPLEMENTED · IOS-SPECIFIC (PDFKit) | `PDFReceiptImporter` lives in `OCR/OCRService.swift`. It is reached **only through the Share Extension** (`ShareExtension/ShareViewController.swift`); the main app has no "import PDF" entry. |
| Share Extension (image, PDF and text input → OCR → review → save into the shared App Group store, with inline split) | IMPLEMENTED · IOS-SPECIFIC | `ShareExtension/ShareViewController.swift`, `ShareExtensionView.swift` |
| Apple Pay Shortcuts automation ("Log Apple Pay Purchase" App Intent; repeat window 10 min) | IMPLEMENTED · IOS-SPECIFIC | `App/ApplePayIntent.swift`, `Data/ApplePayAutomation.swift` |
| Duplicate detection for imports. Strong: same reference (≥4 characters) and same amount within ±48 h. Weak (warning): same amount and merchant within 15 min with compatible channel and funding. Manual entries are never checked. | IMPLEMENTED · NEEDS WEB EQUIVALENT | `Data/DuplicateDetector.swift`, `Data/TransactionReconciliationEngine.swift`, `Data/MovementDuplicateDetector.swift` |
| Reconcile / merge into an existing expense | IMPLEMENTED | `TransactionReconciliationEngine.reconcile` (review screen, Share Extension) |

## 11. Learned classification

| Feature | Status | Evidence / notes |
|---|---|---|
| Category and type rule per merchant (`ClassificationRule`; key = recognised merchant name or normalised text; trusted after 2 consecutive confirmations; a correction resets the count to 1) | IMPLEMENTED · NEEDS WEB EQUIVALENT | `Data/TransactionClassifier.swift`, `Models/ClassificationRule.swift`. Priority: user choice, then trusted learned rule, then deterministic parser, then generic, then Other. |
| Channel rule per merchant **and** funding account (`ChannelRule`; used only when the receipt gives no channel; trusted after 2) | IMPLEMENTED | `ChannelLearning` in `TransactionClassifier.swift` |
| Learning call sites | IMPLEMENTED | Add, Edit, Review and Share Extension save paths call `TransactionClassifier.learn` and `ChannelLearning.learn`. |

## 12. Backup and restore

### 12.1 Local backup — IMPLEMENTED · IOS-SPECIFIC (file locations)

- `UserDataBackupService` (`Data/UserDataBackupService.swift`) writes `SpenDrop_AutoBackup.json` to Documents **and** to the App Group. It runs 2 s (debounced) after any `ModelContext.didSave`, and again when the app goes to the background.
- History folder `SpenDropBackupHistory/`: one copy per day (7 kept) and a "before-shrink" copy whenever records would disappear (5 kept).
- It is skipped in safe mode, for in-memory stores and in UI tests.
- Export JSON (share sheet), Import JSON, and "Restore from Local Backup". All of them merge by id and never delete. If a local record has a newer `updatedAt`, it is kept.
- Payload format **v4** (`BackupPayload.currentVersion = 4`, supported 1…4): `expenses` (with `shares`), `paybookProfiles` (with `paymentMethods`), `accounts`, `moneyMovements`, `classificationRules`, `settlementAllocations`, `sampleRecords`, `channelRules` (optional, added inside v4).

### 12.2 Cloud backup — IMPLEMENTED (BACKUP ONLY) · NEEDS SHARED BACKEND SUPPORT for anything beyond backup

| Aspect | Finding |
|---|---|
| Consent | The "Cloud Backup" switch is off by default and stored per user. Signing in alone never uploads anything. `enableCloudBackup()` runs the first backup at once and schedules the daily one. |
| Daily automatic backup | On by default once Cloud Backup is on. Default time 03:00 (`defaultDailyBackupMinutes = 180`, user-adjustable). `BGProcessingTask` `com.spendrop.SpenDrop.dailyBackup` (IOS-SPECIFIC), plus catch-up on app foreground and when the network returns. At most one automatic success per day. |
| Pipeline | Optimise screenshots → build payload (`UserDataBackupService.makePayload`) → upload to Storage `backups/<user id>/<device id>/<uuid>.json` (`x-upsert: false`) → insert a `public.backups` row → verify (row readable, downloaded bytes identical, decodes as a supported version) → record success → prune. A failed upload is deleted. |
| De-duplication | A SHA-256 content hash. An automatic backup with no changes counts as done without uploading. |
| Retention | 30 (default) or 90 days. Only **this device's** snapshots are pruned, and only after a verified upload. The newest is never pruned. |
| Restore | Lists the 30 most recent backups (all devices). The user picks a range: Everything, Last 7 / 30 days, Last 2 / 3 months, or Custom (`RestoreRange`; days counted back from the backup's export date). A plan preview is shown, then confirmation, then a **local safety copy**, then an id-based merge. Nothing is ever deleted. **There is no automatic restore:** `latestLocalBackup()` and the cloud restore are only run from explicit user actions. |
| Server side | `public.backups` (RLS: owner select/insert/delete, no update), private bucket `backups` limited to `application/json` (owner folder policies), `delete_my_account()` RPC. |
| **Not live sync** | There are no per-record tables, no change feed and no conflict resolution beyond merge-by-id on a manual restore. Two devices do not see each other's edits unless one restores the other's snapshot. |

### 12.3 What is NOT backed up (local or cloud) — KNOWN BUG / GAP

| Data | Evidence |
|---|---|
| Receipt screenshot / image files | Only `imageRelativePath` is in `ExpenseDTO`. The UI says so explicitly: "Receipt screenshots aren't part of backups" (`AccountView.swift:727`) and "the screenshots themselves are not uploaded" (`AccountView.swift:170`). |
| PayBook person photos (`PayBookProfile.photoData`) | `PayBookProfileDTO` has no photo field. |
| Legacy `PayBookContact` rows | Not in the payload (they are migrated to profiles at launch). |
| Settings / AppStorage (appearance, currency, analytics range, cloud settings) | UserDefaults only. |
| Raw `fundingAccount` text | `ExpenseDTO.fundingAccount` exports `effectiveFundingAccount` (a derived value), not the stored text. |

## 13. Sample data, settings, theme

| Feature | Status | Evidence / notes |
|---|---|---|
| Load / Remove Sample Data (with confirmation; registered by id in `SampleDataRecord`; names marked "(Sample)") | IMPLEMENTED | `Data/SampleData.swift`, `SettingsView.swift` |
| Appearance System / Light / Dark (`@AppStorage("user_appearance")`: `system`/`light`/`dark`) | IMPLEMENTED | `MainTabView.preferredColorScheme`, `SettingsView` |
| Default Currency picker (`app_currency`: RM, SGD, USD, EUR, GBP) | KNOWN BUG / GAP | The value is never read outside `SettingsView`, so it has no effect. All new records default to "RM". |
| Screenshot storage stats and optimisation | IMPLEMENTED | `SettingsView` |
| OCR and parser self-test | IMPLEMENTED | `Views/Settings/Components/ParserSelfTestView.swift` |
| "Clear All Expenses" | KNOWN BUG / GAP | `SettingsView.clearAll()` deletes only `Expense` rows. Movements, people, accounts, rules and settlements stay. Image files are not deleted. |
| About section | KNOWN BUG / GAP (minor) | The version string "1.4.0 (Shared Money & Cloud Backup)" and "Target Device iPhone 17 Pro Max" are hard-coded. |

## 14. Data safety and schema

| Item | Status | Notes |
|---|---|---|
| Versioned schemas V1–V5 | IMPLEMENTED | `Data/SchemaVersions.swift`. V1: Expense, PayBookProfile, PayBookPaymentMethod, PayBookContact (frozen copies). V2: + Account, ExpenseShare, MoneyMovement. V3: + ClassificationRule. V4: + SettlementAllocation, SampleDataRecord. V5: + ChannelRule. |
| Migration plan | IMPLEMENTED | V1→V2 is a custom stage (`AccountLinker.linkUnlinkedExpenses`). V2→V3, V3→V4 and V4→V5 are lightweight and only add tables. |
| Pre-upgrade snapshots, schema fingerprint, safe mode, legacy App Group store copy (`group.com.spenddrop.shared`) | IMPLEMENTED | `ExpenseDataContainer.swift` |

## 15. Tests

In-app suites (`AllTestSuites.suites` in `Data/Tests/TestKit.swift`, run with launch flags; `--run-all-tests` runs every suite):

| # | Suite | Flag |
|---|---|---|
| 1 | Existing (parser) | `--run-tests` |
| 2 | Data safety | `--run-data-safety-tests` |
| 3 | Phase 2 (financial) | `--run-financial-tests` |
| 4 | Phase 3 (accounts) | `--run-account-tests` |
| 5 | Phase 4 (splits) | `--run-split-tests` |
| 6 | Debts & settlements | `--run-debt-tests` |
| 7 | Split transaction | `--run-split-transaction-tests` |
| 8 | Auto Calculate & fixed | `--run-auto-calculate-tests` |
| 9 | Sample data | `--run-sample-data-tests` |
| 10 | PayBook filter | `--run-paybook-filter-tests` |
| 11 | Phase 5 (people) | `--run-people-tests` |
| 12 | Phase 6 (timeline) | `--run-timeline-tests` |
| 13 | Phase 7 | `--run-phase7-tests` |
| 14 | Phase 8 (hardening) | `--run-hardening-tests` |
| 15 | Authentication | `--run-auth-tests` |
| 16 | Cloud Backup | `--run-cloud-tests` |
| 17 | Screenshot storage | `--run-screenshot-tests` |
| 18 | PDF import | `--run-pdf-import-tests` |
| 19 | Classifier | `--run-classifier-tests` |
| 20 | Restore ranges | `--run-restore-tests` |
| 21 | Daily backup | `--run-daily-backup-tests` |
| 22 | Test isolation (must stay last; checks the real DB was not touched) | `--run-all-tests` |

UI tests: **16** XCUITest methods in `iOS/SpenDropUITests/SpenDropUITests.swift` (test01–test16: five tabs, add expense, split balance, accounts and transfer, home/breakdown cash flow, local-first account screen, signed-in account screen, email links, email sign-in/create/forgot, restore range, paid-for-someone + mark paid, sample data confirmation, inline custom split must add up, share review split before first save, share review equal split, fixed amount + per-transaction Auto Calculate). They run with `--ui-testing`, which uses a temporary store, a memory Keychain and an offline transport.

## 16. Web / multi-platform readiness summary

| Area | Tags |
|---|---|
| Financial core (Money, FinancialCalculator, SplitCalculator, SplitDraft, PersonLedger / DebtLedger / SettlementService, ActivityFeed, TransactionFilterEngine, PeriodGrouping, classifiers, duplicate rules) | NEEDS WEB EQUIVALENT. Pure logic; port it into a shared module and reuse the in-app test cases as fixtures. |
| Persistence (SwiftData, App Group) | IOS-SPECIFIC · NEEDS SHARED BACKEND SUPPORT (the web needs its own store: IndexedDB locally, and/or per-record server tables). |
| Cloud | NEEDS SHARED BACKEND SUPPORT. Today it is snapshot backup only; real cross-device use needs per-record tables, RLS, `updated_at` conflict rules and tombstones for deletes. |
| Auth | NEEDS WEB EQUIVALENT (supabase-js with PKCE; redirect to a web URL instead of `spendrop://`). |
| OCR / Share Extension / Apple Pay intent / BGTask / Keychain / HEIC | IOS-SPECIFIC. The web needs alternatives (upload + server or WASM OCR, Web Share Target, scheduled server jobs, cookie sessions). |
| Screenshots | NEEDS SHARED BACKEND SUPPORT if images must exist on more than one device (they are not in backups today). |
| Single-device assumptions (device-scoped pruning, merge-only restore, no deletes propagated) | NEEDS FUTURE PLATFORM ADAPTATION |

## 17. Known gaps / bugs (consolidated)

1. **Fixed-amount configuration is not persisted.** `SplitDraft.Participant.fixedMinor` is editor-only; `ExpenseShare` has no field for it. After saving, re-opening the split shows plain typed amounts with Auto Calculate OFF (`SplitDraft.init?(expense:)`).
2. **`iOS/scripts/generate_xcodeproj.py` is out of date and must not be re-run.** The checked-in `project.pbxproj` has since been re-saved by Xcode and has drifted (`Docs/SPENDROP_DOCUMENTATION.md` around line 738 notes this). Regenerating could drop build settings or target membership added by hand.
3. **Hard-coded personal data in the app.** `UserDataBackupService.defaultAccountName`/`defaultAccountEmail` appear in the Settings "Account" header for every user and are written into every backup's `accountName`. About 450 lines of a hard-coded personal dataset (`restoreScreenshotExpenses`, `restorePayBookProfiles`) are seeded into the SwiftUI preview container and with the `--restore-user-data` launch argument. This should be removed or anonymised before any multi-user or web release.
4. **Screenshots and person photos are not backed up**, locally or in the cloud. A restore on a new device gives expenses whose `imageRelativePath` points to nothing.
5. **Deleting an expense leaves its screenshot file on disk** (orphaned files). "Clear All Expenses" has the same problem.
6. **"Clear All Expenses" only deletes expenses.** Movements, people, accounts, settlements and rules remain, which can leave settlements pointing at deleted debts (these are ignored by the calculations).
7. **Default Currency setting has no effect** (`app_currency` is never read).
8. **Dashboard spending cards mix currencies.** Today, Week and Month sum `spendingAmount` across all currencies, while Cash Flow and Balances are RM-only.
9. **Settlement errors are swallowed** (`try?` in `PayBookDetailView`), so the user gets no message if validation fails.
10. **Cloud restore list** shows only the latest 30 backups across all devices. Pruning is per device, so another device's old snapshots are only pruned by that device.
11. **Minor inconsistencies:** "Paybook" vs "PayBook" titles; a stale `docs/` path in `AccountView`; About shows a hard-coded version and device; the `Color.accentColor` asset (#0D73D9 light / #3399F2 dark) and `.tint(.blue)` are both used for accents.
12. **Sort** is limited to date (newest or oldest).
13. `ExpenseDTO.fundingAccount` exports the derived `effectiveFundingAccount`, not the stored raw text, so a round-trip can change "Unknown" into a bank name taken from legacy fields.

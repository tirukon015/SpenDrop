# SpenDrop Android — Architecture

## Principles

- **One product, same data.** Records have the same meaning, ids (UUID), money (integer sen) and raw values (`"DUITNOW_QR"`, `"Food"`, `"loanGiven"`…) as iOS and the cloud schema in `Supabase/supabase/migrations/`.
- **Local-first, like iOS.** The phone's database is the source of truth. The app is fully usable signed out. Signing in never replaces or deletes local data.
- **Same rules, ported, not reinterpreted.** All business logic was ported from the iOS sources into a pure Kotlin module and pinned by the iOS test cases plus `Common/BusinessRules` vectors.
- **Funding account ≠ payment channel.** `Expense.fundingAccount` / `accountId` = WHERE the money came from (Maybank, Touch 'n Go, Cash). `Expense.paymentChannelRaw` = HOW it was paid (Apple Pay, DuitNow QR, Card…). Separate fields, separate pickers, separate analytics.

## Modules

```
Android/
├── core/   Pure Kotlin/JVM — no Android. Models + every business rule. 277 unit tests.
└── app/    Android: Room, Compose UI, auth/HTTP, OCR, PDF, share target, WorkManager.
```

### `:core` packages

| Package | Ported from (iOS) | What |
|---|---|---|
| `model` | `Models/*.swift` | `Expense`, `ExpenseShare`, `Account`, `Person`, `PersonPaymentMethod`, `MoneyMovement`, `SettlementAllocation`, `ClassificationRule`, `ChannelRule`, enums with iOS raw values, `FinanceSnapshot`. Ids are lower-case UUID strings, times epoch millis, money `Long` sen, `deletedAt` tombstones. |
| `Money` | `Data/Money.swift` | Text/Double ↔ sen (half away from zero), `"RM 1,234.50"` formatting. |
| `finance` | `FinancialCalculator.swift` | my share, spending, cash out, summaries, account activity, person balances. |
| `split` | `SplitCalculator.swift`, `SplitDraft.swift` | Equal / parts / amounts, largest-remainder rounding (extra sen to Me when I paid), Auto Calculate (default ON per split), fixed amounts, remaining amount, iOS problem messages, paid-for-someone, payer, last-time suggestion, re-apply after amount change. |
| `ledger` | `PersonLedger.swift`, `MoneyMovementDraft.swift` | Debts per transaction, balances, PayBook filters/grouping, settlements (mark paid, record payment with auto/manual allocation, apply credit, settle all with offsets, undo), money-movement validation. |
| `insights` | `TransactionFilterEngine.swift`, `ActivityFeed.swift`, `PeriodGrouping.swift`, Analytics/Dashboard views | Date filters (Today … Custom), multi-select filters, search, timeline, Home cards, Breakdown Spending / Cash Flow, trends. |
| `accounts` | `AccountLinker.swift` | Funding-account keys, auto-create/relink, form validation. |
| `duplicates` | `DuplicateDetector`, `TransactionReconciliationEngine`, `MovementDuplicateDetector` | Strong (same reference ±48 h) / weak (amount + merchant within 15 min) checks for imports; reconcile/merge. |
| `parser` | `OCR/*.swift` | `TransactionParser` (amount candidates, merchant, date, reference, status), merchant/provider/category/direction/channel detectors, PDF text decision, in-app self-test. |
| `classify` | `TransactionClassifier.swift` | Learned category rules and channel rules (trusted after 2 confirmations). |
| `backup` | `UserDataBackupService.swift` | iOS backup JSON v1–v4 codec (byte-compatible dates/keys), import merge, restore ranges and plans. |
| `cloud` | `CloudBackupService.swift`, migrations | Cloud-backup protocol (paths, rows, verify, prune, hash, daily schedule), plus row mappers and LWW merge for the future per-record sync tables. |
| `sample` | `SampleData.swift` | Sample data set and exact removal. |

### `:app` layers

```
Compose screens (ui/*)  ──>  ViewModels / screen state (EditorViewModel, ImportFlowViewModel, remember{} over snapshot)
        │                                   │
        ▼                                   ▼
FinanceRepository (data/)  ── Room (data/db) ── spendrop.db (app-private)
        │
        ├─ LocalBackup: SpenDrop_AutoBackup.json 2 s after changes + daily/before-shrink history
        ├─ CloudBackupService (cloud/) ── SupabaseHttp (OkHttp) ── Supabase Storage `backups` + table `public.backups`
        └─ AuthService (cloud/) ── Supabase Auth (GoTrue) ── session in Android Keystore-encrypted prefs
```

- **Repository.** `FinanceRepository.snapshot: StateFlow<FinanceSnapshot?>` combines all live tables; screens compute everything from this immutable snapshot with `:core` functions. Writes go through `apply(Changes)` (atomic transaction) or `saveExpense(expense, shares)`, which replaces a split exactly like the cloud RPC `save_expense_with_shares` (unlisted shares tombstoned; shares must add up).
- **Deletes are tombstones** (`deletedAt`), so backups and future sync never resurrect or silently lose records. Undo after swipe-delete restores them.
- **Navigation.** Single `MainActivity` with type-safe Navigation Compose, five tabs as iOS (Home, Transactions, PayBook, Breakdown, More). Transactions and Breakdown share one filter state (iOS `TransactionFilterEngine.shared`).
- **DI.** `AppContainer` (manual, no framework). Tests build one with an in-memory database and an in-memory session store.

## Import pipeline

```
Share sheet (ShareActivity)        In-app (photo picker / file picker)
        │                                   │
        └──────────── Intake ───────────────┘   copy content:// to private cache now (URI grants are temporary)
                         │                      type detection, 40 MB limit, readable errors
            ┌────────────┼──────────────┐
          Image         PDF            Text
            │            │               │
  ImageTools (EXIF,   PdfBox text (≤5 pages) ──► PdfReceiptText.decide
  downscale ≤2400px)   └─ no text → PdfRenderer + OCR (≤3 pages)
            │            │               │
  ML Kit OCR (bundled, on device) ───────┤
            └──► OcrResult (normalised boxes, iOS reading order)
                         │
                  TransactionParser (ported)
                         │
        Review form (TransactionEditorScreen in review mode)
        banner: detected / failed / balance / possible duplicate
        possible amounts, funding account, channel (+ reason), category (+ confidence), split
                         │
        duplicate check → Add Anyway / Merge with Existing / Cancel
                         │
        save → Room (+ receipt JPEG ≤1800 px in app storage) → learn category/channel rules
```

- ML Kit's **bundled** Latin model runs without Google Play Services (Huawei and other devices without GMS work).
- Nothing is uploaded. Receipt images stay in app-private storage (iOS does the same; they are not in backups).
- Multiple shared files are reviewed one after another ("2 of 3"); each can be saved or skipped. The import view model survives rotation and never re-processes the same share.
- iOS has no multi-row bank-statement parser; "PDF import" on iOS (and Android) means one payment per PDF (e.g. a bank transfer receipt). This was reproduced, not extended.

## Authentication

`AuthService` calls Supabase Auth's HTTP API directly, exactly like iOS: email/password, sign-up with PKCE confirmation link, password reset (PKCE) → set new password, Google OAuth (PKCE) in a Custom Tab, refresh within 60 s of expiry (offline keeps the session; a revoked refresh token signs out of the cloud only), sign out, delete account (cloud backups first, then RPC `delete_my_account`). All links return to `spendrop://auth-callback`. Error messages match iOS wording.

## Cloud Backup (live today)

Same as iOS: off by default, explicit consent, first backup immediately, then optional daily backup at a chosen hour (WorkManager one-off job with network constraint, re-scheduled after each run; no permanent service), 30/90-day retention pruned for this device only after a verified upload. Restore lists the 30 newest backups from all the user's devices (iOS and Android), downloads, lets the user choose a range, previews counts, saves a local safety copy, then merges by id (nothing deleted; newer local edits win).

## Live sync with the Web (per-record cloud tables)

The Web session deployed `20261007000000_spendrop_cloud_records.sql` during the night: the live project now has `accounts`, `people`, `person_payment_methods`, `expenses`, `expense_shares`, `money_movements`, `settlement_allocations`, `classification_rules` and `channel_rules` with RLS, tombstones and `server_updated_at` cursors. The Web App uses them as its store. `SyncService` implements the protocol in `Docs/Sync-Architecture.md`, with the same calls as the Web client:

- **Opt-in per account:** More → Account → "Sync with SpenDrop Cloud". The first sync uploads this phone's records once (ids kept, so nothing is duplicated) and downloads the account's records.
- **Two accounts are never mixed.** A phone whose data was synced with account A refuses to sync with account B, unless the user chooses "Start Fresh", which erases the local copy and downloads B.
- **Pull:** per table, `GET rest/v1/<table>?order=server_updated_at.asc,id.asc&limit=1000&server_updated_at=gt.<cursor>`. Keyset pages, with rows sharing the boundary timestamp fetched together. Rows are merged with last-writer-wins on `updated_at`, tombstones included (`SyncMerge`). Cursors are saved only after the rows are written. A learned rule that already exists under another id for the same key is replaced by the cloud one (unique key).
- **Push:** records changed since the last push (`updatedAt` watermark), in foreign-key order.
  - Upsert on `id` (`Prefer: resolution=merge-duplicates`) for accounts, people, payment methods, movements, settlements and rules.
  - Each expense goes with its live shares through the RPC `save_expense_with_shares` (atomic; the server ignores older writes).
  - Records just pulled are not echoed back.
  - A rejected row is isolated so it doesn't block the batch, and the watermark stays before it, so it is retried.
  - Text is trimmed to the column limits. Sample data stays on the phone.
- **When:** at app start and each return to the foreground, 3 s after any local change, and "Sync Now". There is no background service.
- **Receipts:** the Web's `receipt_path` is kept on the record. Android keeps its own screenshots on the phone and doesn't upload them yet (open item). Deleting the account also removes the Web's receipt files.
- **iOS** doesn't sync yet (planned in `Docs/Sync-Architecture.md`). iPhone data reaches Android through Cloud Backup restore, or through the Web's "Bring in iPhone data" import followed by Android sync.

## Offline behaviour

Everything except sign-in, sync and cloud backup works offline. Saves are local and instant. A cloud backup that fails offline is reported on the Account screen and the daily job retries when the network returns.

## Security & privacy

- **Permissions:**
  - `INTERNET` is install-time and granted automatically.
  - `CAMERA` is runtime, asked only when the user taps "Take Photo of Receipt". It is the only permission shown under App info → Permissions.
  - WorkManager adds normal, no-prompt permissions (network state, wake lock, boot completed).
  - Screenshots, photos and PDFs come through the Android photo picker, file picker and share sheet, so there are no storage or media permissions (and Play's photo/video permission policy doesn't apply).
  - No notifications, location, contacts, SMS or accessibility.
  - `permissions/` holds the central `PermissionManager`. Its state comes from Android (`checkSelfPermission`, `shouldShowRequestPermissionRationale`, hardware features), plus a record of past answers so "not requested yet" and "permanently denied" can be told apart.
  - `rememberPermissionGate` explains, asks, and continues the feature automatically, including after a trip to Settings. If access is refused it offers the photo picker instead.
  - Settings → Permissions & Access shows the real state of each permission.
- Session tokens encrypted with a non-exportable Android Keystore AES-GCM key; Android Auto Backup excluded for data and prefs (`data_extraction_rules.xml`).
- No service-role key anywhere; the publishable key is read from `local.properties` (git-ignored). RLS protects the data server-side.
- No OCR text or amounts are logged.

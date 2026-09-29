# SpenDrop — Engineering Documentation, Technical Audit & Case Study

> **Documentation metadata**
>
> | Field | Value |
> |---|---|
> | Project | SpenDrop (renamed from "SpendDrop" on 2026-09-25; identifiers, targets and bundle IDs were renamed, the App Group and receipts folder keep their original names so existing data is found) |
> | Version | **1.4.0** "Shared Money & Cloud Backup" (`MARKETING_VERSION`), build 1. The Settings → About row shows the same label. |
> | Documentation date | 2026-09-29 (first edition 2026-09-25; this edition covers the financial architecture, accounts, shared expenses, cash flow, automation, optional sign-in and cloud backup) |
> | Documentation status | Complete for `master` at the 1.4.0 update |
> | Repository | `https://github.com/tirukon015/SpenDrop` (default branch `master`) |
> | Live URL | Not applicable. Native iOS app; no App Store / TestFlight listing. |
> | Developer | Touhidul Islam Rukon (sole git author) |
> | Technology stack | Swift, SwiftUI, SwiftData (versioned schema), Apple Vision (OCR), Swift Charts, PhotosUI, App Intents, AuthenticationServices, CryptoKit, Security (Keychain), Network, UIKit (Share Extension host), App Groups, Xcode; optional Supabase (Auth, Storage, Postgres with Row Level Security) over HTTPS |
> | Current deployment | Local Xcode builds to the iOS Simulator and developer devices. No CI/CD, no store distribution. |
> | Last verified | 2026-09-29 on the iOS 27 simulator: app, Share Extension and UI-test target build; **274/274** in-app checks across 12 suites pass; **6/6** XCUITest flows pass; V1 → V3 and V2 → V3 migrations rehearsed on copies of real data with no loss. Version 1.4.0 has **not** been verified on a physical iPhone. Sign-in and cloud backup were verified against a simulated Supabase server only. |

---

## Table of contents

1. [Executive Summary](#1-executive-summary)
2. [Project Overview](#2-project-overview)
3. [Problem Statement](#3-problem-statement)
4. [Objectives](#4-objectives)
5. [Requirements](#5-requirements)
6. [Technology Stack](#6-technology-stack)
7. [Architecture](#7-architecture)
8. [Project Structure](#8-project-structure)
9. [Features](#9-features)
10. [User Workflows](#10-user-workflows)
11. [Database](#11-database)
12. [APIs](#12-apis)
13. [Authentication & Authorization](#13-authentication--authorization)
14. [Security Review](#14-security-review)
15. [Performance & Optimization](#15-performance--optimization)
16. [Error Handling](#16-error-handling)
17. [UI / UX](#17-ui--ux)
18. [Development Process](#18-development-process)
19. [Challenges & Solutions](#19-challenges--solutions)
20. [Testing & Verification](#20-testing--verification)
21. [Deployment](#21-deployment)
22. [Current Status](#22-current-status)
23. [Future Improvements](#23-future-improvements)
24. [Case Study](#24-case-study)
25. [Skills Demonstrated](#25-skills-demonstrated)
26. [Portfolio Version](#26-portfolio-version)
27. [GitHub README Version](#27-github-readme-version)
28. [Evidence & Traceability](#28-evidence--traceability)
29. [Final Summary](#29-final-summary)

Throughout this document, **"Verified"** means the claim was confirmed by reading the source code, project configuration, git history, or by the build/test runs of 2026-09-25 and 2026-09-29. **"Inferred"** means the conclusion is drawn from code comments or structure. Anything else is marked **"Not verified."**

---

## 1. Executive Summary

SpenDrop is a native, local-first iOS expense tracker built for Malaysian daily spending. A user takes a screenshot of any payment confirmation (Touch 'n Go eWallet, Maybank/MAE, CIMB OCTO, RHB, Apple Pay, DuitNow QR, receipts), shares it to SpenDrop or picks it from Photos, and the app reads the amount, merchant, provider, category, date/time and reference **on the device** with Apple Vision and a custom rule-based parser. The user confirms and saves.

Version 1.4.0 adds an optional financial layer without changing that core:

- **Shared expenses** (split equally, by parts or exact amounts; paid by me or someone else) and **calculated person balances** in PayBook.
- **Money In / Money Out / own transfers** (loans, repayments, income, refunds) kept strictly separate from spending, plus **cash flow** on Home and in Breakdown.
- **Accounts** that group recorded activity per bank / e-wallet / cash (never presented as a live balance).
- **Automation**: direction hints from screenshots, learned per-merchant categories, a Share Extension "Save as", and an App Intent for the Shortcuts Apple Pay (Wallet) automation.
- **Data safety**: an explicitly versioned SwiftData schema (V1 → V3), safe mode instead of deleting an unreadable store, pre-upgrade copies, dated local backup history, id-based import.
- **Optional account and cloud backup** on the Supabase free tier (Google or email sign-in; append-only, per-device backups; restore merges by id after a local safety copy).

Key verified facts:

| Metric | Value | Source |
|---|---|---|
| Swift source files | 89 (app, extension, in-app tests, UI tests) | `find SpenDrop SpenDropUITests -name '*.swift'` |
| Swift lines of code | ~24,200 | `wc -l` over the above |
| Xcode targets | 3 (`SpenDrop` app, `SpenDropShare` extension, `SpenDropUITests`) | `project.pbxproj` |
| SwiftData models | 8 (`Expense`, `ExpenseShare`, `MoneyMovement`, `Account`, `PayBookProfile`, `PayBookPaymentMethod`, `ClassificationRule`, legacy `PayBookContact`) | `Models/` |
| Schema versions | V1 (frozen), V2, V3 with an explicit `SchemaMigrationPlan` | `Data/SchemaVersions.swift` |
| Payment sources / channels / categories | 17 / 10 / 12 | `PaymentSource`, `PaymentChannel`, `ExpenseCategory` |
| Known merchants in detector | 54 | `MerchantDetector.knownMerchants` |
| Automated checks | 274 in-app (12 suites) + 6 UI flows, all passing on 2026-09-29 | §20 |
| Git commits | 377 (2026-09-16 → 2026-09-29) | `git log` |
| Third-party packages | 0 (Apple frameworks only; Supabase is used through its HTTPS API) | no SPM/CocoaPods/Carthage files |
| Network use | Only the optional sign-in and cloud backup, only when configured and signed in | `Data/Cloud/` |

---

## 2. Project Overview

### 2.1 In simple English

SpenDrop is an iPhone app that helps you keep track of the money you spend. Instead of typing every transaction, you share the payment screenshot your bank or e-wallet shows you, and SpenDrop reads the details itself — on your phone. If you shared a bill with friends, you can split it and SpenDrop remembers who owes whom. If you lend money, get paid back or receive a refund, you can record it without it counting as spending. You can see how much you spent, how much money came in and went out, and what each account was used for. Everything works without an account; if you sign in, SpenDrop also keeps a backup copy in the cloud.

### 2.2 Technical description

| Item | Detail |
|---|---|
| Project type | Native iOS application with a Share Extension and a UI-test target |
| Purpose | Local-first personal expense tracking with on-device OCR, optional shared-expense and cash-flow tracking, optional cloud backup |
| Problem solved | Manual expense logging is slow; Malaysian bank/e-wallet apps have no unified export; shared bills and loans get lost in chat messages |
| Target users | Individuals in Malaysia who pay with cash, e-wallets, bank apps, DuitNow QR and Apple Pay, and who share bills with friends |
| Main use case | Payment → screenshot → Share → SpenDrop → auto-parse → confirm → saved |
| Product principle | "How much did I spend?" stays the core question. Advanced features are optional and never make normal expense entry longer. |
| Status | Version 1.4.0; actively developed; not released |
| Development environment | macOS 27, Xcode 27, iOS 27 simulator runtime |
| Deployment environment | iOS 17.0+, iPhone only, portrait only |

---

## 3. Problem Statement

### 3.1 Verified facts

- The parser targets Malaysian formats (`RM`, `MYR`, Bahasa Malaysia labels, local providers) and rejects non-expense numbers (balances, limits, points, ads, fees, cashback). (`TransactionParser`, `PaymentProviderDetector`.)
- The same payment can be captured twice (notification + receipt). (`DuplicateDetector`, `MovementDuplicateDetector`.)
- Before 1.4.0 the app could only record expenses: money lent to a friend or received back had to be entered as a fake expense or not at all, which distorted "how much did I spend?".
- Before the 1.4.0 data-safety work, a store that failed to open was **deleted** and the automatic JSON backup was only written after restores/imports. Both are fixed (§11, §19 C13).

### 3.2 Goals

- Capture faster than typing; keep processing on the device.
- Keep **spending** separate from **cash flow** and from **who owes whom**.
- Never lose financial data, including across schema upgrades and restores.
- Stay within a RM0 budget: no paid APIs, AI services or aggregators.

### 3.3 Requirements identified

- Extract transaction details from an image with no network.
- Split one expense between people with exact sen and a clear payer.
- Record loans, repayments, income, refunds and own transfers without inflating spending.
- Calculate balances per person and per currency; never store them.
- Associate transactions with accounts without pretending to know bank balances.
- Upgrade the database without data loss; back up locally and optionally to the cloud.

---

## 4. Objectives

| # | Objective | Evidence |
|---|---|---|
| O1 | Automate expense capture from screenshots | `OCRService`, `TransactionParser`, `ExpenseReviewView`, `ShareExtension/` |
| O2 | Keep data local-first | SwiftData in the App Group; cloud only as optional backup (`Data/Cloud/`) |
| O3 | Keep normal entry fast | `AddExpenseView` unchanged flow; split and type switch are optional |
| O4 | Improve accuracy | confidence, candidate chips, duplicate checks, learned rules (`TransactionClassifier`) |
| O5 | Spending and cash-flow visibility | `DashboardView`, `AnalyticsView` (Breakdown), `FinancialCalculator`, `PeriodGrouping` |
| O6 | Shared money without a debt app | `SplitDraft`, `ExpenseShare`, `PersonLedger`, PayBook views |
| O7 | Protect financial data | `ExpenseDataContainer` safe mode and pre-upgrade copies, `UserDataBackupService` |
| O8 | Verifiable on-device | 12 in-app suites (`--run-all-tests`), XCUITest target |

---

## 5. Requirements

### 5.1 Functional requirements (implemented and verified unless noted)

| ID | Requirement | Status |
|---|---|---|
| FR-1 | Add a manual expense (amount, merchant, category, funding account, channel, date, notes) | Implemented (`AddExpenseView`) |
| FR-2 | Import an image from Photos and parse it | Implemented |
| FR-3 | Receive an image through the Share Sheet and parse it | Implemented (`SpenDropShare`) |
| FR-4 | Review/edit before saving; choose Save as Expense / Money In / Money Out / Transfer | Implemented (`ExpenseReviewView`; extension offers Expense / Money In / Money Out) |
| FR-5 | Duplicate warnings for expenses and money records; never delete silently | Implemented |
| FR-6 | Transactions timeline with filters All / Expenses / Money In / Money Out / Shared / Transfers | Implemented (`ExpensesView`, `ActivityFeed`) |
| FR-7 | Edit and delete expenses and money records | Implemented |
| FR-8 | Split an expense equally, by parts or exact amounts; payer = me or a person; "Same as last time" | Implemented (`SplitEditorView`, `SplitDraft`) |
| FR-9 | Person balances, history, Record Repayment, Frequent/Archived, delete blocked while money is owed | Implemented (`PayBookView`, `PayBookDetailView`, `PersonLedger`) |
| FR-10 | Money In / Money Out / own transfers with accounts | Implemented (`MoneyMovementFormView`) |
| FR-11 | Accounts with recorded in / out / net; add, rename, archive | Implemented (`AccountsView`) |
| FR-12 | Home spending totals, conditional Cash Flow and Balances cards | Implemented (`DashboardView`) |
| FR-13 | Breakdown: Spending \| Cash Flow, merchants, my share, refunds, net spending, trends | Implemented (`AnalyticsView`) |
| FR-14 | Learned categories from user corrections | Implemented (`TransactionClassifier`, `ClassificationRule`) |
| FR-15 | Apple Pay automation via Shortcuts | Implemented (`ApplePayIntent`, `ApplePayAutomation`); needs a physical device to exercise |
| FR-16 | Local backup, history, export/import, format versioning | Implemented (`UserDataBackupService`) |
| FR-17 | Optional sign-in (Google, email), sign out, delete cloud account | Implemented (`AuthService`, `AccountView`); verified against a simulated server |
| FR-18 | Optional cloud backup and restore | Implemented (`CloudBackupService`); verified against a simulated server |
| FR-19 | Default currency preference | **Partially implemented**: stored, not applied (amounts are RM) |

### 5.2 Non-functional requirements

| Area | What the code does | Assessment |
|---|---|---|
| Correctness of money | All new calculations in integer sen; splits use largest remainder and must add up exactly | Implemented, tested |
| Data safety | Safe mode; pre-upgrade copies; explicit migrations; backup history and shrink guard; id-based import | Implemented, rehearsed on real data copies |
| Privacy | On-device OCR; financial details not logged in release builds; cloud is optional and owner-only (RLS) | Implemented; RLS not yet verified on a live project |
| Offline | Everything except sign-in and cloud backup works offline; cloud backup waits for connectivity | Implemented |
| Performance | Downsampling before OCR; in-memory aggregation per view | Adequate for personal data volumes; no benchmarks |
| Maintainability | Pure calculation types (`SplitCalculator`, `FinancialCalculator`, `PersonLedger`, `ActivityFeed`) separated from views; generator-managed project | Good |
| Cost | RM0: Apple frameworks, Supabase free tier | Implemented |

---

## 6. Technology Stack

| Technology | Purpose | Where / how | Verified |
|---|---|---|---|
| Swift 5 mode (async/await, `@MainActor`, `@Observable`) | Language | all sources | ✅ |
| SwiftUI, Swift Charts, PhotosUI | UI, charts, image picking | `Views/` | ✅ |
| SwiftData + `VersionedSchema` / `SchemaMigrationPlan` | Persistence and explicit migrations | `Data/SchemaVersions.swift`, `ExpenseDataContainer` | ✅ |
| Core Data metadata API | Checking whether a store matches the current model before opening it | `ExpenseDataContainer.storeMatchesCurrentModel` | ✅ |
| Vision | On-device OCR | `OCRService` | ✅ |
| App Intents | Shortcuts action for the Wallet automation | `App/ApplePayIntent.swift` | ✅ (metadata generated) |
| AuthenticationServices | Google OAuth sheet (`ASWebAuthenticationSession`) | `AuthService` | ✅ build; not run against a live project |
| CryptoKit | PKCE S256 challenge; backup content hash | `AuthService`, `CloudBackupService` | ✅ (RFC 7636 vector) |
| Security (Keychain) | Storing the auth session | `KeychainStore` | ✅ |
| Network (`NWPathMonitor`) | Waiting for connectivity before cloud backup | `CloudBackupService` | ✅ |
| UIKit | Share Extension host, haptics, pasteboard | `ShareExtension/`, utils | ✅ |
| App Groups | Sharing the store with the extension | entitlements, `ExpenseDataContainer` | ✅ |
| Supabase (optional) | Auth, private Storage bucket, `backups` table with RLS | `supabase/migrations/…sql`, `Data/Cloud/` | ✅ SQL written; not executed on a live project |
| XCTest / XCUITest | UI automation | `SpenDropUITests/` | ✅ |
| Python 3 | Deterministic `project.pbxproj` generator | `scripts/generate_xcodeproj.py` | ✅ |

**Why these choices:** SwiftData keeps the UI live with little code and now has explicit versions for safe upgrades. Supabase was chosen for the optional cloud because it is the only RM0 option offering Google + email sign-in, private file storage and database-enforced per-user access together (Firebase Storage now requires a paid plan; CloudKit cannot do Google or email sign-in). Its official HTTPS API is called directly so the project stays free of third-party packages and every call can be tested against a fake server.

---

## 7. Architecture

### 7.1 Current architecture (verified)

```
 ┌──────────────────────────── SpenDrop.app ─────────────────────────────┐  ┌──── SpenDropShare.appex ────┐
 │ Home | Transactions | PayBook | Breakdown | More (Account, Accounts,  │  │ ShareViewController (UIKit) │
 │                                               Settings)               │  │  └ ShareExtensionView       │
 │ Add sheet: Expense ▾ / Money In / Money Out / Transfer                │  │    Save as Expense /        │
 │ Split editor · Review (Save as) · App Intent (Apple Pay automation)   │  │    Money In / Money Out     │
 └───────────────────────────────┬───────────────────────────────────────┘  └──────────────┬──────────────┘
                                 │            shared model + engine sources                  │
                                 ▼                                                           ▼
   Image → OCRService → TransactionParser → ParsedTransaction (+ DirectionDetector suggestion)
                                              → TransactionClassifier (learned rules)
                                              → DuplicateDetector / MovementDuplicateDetector
                                              → review → save as Expense (+ ExpenseShare) or MoneyMovement
                                 │
   Calculation layer (pure, integer sen, never stored):
     SplitCalculator · SplitDraft · FinancialCalculator (spending, cash flow, account activity,
     person balances) · PersonLedger · ActivityFeed · PeriodGrouping
                                 │
   Stored (SwiftData, schema V3, App Group container):
     Expense ─1:N─ ExpenseShare      Expense ─ payer ─ PayBookProfile ─1:N─ PayBookPaymentMethod
     MoneyMovement ─ person / linkedExpense / account / counterAccount
     Account ─ expenses / movements / incomingTransfers      ClassificationRule
                                 │
   Safety: safe mode · SpenDropSafety/pre-upgrade copies · auto-backup + SpenDropBackupHistory · export/import
                                 │ (optional, signed in, online)
                                 ▼
   CloudBackupService ──HTTPS──► Supabase: Auth (Google / email) · private bucket "backups" · table "backups" (RLS)
```

### 7.2 Runtime flow of the OCR pipeline

Unchanged from the first edition, with two additions after step 9: **(10a) direction suggestion** — `DirectionDetector` suggests Money In / refund / income / own transfer only from clear wording and returns no suggestion when wording is missing or mixed; **(10b) classification** — a learned rule confirmed at least twice takes priority over the parser's category, which takes priority over a generic guess. Steps 1–9: downsample to 1280 px → Vision OCR with row-band sort → provider detection (sender vs recipient bank, Apple Pay + bank) → context flags → amount extraction with semantic classification (balance / ad / fee / cashback / discount / total) → merchant and category → date, time, reference → confidence. Then duplicate check and review.

### 7.3 Financial model

| Concept | Rule |
|---|---|
| `Expense.amount` | always the full bill; never changed by splits or refunds |
| Spending | full amount if I paid; my share if someone else paid |
| Cash out | full amount if I paid; 0 if someone else paid |
| Money In | income, loans received, repayments received, refunds, other in |
| Money Out | expenses I paid + loans given + repayments made + other out |
| Own transfer | moves money between my accounts; excluded from spending, Money In, Money Out and net |
| Net cash flow | Money In − Money Out |
| Refund | a Money In linked to the original expense; gross spending unchanged, net spending shown separately |
| Person balance | calculated per currency: shares I paid (+), my share when they paid (−), loans/repayments (±); positive = they owe me |

---

## 8. Project Structure

```
SpenDrop/                                   repository root
├── SpenDrop.xcodeproj/                     3 targets; schemes SpenDrop, SpenDropShare, SpenDropUITests
├── SpenDrop/
│   ├── App/                SpenDropApp.swift (entry, lifecycle backups, test runner), ApplePayIntent.swift
│   ├── Models/             Expense, ExpenseShare, MoneyMovement (+ kinds), Account, PayBookProfile,
│   │                       PayBookPaymentMethod, ClassificationRule, PayBookContact (legacy),
│   │                       ExpenseCategory, PaymentSource, PaymentChannel, ExpenseSourceType
│   ├── Data/               ExpenseDataContainer, SchemaVersions, UserDataBackupService, AccountLinker,
│   │                       Money, SplitCalculator, SplitDraft, FinancialCalculator, PersonLedger,
│   │                       ActivityFeed, PeriodGrouping, MoneyMovementDraft, MovementDuplicateDetector,
│   │                       TransactionClassifier, ApplePayAutomation, TransactionFilterEngine,
│   │                       DuplicateDetector, TransactionReconciliationEngine, SampleData,
│   │                       DataSafetyTests, FinancialModelTests, AccountFeatureTests
│   │   ├── Cloud/          CloudCore, AuthService, CloudBackupService
│   │   └── Tests/          TestKit (runner), SplitFeature, PeopleBalance, ActivityFeed, Phase7,
│   │                       Hardening, Cloud (auth + backup) tests
│   ├── OCR/                OCRService, TransactionParser, DirectionDetector, PaymentProviderDetector,
│   │                       MerchantDetector, CategoryDetector, MonetaryCandidate, ParsedTransaction,
│   │                       ImageStorageService, ImagePipelineDiagnostics, TransactionParserTests
│   ├── Views/              Dashboard (Home), Expenses (Transactions), PayBook, Analytics (Breakdown),
│   │                       More, Account, Accounts, Money, Split, AddExpense, Review, Settings, MainTabView
│   ├── ShareExtension/     ShareViewController, ShareExtensionView, Info.plist, entitlements
│   ├── Resources/          Assets, Info.plist, entitlements, CloudConfig/ (template; real config git-ignored),
│   │                       DiagnosticSamples/
│   └── Utils/              CurrencyFormatter, HapticFeedback
├── SpenDropUITests/        XCUITest flows
├── supabase/migrations/    SQL for the optional cloud backend
├── scripts/                generate_xcodeproj.py
└── docs/                   this document, SUPABASE_SETUP.md, screenshots (v1.4 and earlier)
```

Maintainability notes: model and engine files are compiled into both app and extension through the generator's `share_source_paths`; cloud code, calculators and tests are app-only. The generator also defines the UI-test target and a folder reference for the optional cloud config.

---

## 9. Features

### 9.1 Quick Cash / Manual Expense Entry

**Purpose:** record a cash or card expense in a few taps.

**How it works:** `AddExpenseView` shows a hero amount field (decimal keypad), four increment chips (+RM5/+RM10/+RM20/+RM50) that add to the current value, funding-account chips (the fixed list plus any account added in More → Accounts), payment-channel chips, a 12-category grid, a merchant text field with seven quick chips that also pre-select a category (e.g. "Grab" → Transport), a date/time picker and an optional description.

**User flow:**
1. Tap "Quick Cash" (Home header, empty state, or "+" toolbar).
2. Enter or chip-build the amount.
3. Optionally pick source, category, merchant, date, notes.
4. Tap "Save Expense" (disabled until amount > 0).

**Technical implementation:** `Expense(amount:currency:merchant:category:paymentSource:date:notes:sourceType:)` inserted into `modelContext`; empty merchant becomes "Food / Dining" when category is Food, else "Unknown".

**Validation:** `isValid = parsedAmount > 0` using `CurrencyFormatter.parse` (strips RM/MYR/commas). Save button disabled otherwise.

**Security:** none needed (local).

**Evidence:** `Views/AddExpense/AddExpenseView.swift`; screenshot `01_dashboard.png` shows the Quick Cash button.

### 9.2 Screenshot / Receipt Import from Photos

**Purpose:** parse a payment screenshot without leaving the app.

**How it works:** `PhotosPicker` (Home header icon, Home empty state, and top card in Add Expense). On selection an 8-stage pipeline runs on the main actor: load `Data` → decode `UIImage` → obtain `CGImage` (with `CIImage` fallback) → downsampling check → temp-file write test → App Group write/delete test → `OCRService` → `TransactionParser`. Each stage logs with a `[SpenDrop][IMAGE]` prefix and fails to a user alert naming the stage.

**User flow:**
1. Tap the viewfinder icon or "Drop Screenshot".
2. Choose an image; overlay "Reading transaction..." appears.
3. Review sheet opens with parsed fields, or an alert offers "Try Again" / "Add Manually".

**Evidence:** `DashboardView.processSelectedImage`, `AddExpenseView.processSelectedImage`.

### 9.3 Transaction Parsing Engine

**Purpose:** turn raw OCR text into a structured `ParsedTransaction`.

**How it works:** see §7.2. Highlights verified in code:

- Amount regexes accept `RM 25.90`, `RM25.90`, `MYR 25.90`, `25.90 RM`, `RM450`, `Amount: RM25.90`, `Jumlah`, `Paid`, `-RM12.00`, and bare `1234.56`; values must be 0 < v < 500,000.
- 50+ advertisement keywords ("promo", "voucher", "shop now", "near me!", "validity:", brand names seen in TNG banners) plus exact-word checks for "ad", "ads", "promo", "off".
- Balance keywords in English and Malay ("baki akaun", "baki tersedia").
- Total keywords prefer "grand total" / "jumlah bayaran"; a line containing "subtotal" is never a total.
- Spatial rule: an amount in the bottom 35 % of the image near ad keywords is an advertisement.
- Status normalisation: `failed`, `balance_inquiry`, `transferred`, `payment_successful`, `approved`, `completed`.
- Apple Pay screens produce `suggestedRemark` "Paid via Apple Pay • CIMB" which pre-fills the notes field.
- `ParsedTransaction.toNormalizedDictionary()` exposes a stable dictionary (`paymentProvider`, `paymentMethod`, `currency` as "MYR", `status`, `underlyingBank`, `amount`, `date` as `yyyy-MM-dd`, `time` as `HH:mm:ss`).

**Validation:** every extractor returns `nil` rather than guessing; merchant candidates are rejected if they contain currency, "account", "successful", provider names, or are in a 60-entry generic-label set.

**Evidence:** `OCR/TransactionParser.swift`, `OCR/PaymentProviderDetector.swift`, `OCR/MerchantDetector.swift`, `OCR/CategoryDetector.swift`, tests 1–20 and 24–42.

### 9.4 Expense Review Screen

**Purpose:** let the user confirm or correct the parse before anything is stored.

**How it works:** `ExpenseReviewView` is initialised from a `ParsedTransaction`. It shows one of five banners (Payment Failed / Account Balance / Possible Duplicate / Expense Detected / Possible Expense Detected), the editable amount, "POSSIBLE AMOUNTS" chips for every non-excluded candidate with its semantic label, merchant field with ✓/? indicator, category menu, payment menu (with Apple Pay + bank logos), date picker, notes, a tappable thumbnail of the original image, Save and Discard.

**Validation:** amount > 0; duplicate check runs in `.onAppear` and gates Save behind an "Add Anyway / Cancel" alert.

**Technical implementation:** on save, the image is written via `ImageStorageService.saveImage`, and the `Expense` is created with `sourceType: .screenshot`, `ocrText` (full OCR text), `underlyingBank`, `paymentMethod`, `transactionReference`, and a numeric confidence (1.0 / 0.7 / 0.4).

**Evidence:** `Views/Review/ExpenseReviewView.swift`.

### 9.5 iOS Share Extension (SpenDropShare)

**Purpose:** capture from any app's Share Sheet: Photos, Files, bank app receipts.

**How it works:**
- `Info.plist` activation rule accepts attachments conforming to `public.image`, `public.file-url`, `public.png`, `public.jpeg`, `public.heic`.
- `ShareViewController` attaches the SwiftUI root **synchronously in `viewDidLoad`** (comment: "so the extension NEVER presents a black screen"), then loads the image asynchronously.
- Image loading tries, per attachment and per prioritised UTI (png, jpeg, heic, image, file-url, url, data), three strategies in order: `loadItem`, `loadDataRepresentation`, `loadFileRepresentation`, handling `UIImage`, security-scoped `URL`, and `Data` results.
- The image is downsampled to 1280 px, then `ShareExtensionViewModel.startAutomaticOCR` runs OCR → parse → duplicate check and moves through phases `receiving → processing → reviewing | noTextFound | error`.
- `noTextFound` offers "Enter Details Manually" (blank review with the image attached) and "Retry".
- Save writes to the **same** `ExpenseDataContainer.shared` (App Group store) with `sourceType: .shareExtension`, then calls `extensionContext.completeRequest`.
- Since 1.4.0 the review offers **Save as Expense / Money In / Money Out** (preselected only from clear wording), links the account immediately, warns about duplicate money records and teaches the learned category rule (§9.19–9.20).
- `shareLog()` writes every step to stdout, `NSLog`, and an append-only file in the App Group; the main app prints that file when launched with `--read-share-logs`.

**Evidence:** `ShareExtension/*`, tests "Persistence Lifecycle & Duplicate Verification"; the build produced `SpenDrop.app/PlugIns/SpenDropShare.appex`.

### 9.6 Duplicate Detection

**Purpose:** prevent the same payment being stored twice.

**How it works:** `DuplicateDetector.checkDuplicate(amount:merchant:date:reference:in:)` fetches up to 10 expenses with the identical amount within ±48 h of the target date (`#Predicate`), then applies three rules in order: identical transaction reference; same merchant (substring match either way, ignoring "unknown") on the same calendar day; any candidate within one hour. Returns `DuplicateCheckResult { isDuplicate, matchedExpense, reason }` with a human-readable reason used in the alert.

**Evidence:** `Data/DuplicateDetector.swift`; tests "Duplicate Detection (Identical Transaction)", "Unique Transaction (Non-Duplicate)", "Persistence Lifecycle & Duplicate Verification".

### 9.7 Transactions (unified timeline)

`ExpensesView` shows one calculated timeline (`ActivityFeed`) of expenses and money movements for the selected date range, grouped by day, with type filters **All · Expenses · Money In · Money Out · Shared · Transfers**, search, the existing account/category/channel filters and sort. The header shows **Spent** prominently and **In / Out** separately; nothing adds spending and cash flow together. Rows: expenses show category, account · channel, a small "2 people" badge and "You RM x" / "Paid by X" when shared; Money In shows "+RM", Money Out "−RM", transfers "From → To · Not spending". Swipe to delete; tap to open details or the edit sheet. Timeline items are built on the fly and never stored, so nothing can be counted twice.

### 9.8 Expense Detail, Edit and Delete

Detail shows the amount, merchant, category, funding account, channel, date/time, source, reference, notes, receipt image and — for shared expenses — "Your share", "Paid by" and each person's share (with a "Needs attention" row if exact amounts no longer add up). Edit Expense keeps the account link in step with the funding choice, re-applies the split to a changed amount (Equally/Parts recalculate; exact Amounts must be corrected before saving) and teaches the learned rule.

### 9.9 Home

Today / This Week / This Month **spending** (my share when someone else paid). Secondary cards appear only when relevant: "My share of N shared expenses this month", **Cash Flow · this month** (Money In, Money Out, Net) once money movements exist, and **Balances** (owed to you / you owe) when non-zero.

### 9.10 Breakdown (formerly Analytics)

A **Spending | Cash Flow** switch. Spending keeps the existing metrics, period comparison, daily chart and category / channel / account breakdowns, and adds Shared & Refunds (shared bills, my share, refunds, net spending), Top Merchants and a daily/weekly/monthly trend. Cash Flow shows Money In, Money Out, Net Cash Flow (with spending shown separately), a by-type list and a trend chart with Money In and Money Out bars; own transfers are excluded.

### 9.11 PayBook (people, payment details and balances)

People are `PayBookProfile`s with any number of `PayBookPaymentMethod`s (bank account, e-wallet, payment ID; masked in lists, one-tap copy, duplicate-method warning). 1.4.0 adds a summary (owed to you / you owe / settled), Frequent / Other People / Archived groups, a balance on each row, and on the person page: the balance with explicit direction ("Bijoy owes you RM 15.00" / "You owe Riyad RM 20.00"), **Record Repayment** prefilled with the exact amount, a history of shared expenses, loans and repayments (with the effect of each), and Frequent / Archived switches. Deleting a person is blocked while any balance is non-zero ("Archive instead"); deleting a settled person keeps all records under their saved name.

### 9.12 More, Settings and Account

More holds **Account** (optional sign-in, cloud backup), **Accounts** (recorded activity per account) and **Settings** (backup & data recovery, preferences, diagnostics, privacy statement, about).

### 9.13 In-App Self-Test Runner and Diagnostics

- `ParserSelfTestView` runs `TransactionParserTests.runAllTests()` on appear and on demand, listing each case with pass/fail, details and actual value.
- Launching with `--run-all-tests` (or one suite flag such as `--run-tests`) runs the in-app suites at startup, prints `[TEST][suite] [PASS|FAIL] …` lines and one `[SUITE_SUMMARY] <suite>: n/m PASSED` line per suite, and exits with code 0/1 — usable from `xcrun simctl launch --console-pty`. See §20.
- `--run-image-diagnostics` runs `ImagePipelineDiagnostics` over three bundled samples (PNG, JPEG, HEIC) through eight steps (data load, UIImage, CGImage, downsample, temp write, App Group write/read, OCR, parser).

**Evidence:** `OCR/TransactionParserTests.swift`, `OCR/ImagePipelineDiagnostics.swift`, `App/SpenDropApp.swift`; verified run on 2026-09-25.

### 9.14 Receipt Image Storage

`ImageStorageService` writes JPEG (quality 0.8) named `<uuid>.jpg` into `SpenDropReceipts/` in the App Group (falls back to Documents), loads by relative path (with Documents fallback), and deletes. `Expense.imageRelativePath` holds the filename. Deleting an `Expense` does **not** delete its image file (verified: no call to `deleteImage` in delete paths).

### 9.15 Sample Data Seeding

`SampleData.seed` inserts 18 realistic Malaysian expenses spread over today / this week / this month, flagged `isSampleData = true`, and is idempotent (skips if any sample record exists). First-launch seeding is additionally guarded by the `UserDefaults` key `has_seeded_initial_sample_data_v1`.

### 9.16 Shared Expenses (Split with others)

A collapsed "Split with others" row in Add Expense, Edit Expense and Expense Detail opens the split editor: people (Me is always included and cannot be removed; frequent people as chips; "Add Person" / "New Person" through the PayBook picker), method **Equally / Parts / Amounts**, **Paid by** (Me, a participant or anyone else), "Same as last time" from local history, and a live footer ("✓ Balanced · Your share RM 7.50" or "RM 2.00 left to assign"). `SplitCalculator` works in integer sen with the largest-remainder method; leftover sen go to Me first when I paid; exact amounts that don't match the total are an error, never adjusted. Shares are `ExpenseShare` rows with a name snapshot.

### 9.17 Money In, Money Out and Transfers

The Add sheet opens on Expense exactly as before; its title menu switches to Money In (income, repayment received, loan received, refund, other), Money Out (loan given, repayment made, other) or Transfer (two different accounts). A person is only asked for on loans and repayments. Records are `MoneyMovement`s in sen with person, account and linked-expense snapshots. Invalid drafts cannot be saved.

### 9.18 Accounts

More → Accounts lists each account with **Recorded In / Recorded Out / Recorded Net** and a note that this is not a bank balance. Accounts are created automatically from funding choices (the V1 → V2 migration created one per existing funding account; saves and edits keep the link current), and can be added, renamed and archived (never deleted, so history is kept). Account detail lists its expenses, money movements and transfers.

### 9.19 Learned Categories (ClassificationRule)

When you save or correct an expense, `TransactionClassifier.learn` records the merchant (normalised) and your category. A rule confirmed twice in a row becomes trusted. Priority when suggesting: your explicit choice (never overridden) → trusted rule → the parser's rule → a generic guess from the merchant text → Other. Everything is local.

### 9.20 Scan Direction and "Save as"

`DirectionDetector` suggests Money In ("you have received", "credited to your"), income (salary wording), refund or own transfer (reload / top up) only from clear phrases, and nothing when phrases conflict. The in-app review offers **Save as Expense / Money In / Money Out / Transfer** (preselected only from a clear suggestion, with the reason shown); the Share Extension offers Expense / Money In / Money Out and links the account immediately. Scanned movements keep their reference, source and channel.

### 9.21 Apple Pay Automation

`LogApplePayPurchaseIntent` ("Log Apple Pay Purchase") can be used in the Shortcuts **Wallet → Transaction** automation with the Merchant, Amount and Card variables. It saves an Apple Pay expense with the learned category and the bank from the card name when recognised, and skips a repeat trigger (same amount and merchant within 10 minutes). It only sees Apple Pay taps; bank-app, QR and other notifications are not readable by iOS apps.

### 9.22 Payment Channels

Apple Pay, QR, Bank Transfer, Card, Cash, **DuitNow QR**, **Online Banking**, **E-Wallet**, Other, Unknown. The three new values were added without renaming any stored value; detection still never guesses ("Unknown" is valid).

### 9.23 Data Safety and Local Backup

- The store is opened through `openStoreSafely`: if it cannot be opened, the app starts in **safe mode** on a temporary store, leaves the files untouched, and offers "Move Aside & Use Backup" (moves, never deletes).
- Before a schema change, the store files are copied to `SpenDropSafety/pre-upgrade-<time>/` (newest 3 kept). The change is detected from a recorded schema fingerprint **and** the store file's own metadata.
- The JSON auto-backup is refreshed after saves (debounced), on background and on foreground; the previous file is kept once per day (7 days) and whenever records would disappear (last 5).
- Backup format 3 carries expenses (with account, payer and shares), people (with flags), payment methods, accounts, money movements and learned rules. Formats 1–2 still import; newer formats are refused. Import matches by id (accounts and rules also by name/merchant), never merges people by name, reports possible duplicates instead of skipping them, and keeps records edited more recently on the device.

### 9.24 Optional Account and Cloud Backup

More → Account: **Continue with Google**, **Create Account**, **Sign In**; when signed in: profile, status, cloud backup status, last backup, **Backup Now / Retry**, **Restore from Cloud Backup**, **Sign Out**, **Delete Cloud Account**. After sign-in with existing local data the app only offers to back it up. Backups are append-only files under `backups/<user>/<device>/` with metadata rows (device, app/schema/format version, counts), uploaded after changes, on background and on demand, skipped when content is unchanged, and paused while offline. Restore shows what a backup contains, saves a local safety copy, then merges by id. Without a `SupabaseConfig.plist` the screen explains that cloud backup isn't set up.

---

## 10. User Workflows

**Share-sheet capture:**
```
Pay → screenshot → Share → SpenDrop → OCR → parse (+ direction suggestion, learned category)
  → duplicate check → review: Save as Expense | Money In | Money Out
  → save (account linked; rule learned) → app shows it on next appearance
```

**In-app scan:** Home or Add Expense → Photos → review (Save as Expense / Money In / Money Out / Transfer) → save.

**Manual expense:** + → amount → (optional funding, channel, category, merchant, notes, **Split with others**) → Save.

**Shared lunch:** + → RM30 → Split with others → add Bijoy, Riyad, Labib → Equally → Paid by Me → Done → Save → PayBook shows each owes RM 7.50.

**Someone else paid:** split as above with **Paid by Bijoy** → my spending RM 7.50, cash out RM 0, "You owe Bijoy RM 7.50".

**Loan and repayment:** + → Money Out → Loan given → Shadin → RM150 → Save … later PayBook → Shadin → Record Repayment Received → prefilled → Save.

**Own transfer:** + → Transfer → From Maybank → To Touch 'n Go → RM200 → Save (not spending; net cash flow unchanged).

**Refund:** Money In → Refund → amount (the original expense stays unchanged; Breakdown shows net spending).

**Cloud backup:** More → Account → Continue with Google / Sign In → "Back up this iPhone's data?" → Back Up Now → later automatic.

**Restore:** More → Account → Restore from Cloud Backup → pick a backup (details shown) → Restore → safety copy → merge.

**Verification:** `--run-all-tests` (274 checks) and the SpenDropUITests scheme (6 flows).

---

## 11. Database

| Item | Detail |
|---|---|
| Technology | SwiftData (SQLite) in the App Group container (`Library/Application Support/default.store`), opened with `ModelContainer(for: Schema(versionedSchema: SpenDropSchemaV3.self), migrationPlan: SpenDropMigrationPlan.self, …)` |
| Versions | **V1** frozen copies of the original models; **V2** adds Account, ExpenseShare, MoneyMovement and fields on Expense/PayBookProfile; **V3** adds ClassificationRule |
| Migrations | V1 → V2: custom stage (lightweight changes, then `AccountLinker` creates one account per meaningful `fundingAccount` value and links expenses; the text is kept). V2 → V3: lightweight (new table only) |
| Freeze checks | tests compare the V1 and V2 schema fingerprints with those recorded from the shipped builds |
| Failure handling | safe mode (store untouched), pre-upgrade copies, explicit "Move Aside & Use Backup" |
| Relationships | see diagram; deletions never destroy history (nullify + name snapshots), except an expense's own shares (cascade) |

### 11.1 `Expense` (key fields)

`id` (unique) · `amount` (Double, full bill) · `currency` · `merchant` · `categoryRaw` · `paymentSourceRaw` · `underlyingBankRaw` · `paymentMethodRaw` · `paymentChannelRaw` · `fundingAccount` (text snapshot) · `fundingInstrument` · `date` · `notes` · `transactionReference` · `imageRelativePath` · `sourceTypeRaw` · `ocrText` · `confidence` · matching fields · `createdAt` / `updatedAt` · **V2:** `account` → Account, `paidByMe`, `payer` → PayBookProfile, `payerNameSnapshot`, `splitMethodRaw`, `shares` (cascade), `linkedMovements` (nullify).

### 11.2 `ExpenseShare`

`id` · `expense` · `person` (nil = Me or deleted person) · `isMe` · `nameSnapshot` · `amountMinor` (sen) · `parts` · `enteredMinor` · `sortIndex`.

### 11.3 `MoneyMovement`

`id` · `directionRaw` (in / out / internal) · `kindRaw` (income, loanReceived, repaymentReceived, refund, otherIn, loanGiven, repaymentMade, otherOut, ownTransfer) · `amountMinor` · `currency` · `date` · `person` + `personNameSnapshot` · `linkedExpense` + `linkedExpenseSnapshot` · `account` · `counterAccount` · `note` · `transactionReference` · `sourceTypeRaw` · `paymentChannelRaw` · `createdAt` / `updatedAt`.

### 11.4 `Account`

`id` · `name` · `typeRaw` (bank, eWallet, cash, other) · `currency` · `icon` · `isArchived` · `createdAt` · `sortIndex`. **No balance field by design.**

### 11.5 `PayBookProfile`, `PayBookPaymentMethod`, `ClassificationRule`

- `PayBookProfile`: `id`, `name`, `photoData`, `notes`, timestamps, `paymentMethods` (cascade), **V2:** `isFrequent`, `isArchived`, inverse `shares`, `paidExpenses`, `movements` (all nullify).
- `PayBookPaymentMethod`: `id`, `paymentTypeRaw`, `provider`, `customProviderName`, `accountIdentifier`, `label`, `notes`, timestamps, `profile`.
- `ClassificationRule`: `id`, `merchantKey`, `categoryRaw`, `suggestedTypeRaw`, `accountId`, `hitCount`, timestamps.
- `PayBookContact`: legacy model, migrated into profiles at launch.

### 11.6 Relationship diagram

```
PayBookProfile ─1:N─ PayBookPaymentMethod
      │  ▲  ▲
payer │  │  └──────────── person ── MoneyMovement ── linkedExpense ──┐
      ▼  │ person                       │  │                          │
   Expense ─1:N─ ExpenseShare           │  └ account / counterAccount ─┤
      │                                 ▼                             ▼
      └──────────── account ────────► Account ◄──────────────────── (nullify)
ClassificationRule (standalone, accountId by value)
```

### 11.7 Stored vs calculated

Stored: the models above. Calculated and never stored: spending, cash out, my share, Money In/Out, net cash flow, refunds and net spending, account activity, person balances, the Transactions timeline, trends.

---

## 12. APIs

**Internal interfaces** (unchanged ones from the first edition plus): `SplitCalculator.calculate`, `SplitDraft.apply/removeSplit/recalculateAfterAmountChange/lastTimeSuggestion`, `FinancialCalculator.summary/personBalances/accountActivity`, `PersonLedger.balances/entries/summary/repaymentDraft`, `ActivityFeed.items`, `PeriodGrouping.buckets`, `TransactionClassifier.suggestCategory/learn`, `DirectionDetector.detect`, `MovementDuplicateDetector.findMatch`, `AccountLinker.resolveAccount/relink/linkUnlinkedExpenses`, `UserDataBackupService.makePayload/applyBackupPayload/importFromJSON`, `ApplePayAutomation.record`.

**App Intent:** `LogApplePayPurchaseIntent(amount: Double, merchant: String, card: String?)`, exposed through `SpenDropShortcuts`.

**External HTTPS (optional; Supabase, only when configured and signed in):**

| Call | Endpoint |
|---|---|
| Email sign-up / sign-in / refresh / PKCE exchange | `POST /auth/v1/signup`, `POST /auth/v1/token?grant_type=password|refresh_token|pkce` |
| Google authorize (opened in `ASWebAuthenticationSession`) | `GET /auth/v1/authorize?provider=google&redirect_to=spendrop://auth-callback&code_challenge=…&code_challenge_method=s256` |
| Sign out | `POST /auth/v1/logout` |
| Upload backup file (never overwrite) | `POST /storage/v1/object/backups/<user>/<device>/<id>.json` with `x-upsert: false` |
| Record / list / prune metadata | `POST|GET|DELETE /rest/v1/backups` |
| Download backup | `GET /storage/v1/object/authenticated/backups/<path>` |
| Delete files | `DELETE /storage/v1/object/backups` |
| Delete account | `POST /rest/v1/rpc/delete_my_account` |

**Launch arguments:** see README (`--run-all-tests`, per-suite flags, `--print-schema-fingerprints`, `--ui-testing`, diagnostics and demo flags).

---

## 13. Authentication & Authorization

- **Local use:** no account required. The iOS sandbox and App Group remain the local boundary.
- **Optional account:** Supabase Auth. Google through OAuth with PKCE (S256) in Apple's `ASWebAuthenticationSession`, returning to `spendrop://auth-callback`; email/password sign-up (handles "confirm your email") and sign-in. Passwords are handled by the auth service and never stored by SpenDrop.
- **Session:** access/refresh tokens and the user profile are stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in SwiftData or UserDefaults. Tokens refresh automatically within 60 s of expiry; an expired refresh token signs out of the cloud with a message; being offline keeps the session.
- **Configuration:** only the public anon key and URL, read from the git-ignored `CloudConfig/SupabaseConfig.plist`. No service-role key in the app.
- **Authorization (server):** Row Level Security on `public.backups` (select/insert/delete where `user_id = auth.uid()`; no update) and on `storage.objects` for bucket `backups` (first folder must equal `auth.uid()`; no update). `delete_my_account()` is `security definer` and deletes only `auth.uid()`.
- **Sign out / delete:** never touch local data. Deleting the cloud account removes the backup files first, then calls `delete_my_account()`.

---

## 14. Security Review

| Area | Finding | Classification |
|---|---|---|
| Network exposure | Only the optional Supabase HTTPS calls; none without configuration and sign-in | Implemented |
| Secrets in repo | No keys committed; the real config file is git-ignored; only a template with placeholders | Implemented |
| Session storage | Keychain, this device only | Implemented |
| Cloud access control | RLS policies and a private bucket defined in SQL | Implemented; **not yet verified on a live project** |
| Cloud data encryption | HTTPS in transit, provider encryption at rest; no client-side (end-to-end) encryption, deliberately, to avoid an unrecoverable key | Documented limitation |
| Logging | Amounts, merchants and OCR text are printed only in debug builds; extension logs no longer include merchant/amount | Improved (was a gap) |
| Destructive recovery | Store is never deleted; moves require explicit user action | Fixed (was a gap) |
| Test isolation | A test check proves no suite opens the real database; UI tests use `--ui-testing` temporary store | Implemented |
| PayBook identifiers | Stored in plain text; copied to the general pasteboard without expiry | Needs improvement (unchanged) |
| Data at rest | Default iOS Data Protection | Acceptable for personal use |
| Input validation | Amounts > 0 (sen); split, movement and account forms validated in pure types | Implemented |
| Dependencies | No third-party packages | Implemented |
| App lock | No biometric gate | Not implemented |

The app should not be described as "fully secure"; its threat model is a personal device plus an optional per-user cloud backup.

---

## 15. Performance & Optimization

Implemented (verified in code):

| Technique | Where |
|---|---|
| Image downsampling to 1280 px max side before OCR (twice: extension entry and `OCRService`) | `ShareViewController`, `OCRService` |
| `format.scale = 1.0` rendering to avoid 3× retina buffers | both downsamplers |
| Vision request on `Task.detached(priority: .userInitiated)` with `autoreleasepool` | `OCRService` |
| Quantised row-band sort (O(n log n) with a strict weak ordering) | `OCRService` |
| `fetchLimit = 10` on duplicate query, `fetchLimit = 1` on count checks | `DuplicateDetector`, `ExpenseDataContainer`, `SampleData` |
| Sorted `@Query` so lists need no re-sorting | `DashboardView`, `ExpensesView`, `AnalyticsView`, `PayBookView` |
| JPEG compression 0.8 for stored receipts | `ImageStorageService` |
| Lazy grid for category picker | `AddExpenseView` |
| OCR task cancellation on user cancel; re-entrancy guard | `ShareExtensionViewModel` |

Not implemented: pagination, caching layers, background indexing. All aggregation is in-memory per view body evaluation; `groupedExpenses` and the analytics dictionaries are recomputed on each render.

**No verified benchmark was available.** The only timing-related artefacts are the diagnostics report fields; no numbers are recorded in the repository.

---

## 16. Error Handling

| Situation | Behaviour |
|---|---|
| Invalid amount / split / movement | Save disabled with a specific message (e.g. "RM 2.00 left to assign", "Choose who this money is with", "From and To must be different accounts") |
| OCR failure / no text | alert with the failing stage (app) or `noTextFound` phase with manual entry (extension) |
| Store cannot be opened (corrupt or failed migration) | **safe mode**: temporary store, original files untouched, alert explaining that nothing was deleted; optional "Move Aside & Use Backup" |
| Schema change | pre-upgrade copy before opening |
| Possible duplicate expense / money record | warning with "Add Anyway" / "Continue Anyway"; never an automatic delete |
| Deleting a person with a balance | blocked, "Archive instead" offered |
| Backup file from a newer app | refused with a message; nothing imported |
| Cloud: offline | "Waiting for internet", retried when connectivity returns |
| Cloud: upload / server failure | "Backup failed" with Retry; local data unaffected; an uploaded file whose metadata failed is removed again |
| Cloud: expired session | signed out of the cloud with a message; local data unaffected |
| Cloud restore: no safety copy / newer format / interrupted download | refused; nothing applied |
| Sign-in errors | wrong password, unconfirmed email, existing email, weak password, cancelled sheet — each with a clear message |

Remaining gap: several local `try? modelContext.save()` calls still ignore save errors.

---

## 17. UI / UX

- **Structure:** five tabs — Home | Transactions | **PayBook (centre)** | Breakdown | More. More holds Account, Accounts and Settings. No sixth tab.
- **Principle:** normal expense entry is unchanged; split, type switch and people only appear when asked for.
- **Clarity:** Spending is always shown separately from Money In / Out; transfers say "Not spending"; account totals say "not your real bank balance"; balances always say who owes whom.
- **Visual language:** system grouped backgrounds, rounded cards, SF Symbols, rounded numerals, provider logos, category colours in charts; green for money in / owed to you, orange for owed by you.
- **States:** empty, loading, error and safe-mode states on every screen; confirmation dialogs for destructive actions.
- **Accessibility:** system components and Dynamic Type; accessibility identifiers on key controls (used by the UI tests). No VoiceOver audit yet.
- **Screenshots (2026-09-29, UI-test captures, synthetic data):** `docs/screenshots/v1.4/` — Home cash flow, Transactions transfers, split editor, PayBook balances, person detail, accounts, Breakdown cash flow, Money In and Transfer forms, Account. Earlier captures remain in `docs/screenshots/` and `docs/screenshots/case-study/`.

---

## 18. Development Process

| Phase | Date | What was built |
|---|---|---|
| Milestone 1 — core tracker | 2026-09-16 | models, main tabs, sample data, project generator |
| Milestone 2 — OCR & parser | 2026-09-16 | Vision OCR, Malaysian parser, review screen, self-test runner |
| Milestone 3 — Share Extension | 2026-09-17 | extension, shared App Group store, duplicate detection |
| Extraction overhaul | 2026-09-18 | provider detector, semantic amount classification, logos, real-reference tests |
| PayBook V1 / corrected PayBook | 2026-09-18 → 09-25 | profiles with multiple payment methods, rename to SpenDrop |
| Backup & transaction intelligence | 2026-09-25 → 09-28 | JSON backup/import, payment channels vs funding accounts, reconciliation, filters |
| **1.4.0 — financial architecture** | 2026-09-29 | Phase 0 data safety → 1 navigation → 2 models & migration → 3 accounts & money in/out → 4 splits → 5 PayBook balances → 6 unified timeline → 7 Home/Breakdown, channels, learned rules, parser direction, Share Extension save-as, Apple Pay intent → authentication and cloud backup → 8 hardening and UI tests |

The 1.4.0 work was merged into `master` as 347 small commits (one per file section or code block, each with an explanation drawn from the code) on 2026-09-29. Each phase was gated by the full test run before the next started.

---

## 19. Challenges & Solutions

### C1 — Advertisement prices being picked as the payment amount
- **Challenge:** TNG eWallet receipts show a banner such as "Panasonic air conditioner RM450" beneath a RM22.00 transfer.
- **Cause:** any regex for `RM\d+` matches both.
- **Investigation:** test "TNG RM22.00 vs RM450 Advertisement" and "Real Ref: TNG Interbank Transfer (Ad Disqualification & Sender TNG)" encode the real screenshots.
- **Solution:** `MonetarySemanticType.advertisement` with a 50+ keyword list, exact-word checks ("ad", "off"), neighbouring-line checks, and a spatial rule using Vision bounding boxes (bottom 35 % of the image). Excluded types can never be selected.
- **Result:** both tests pass; ad amounts still appear as candidates (with the label) so the user can override.
- **Lesson:** layout position is a strong signal that pure text rules miss.

### C2 — Sender bank vs recipient bank in interbank transfers
- **Challenge:** a CIMB → Maybank transfer receipt mentions both banks; the expense should be attributed to CIMB.
- **Cause:** keyword presence alone is ambiguous.
- **Investigation:** three "Real Ref" tests (CIMB→Maybank, Maybank→RHB, RHB→CIMB).
- **Solution:** `PaymentProviderDetector` first collects `recipientBankIds` from lines following "Receiving bank / Recipient bank / Beneficiary bank / To bank / Bank", then parses the "From" block, then applies sender rules that exclude a bank if it appears only as a recipient.
- **Result:** all three tests pass.
- **Lesson:** model the document structure (header, from-block, recipient-block) instead of the bag of words.

### C3 — Balance, credit-limit and reward-point screens producing fake expenses
- **Solution:** `checkBalanceOrLimitOnly` returns true when balance/limit/points keywords appear **without** any transaction indicator; the parser then returns no amount, `.low` confidence, status `balance_inquiry`, and the review screen shows an orange "Account Balance / Credit Limit" banner.
- **Evidence:** tests "False Positive: Account Balance / Credit Limit / Reward Points".

### C4 — Negative amounts in notifications ("-RM12.00")
- **Solution:** the amount regexes accept an optional leading `-`, `–` or `—`; the captured group excludes the sign so the stored amount is positive.
- **Evidence:** test "Real Ref: TNG Notification (-RM12.00 Negative Amount)".

### C5 — Runtime crash while sorting Vision observations *(inferred from code comment)*
- **Challenge:** sorting text observations by floating-point `midY` with a tolerance violates strict weak ordering, which Swift's sort can trap on.
- **Solution:** quantise `1 - midY` into integer bands of 0.018 and compare bands, then `minX`. Comment: "Quantized row-band sort ensures strict weak ordering (prevents Swift sorting runtime crash)".
- **Lesson:** comparators must be transitive; bucketing is a cheap way to guarantee it.

### C6 — Share Extension showing a black screen / failing to receive images *(inferred from code comments and structure)*
- **Challenge:** extension UI appeared black and shared items were not decoded consistently across Photos, Files and screenshots.
- **Solution:** attach `UIHostingController` synchronously in `viewDidLoad` with explicit constraints and a system background colour; load the image afterwards using seven prioritised UTIs and three `NSItemProvider` strategies; write a timestamped log into the App Group and expose it through `--read-share-logs` because extension stdout is hard to observe.
- **Result:** the multi-strategy loader is the shipped code; the log mechanism is used throughout.
- **Lesson:** extensions need their own observability.

### C7 — Memory limits in the extension
- **Solution:** downsample to 1280 px at scale 1.0 (comment targets "< 30MB"), `Task.detached` + `autoreleasepool` around the Vision request, cancellable OCR task.
- **Evidence:** `ShareViewController.downsampleImageIfNeeded`, `OCRService`.

### C8 — Sharing one database between two processes
- **Solution:** App Group entitlement on both targets, `ModelConfiguration(schema:url:)` pointing at `SpenDrop.store` in the container, identical `Schema` in both processes, all model and engine files compiled into both targets.
- **Evidence:** commits `aead78c`, `76b5f0e`; fix commit `0008dfb` ("Fix SampleData target membership in SpendDropShare") shows the cost of the no-framework approach.

### C9 — Apple Pay masking the real bank
- **Solution:** `underlyingBank` on `ProviderDetectionResult` and `Expense`; composite display "Apple Pay • CIMB" with two logos; `suggestedRemark` pre-fills notes.
- **Evidence:** tests "Apple Pay + CIMB Underlying Bank", "Apple Pay + Maybank Underlying Bank", "Apple Pay Standalone".

### C10 — Reproducible Xcode project without hand-editing pbxproj
- **Solution:** `scripts/generate_xcodeproj.py` derives every object ID from `sha1(name)[:24]`, so regenerating produces stable diffs. Xcode 27 later re-saved the file (uncommitted diff), so the script and the checked-in project may drift; the script remains the documented source of truth for target membership.

### C12 — Keeping users' data after renaming the app
- **Challenge:** renaming SpendDrop to SpenDrop changed the bundle identifiers and, initially, the App Group identifier. On the developer's phone the new app opened an empty store while the old app still held 19 real transactions.
- **Cause:** the store lives in the App Group container, and a new group identifier is a new, empty container. Investigating this also showed that the original URL-based configuration (`ModelConfiguration(schema:url:)` pointing at `<group>/SpenDrop.store`) had never been the store actually in use on the device: the group container held `Library/Application Support/default.store`, which is where SwiftData's fallback `ModelContainer(for:)` writes when an app has exactly one App Group. The URL configuration was failing on device and the fallback was silently doing the work.
- **Investigation:** the old container was copied off the phone with `devicectl device copy from` and inspected with `sqlite3` (19 rows in `ZEXPENSE`, 1 in `ZPAYBOOKCONTACT`). The new configuration was proven on the simulator by injecting the backed-up store at the group path and seeing the real rows on the Dashboard.
- **Solution:** the App Group identifier reverted to the original value and is now a single documented constant; the container is configured with `groupContainer: .identifier(...)`, which resolves to exactly the file that already existed; the receipts folder keeps its original name for the same reason.
- **Result:** the renamed app reopens the existing store on the device without any data copy. Both targets still built and the 48 tests of that date passed.
- **Lesson:** storage identifiers are part of a product's contract with its users. A rename that touches them needs a migration or, as here, a decision to keep them.

### C11 — Testing without a Mac in the loop
- **Solution:** tests are plain Swift functions compiled into the app and runnable from Settings or via `--run-tests` with a process exit code, instead of an XCTest bundle.
- **Trade-off:** no Xcode test navigator integration, no code coverage; test code ships in the binary. Since 1.4.0 a separate XCUITest target (`SpenDropUITests`) covers real UI interaction.

### C13 — A failed upgrade used to delete the database
- **Challenge:** when the store could not be opened, the original container code deleted `default.store*` and rebuilt from the automatic backup — which was only written after restores/imports, so it could be days old.
- **Solution:** `openStoreSafely` never deletes: it enters safe mode on a temporary store and leaves the files in place; a pre-upgrade copy is taken before any schema change; the backup is refreshed after saves and on background with dated history and a "before shrink" copy.
- **Evidence:** data-safety tests "Failed migration leaves database untouched", "Corrupt database file is preserved"; rehearsal with a corrupted store on the simulator.

### C14 — SwiftData can silently drop data during an upgrade
- **Challenge:** a test that opened a store created with a different model *succeeded* — SwiftData's inferred migration removed the unknown entity without any error.
- **Solution:** explicit `VersionedSchema`s with frozen V1 models, a V2 freeze check, explicit migration stages, and a pre-upgrade copy taken before opening (the only protection against silent drops).
- **Evidence:** test "Pre-upgrade copy keeps data an automatic migration drops"; V1 → V3 and V2 → V3 rehearsals on real data copies (all ids, amounts, text and links identical).

### C15 — The pre-upgrade check trusted stale settings
- **Challenge:** the "schema changed?" check read a fingerprint from shared UserDefaults. When a store file was swapped (as in a restore) the cached fingerprint said nothing changed and no copy was taken.
- **Solution:** also read the store file's own metadata (`NSPersistentStoreCoordinator.metadataForPersistentStore` + `isConfiguration(compatibleWithStoreMetadata:)`) and take a copy if either check says the model changed.
- **Evidence:** test "Pre-upgrade copy taken when settings are out of sync with the store".

### C16 — A test run opened the real database
- **Challenge:** after adding learned categories to the Share Extension's `applyParsedTransaction`, the existing self-tests (which call that function) opened and upgraded the real store.
- **Solution:** kept `applyParsedTransaction` free of database access and moved the suggestion to the real OCR path; added a permanent "Test isolation" check that fails if any suite opens the real store; UI tests use a `--ui-testing` temporary store.
- **Evidence:** reproduction on a copy of V2 data; isolation check 1/1.

### C17 — Keeping money exact
- **Challenge:** `Expense.amount` is a `Double`; splitting RM10 three ways or summing many values in floating point drifts.
- **Solution:** a single conversion point (`Money.minorUnits`) and integer sen everywhere in new code; largest-remainder splits; exact-amount mismatches are errors.
- **Evidence:** Phase 2 and Phase 4 tests (RM100.99 → 10099, 0.1 + 0.2 → 30, 7-way RM100 split, leftover sen to Me).

---

## 20. Testing & Verification

### 20.1 Automated in-app suites (2026-09-29, iOS 27 simulator)

Run with `--run-all-tests`. Suites use in-memory stores or temporary folders; the final isolation check proves the real database was never opened. Authentication and cloud suites use an in-memory fake of the Supabase HTTP API.

| Suite | Covers | Result |
|---|---|---|
| Existing | parsing, amounts, false positives, providers, 10 real-reference screenshots, real samples, merchant rules, filters and reconciliation scenarios, PayBook, backup, share flow | **93/93** |
| Data safety | safe mode, corrupt store, frozen V1/V2 schemas, pre-upgrade copies, backup history and shrink guard, format compatibility, id-based import, people not merged | **18/18** |
| Phase 2 — financial models | money conversion, split calculator, accounts and linker, relationships and delete rules, spending/cash-flow/balances, backup format, V1 → V2 migration | **46/46** |
| Phase 3 — accounts, money in/out | account activity, relinking, funding options, drafts, form validation | **10/10** |
| Phase 4 — shared expenses | equal/parts/exact, rounding, mismatch, payer, amount edits, participant changes, snapshots, deletion, duplicates, "same as last time" | **15/15** |
| Phase 5 — PayBook balances | loans, repayments, direction flip, currencies, summary, history, record payment, archive/delete safety | **11/11** |
| Phase 6 — timeline | filters, sorting, no duplicates, edit/delete, spending unchanged, transfers excluded | **12/12** |
| Phase 7 — automation | channels, learned rules and priority, direction detection (incl. real parser), movement duplicates, scan drafts, Apple Pay automation, trends/breakdowns, backup V3, V2 → V3 migration | **14/14** |
| Phase 8 — hardening | V1 → V3 chain, full export → wipe → import round trip (twice), transfers both ways, account archive/rename, invalid input, money-in kinds | **6/6** |
| Authentication | PKCE (RFC 7636 vector), Google exchange, cancel/deny, email sign-in, wrong password (two formats), backend down, sign-up (both flows), validation, session restore, refresh, offline, expiry, sign out/in, not configured, account deletion | **14/14** |
| Cloud backup | upload path/headers/metadata, append-only, unchanged skipped, not signed in/configured, offline, failure + retry, metadata cleanup, interrupted upload, list, restore merge, duplicate restore, safe refusals, full cloud round trip | **13/13** |
| Test isolation | no suite opened the real database | **1/1** |
| **Total** | | **274/274** |

### 20.2 UI tests (XCUITest, 2026-09-29)

`SpenDropUITests` (6/6 passed): five tabs in order; add an expense; split with a new person and see "Bijoy owes you RM 15.00" in PayBook; create two accounts, record Money In and a transfer, check Transactions filters and account totals; Home cash-flow card and Breakdown → Cash Flow; More → Account (not configured state). Screenshots are attached to the result bundle.

### 20.3 Migration rehearsals (copies of real data)

| Rehearsal | Result |
|---|---|
| V1 (original pre-safety store) → V3 | 23 expenses (RM 1,500.11), 10 people, 16 payment methods preserved; 5 accounts created, 22 expenses linked, 1 "Unknown" left unlinked; pre-upgrade copy taken; auto-backup format 3 |
| V2 (with 3 money movements) → V3 | all ids, funding text, amounts, account links, movements (RM 3,850.00) and snapshots byte-identical; rules table added; V2 pre-upgrade copy taken |
| Rollback | the pre-1.4 app opened a pre-upgrade copy with all data |
| Safe mode | corrupted store left untouched; good backup not overwritten |

### 20.4 Build verification

App, Share Extension and UI-test target build. The App Intent metadata is generated for the app. Remaining warnings are pre-existing ones plus two tests that intentionally call the deprecated duplicate cleanup.

### 20.5 Not covered

Physical-iPhone testing of 1.4.0; sign-in and cloud backup against a live Supabase project (SQL and RLS not yet executed); the Google sheet; the Share Extension at runtime in the share sheet; the Wallet automation (needs a device); VoiceOver audit; performance benchmarks.

---

## 21. Deployment

| Item | Detail |
|---|---|
| Build | Open `SpenDrop.xcodeproj`, scheme `SpenDrop`, run; UI tests with scheme `SpenDropUITests` |
| Signing | Automatic; App Group `group.com.spendrop.shared` required on app and extension |
| Bundle identifiers | `com.spendrop.SpenDrop`, `com.spendrop.SpenDrop.ShareExtension`, `com.spendrop.SpenDropUITests` |
| Optional backend | Supabase free tier: run `supabase/migrations/20260929000000_spendrop_cloud_backup.sql`, enable Google and Email providers, add redirect `spendrop://auth-callback`, place `SupabaseConfig.plist` (see `docs/SUPABASE_SETUP.md`) |
| Environments | Debug and Release; no staging |
| CI/CD | None |
| Distribution | None configured |

---

## 22. Current Status

### Completed (verified on the simulator)
- Everything from the first edition (OCR, parser, Share Extension, PayBook, backup, filters, reconciliation).
- 1.4.0: data safety, versioned schema V1–V3, accounts, Money In/Out/Transfers, shared expenses, PayBook balances, unified Transactions, Home and Breakdown cash flow, payment channels, learned categories, scan direction, Share Extension save-as, Apple Pay App Intent, optional sign-in and cloud backup, 274 in-app checks, 6 UI flows.

### Needs the developer's setup or a device
- Supabase project, Google OAuth client and `SupabaseConfig.plist` (then the testing checklist in `docs/SUPABASE_SETUP.md`).
- Physical-iPhone run of 1.4.0 (export a backup first); Wallet automation.

### Known limitations
- Account totals are recorded activity, not bank balances (live balances intentionally postponed).
- Cloud backups are not end-to-end encrypted; receipt images are not backed up.
- Transfers can't be recorded from the Share Extension (they need two accounts).
- Supabase free projects pause after inactivity (local use unaffected).
- Currency preference is stored but amounts are RM; camera capture not implemented; deleting an expense leaves its image.
- Some local saves still use `try?`; PayBook identifiers use the general pasteboard without expiry.
- The committed `SpenDrop` and `SpenDropShare` schemes reference an older target id (builds work).

---

## 23. Future Improvements

| Priority / Area | Proposal | Reason |
|---|---|---|
| High / Verification | Run the cloud checklist on a live Supabase project and on a physical iPhone | only simulated so far |
| High / Data safety | Replace remaining `try? save()` with handled errors | silent save failures |
| Medium / Security | Expiring, local-only pasteboard for account numbers; optional Face ID | sensitive identifiers |
| Medium / Backup | Include receipt images in backups (optionally); optional end-to-end encryption with a recoverable key | completeness, privacy |
| Medium / CI | GitHub Actions running the build, `--run-all-tests` and UI tests | regressions on push |
| Medium / Architecture | Move models and engine into a Swift package shared by both targets | fewer target-membership mistakes |
| Medium / Features | Transfers from the Share Extension; refund linking UI; currency support; camera capture | completeness |
| Low / UX | iPad/landscape, Bahasa Malaysia localisation, VoiceOver audit | reach and accessibility |
| Future | Live bank balances through an official, affordable API if one becomes available | intentionally postponed |

---

## 24. Case Study

### The Problem
Malaysians pay through cash, several e-wallets, many bank apps, DuitNow QR and Apple Pay; none export to one ledger. Shared bills and small loans between friends live in chat messages, and mixing them into an expense list makes "how much did I spend?" wrong.

### The Goal
A private iPhone app where a payment screenshot becomes a saved record in two taps, and where shared money and cash flow are tracked without turning the app into accounting software — at zero running cost.

### The Approach
1. Local-first tracker with on-device OCR and a deterministic, tested parser.
2. Share Extension over a shared App Group store.
3. Before adding financial features, make the data layer safe (safe mode, pre-upgrade copies, explicit schema versions).
4. Separate concepts precisely: expense vs spending vs money in/out vs cash flow vs person balance, all calculated in integer sen.
5. Add optional layers one phase at a time, each gated by the full test run.
6. Offer an optional, free-tier cloud backup that never replaces local data.

### The Solution
A three-target iOS app (app, Share Extension, UI tests) with a shared OCR/parsing engine, eight SwiftData models under an explicit V1 → V3 migration plan, pure calculation types for splits, balances and cash flow, and an optional Supabase-backed account and backup.

### Key Features
Screenshot capture with direction suggestions; learned categories; splits with payer; PayBook balances and repayments; Money In/Out and transfers; accounts; unified timeline; cash-flow views; Apple Pay automation; safe upgrades and backups; optional cloud backup.

### Challenges
See §19, especially C13–C17 (data safety, silent SwiftData drops, stale settings, test isolation, exact money).

### Results (verifiable)
- 274/274 in-app checks and 6/6 UI flows pass (2026-09-29).
- Real-data upgrade rehearsals with no loss; rollback verified.
- No third-party packages; RM0 running cost.
- No user metrics or accuracy percentages exist; none are claimed.

### What I Learned
Designing a financial model where each number answers exactly one question; SwiftData versioning and its failure modes; building safety nets before features; testing network code against a fake server; OAuth PKCE on iOS; row-level security design.

---

## 25. Skills Demonstrated

**Technical** — Swift concurrency, SwiftUI, Swift Charts, SwiftData with versioned schemas and custom migration stages, Core Data metadata checks, Vision, App Intents, AuthenticationServices (OAuth PKCE), CryptoKit, Keychain, Network framework, UIKit interop in extensions.
**Financial modelling** — integer-minor-unit arithmetic, largest-remainder splits, calculated balances and cash flow, separation of spending and cash flow.
**Data safety** — safe mode, pre-upgrade snapshots, backup history, idempotent id-based import, format versioning, migration rehearsal on real data.
**Backend & security** — Supabase Auth/Storage/Postgres, Row Level Security, append-only storage policies, secret-free client configuration.
**Testing** — 12 in-app suites, fake HTTP server, isolation checks, XCUITest with screenshots.
**Tooling** — deterministic Xcode project generation including a UI-test target.
**Product** — phased delivery with explicit scope boundaries (no live bank balances, no groups/trips, RM0 budget).

---

## 26. Portfolio Version

**Project title:** SpenDrop — on-device OCR expense tracker with shared money and cash flow

**1-line description:** Share a payment screenshot and it becomes a categorised expense, parsed on your iPhone; split bills, track who owes whom and see cash flow, with optional cloud backup.

**Tech stack:** Swift, SwiftUI, SwiftData (versioned), Vision, Swift Charts, App Intents, AuthenticationServices, CryptoKit, Supabase (optional). No third-party packages.

**Key features:** Share Sheet capture · learned categories · splits with payer · PayBook balances · Money In/Out and transfers · accounts · unified timeline · cash-flow views · Apple Pay automation · safe upgrades and backups · optional cloud backup.

**My contribution:** Sole developer — product definition, architecture, data model and migrations, OCR engine, extension, UI, backend design, tests.

**Outcome / status:** Version 1.4.0; 274/274 in-app checks and 6/6 UI tests passing on the iOS 27 simulator. Not released.

**GitHub:** https://github.com/tirukon015/SpenDrop

---

## 27. GitHub README Version

`README.md` was rewritten for 1.4.0 on 2026-09-29: Overview · Core ideas (financial model) · Features · Screenshots (v1.4) · Tech Stack · Architecture · Project Structure · Installation · Configuration · Running Locally · Database · Launch Arguments · Authentication · Testing · Deployment · Known Limitations · Project Status · License.

---

## 28. Evidence & Traceability

| Claim | Evidence | Status |
|---|---|---|
| Version 1.4.0 | `MARKETING_VERSION = 1.4.0` in `project.pbxproj` and the generator; Settings About label | Verified |
| Three targets | `PBXNativeTarget` entries for SpenDrop, SpenDropShare, SpenDropUITests | Verified |
| Explicit schema V1–V3 and migration plan | `Data/SchemaVersions.swift` | Verified |
| V1/V2 frozen | data-safety tests with recorded fingerprints | Verified |
| Store never deleted on failure | `ExpenseDataContainer.openStoreSafely`; data-safety tests | Verified |
| Pre-upgrade copies | `snapshotStoreIfSchemaChanged`, `storeMatchesCurrentModel`; tests; rehearsals | Verified |
| Integer-sen money | `Money`, `SplitCalculator`, `FinancialCalculator` | Verified |
| Balances never stored | no balance fields in models; `PersonLedger` | Verified |
| Account has no balance field | `Models/Account.swift` | Verified |
| Timeline not stored | `Data/ActivityFeed.swift` | Verified |
| Backup format 1–3 supported, newer refused | `BackupPayload.supportedVersions`; tests | Verified |
| Learned rules local only | `TransactionClassifier`, `ClassificationRule` | Verified |
| App Intent present | `App/ApplePayIntent.swift`; `Metadata.appintents` in the build | Verified |
| Session in Keychain, no secrets in repo | `KeychainStore`; `.gitignore`; config template | Verified |
| RLS and private bucket | `supabase/migrations/20260929000000_spendrop_cloud_backup.sql` | Written; not executed on a live project |
| 274/274 checks, 6/6 UI tests | simulator runs 2026-09-29 | Verified |
| Real-data migrations lossless | rehearsals 2026-09-29 | Verified |
| 1.4.0 on a physical iPhone | — | Not verified |
| Cloud features against live Supabase | — | Not verified |

---

## 29. Final Summary

SpenDrop 1.4.0 keeps its original strength — a private, tested OCR pipeline that turns Malaysian payment screenshots into expenses — and adds a carefully separated financial layer: shared expenses with exact splits, calculated balances, money in/out and transfers, accounts, cash-flow views and light automation. The data layer was made safe before any of it (safe mode, pre-upgrade copies, explicit schema versions, dated backups, id-based import), and an optional free-tier cloud backup protects data without ever replacing it. Every claim above is traceable to code, the 274 in-app checks, the UI tests or the recorded migration rehearsals; what has not been verified (live Supabase, physical iPhone) is stated as such.

# SpenDrop — Engineering Documentation, Technical Audit & Case Study

> **Documentation metadata**
>
> | Field | Value |
> |---|---|
> | Project | SpenDrop (renamed from "SpendDrop" on 2026-09-25; all identifiers, targets, bundle IDs and the App Group were renamed) |
> | Version | 1.3.0 (`MARKETING_VERSION`), build 1 (`CURRENT_PROJECT_VERSION`). The Settings screen labels this "1.3.0 (Milestone 3 - Share Extension)"; the PayBook feature (branch `feature/paybook`) was added after that label was written and the version string was not bumped. |
> | Documentation date | 2026-09-25 |
> | Documentation status | Complete for the current working tree on branch `feature/paybook` (commit `efd5f99` + uncommitted rename and Xcode 27 project re-save) |
> | Repository | `https://github.com/tirukon015/SpenDrop` (renamed on GitHub 2026-09-25; the old URL redirects; default branch `master`; private at the time of writing) |
> | Live URL | Not applicable. Native iOS app. No App Store / TestFlight listing was found in the project files. Not verified. |
> | Developer | Touhidul Islam Rukon (sole git author, 19 commits) |
> | Technology stack | Swift, SwiftUI, SwiftData, Apple Vision (OCR), Swift Charts, PhotosUI, UIKit (Share Extension host), App Groups, Xcode |
> | Current deployment | Local Xcode builds to iOS Simulator and developer devices (automatic code signing). No CI/CD, no store distribution found. |
> | Last verified | 2026-09-25: `xcodebuild` Debug build succeeded for both targets on iPhone 17 Simulator (iOS 27.0) and for a physical iPhone 17 Pro Max (installed and launched); in-app test suite run via `--run-tests` reported **48/48 PASSED**; image-pipeline diagnostics passed on all three synthetic samples |

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

Throughout this document, **"Verified"** means the claim was confirmed by reading the source code, project configuration, git history, or by the build/test run performed on 2026-09-25. **"Inferred"** means the conclusion is drawn from code comments or structure but was not directly observed. Anything else is marked **"Not verified from the available project files."**

---

## 1. Executive Summary

SpenDrop is a native, offline-first iOS expense tracker built for Malaysian daily spending. Its defining feature is that a user can take a screenshot of any payment confirmation (Touch 'n Go eWallet, Maybank/MAE, CIMB OCTO, RHB, Apple Pay, DuitNow QR, physical receipts), share it to SpenDrop from the iOS Share Sheet or pick it from Photos, and the app reads the amount, merchant, payment provider, category, date/time and reference number **entirely on-device** using Apple's Vision framework and a custom rule-based parser. The user confirms or edits the result on a review screen and saves it.

Around that core the app provides manual "Quick Cash" entry, a dashboard with Today / This Week / This Month totals, a searchable and filterable history, Swift Charts analytics, a "PayBook" of frequently used bank-transfer payees (with masked account numbers and one-tap copy), duplicate-transaction protection, and a built-in self-test runner that executes 48 parser and persistence checks on the device.

Key verified facts:

| Metric | Value | Source |
|---|---|---|
| Swift source files | 42 | `find SpenDrop -name '*.swift'` |
| Swift lines of code | 8,722 | `wc -l` over the above |
| Xcode targets | 2 (`SpenDrop` app, `SpenDropShare` share extension) | `project.pbxproj` |
| SwiftData models | 2 (`Expense`, `PayBookContact`) | `Models/` |
| Payment providers modelled | 16 enum cases | `PaymentSource.swift` |
| Expense categories | 12 | `ExpenseCategory.swift` |
| Known merchants in detector | 56 | `MerchantDetector.swift` |
| Built-in automated test cases | 48, all passing on 2026-09-25 | `TransactionParserTests.swift`, simulator run |
| Git commits | 19 across 2026-09-16 → 2026-09-18 | `git log` |
| External dependencies / packages | 0 (Apple frameworks only) | no SPM/CocoaPods/Carthage files |
| Network calls | 0 | no `URLSession` or networking code in source |

---

## 2. Project Overview

### 2.1 In simple English

SpenDrop is an iPhone app that helps you keep track of the money you spend. Instead of typing every transaction, you take a screenshot of the payment screen your bank or e-wallet app shows you, share it to SpenDrop, and the app reads the important details from the picture by itself. Nothing is sent to the internet: the reading happens on your phone. You check the details, press Save, and the expense appears in your dashboard, history and charts. It also keeps a small address book of people you often transfer money to, so you can copy their account number quickly.

### 2.2 Technical description

| Item | Detail |
|---|---|
| Project name | SpenDrop |
| Project type | Native iOS application with a companion Share Extension target |
| Purpose | Local-first personal expense tracking with on-device OCR extraction of Malaysian payment screenshots |
| Problem solved | Manual expense logging is slow and error-prone; bank/e-wallet apps in Malaysia do not offer a unified export, so users screenshot receipts and forget to record them |
| Target users | Individuals in Malaysia who pay with a mix of cash, e-wallets (Touch 'n Go, GrabPay, Boost), bank apps (Maybank, CIMB, RHB, Public Bank, Bank Islam), DuitNow QR and Apple Pay |
| Main use case | Payment done → screenshot → Share → SpenDrop → auto-parse → confirm → saved |
| Real-world context | Malaysian Ringgit (RM/MYR) formats, Bahasa Malaysia keywords ("Jumlah", "Berjaya", "Baki", "Penerima"), local merchants and telcos |
| Project status | Actively developed; four milestones delivered (M1 core tracker, M2 OCR/parser, M3 Share Extension, PayBook V1). Not released. |
| Current version | 1.3.0 (build 1) — Verified from `project.pbxproj` |
| Repository | `github.com/tirukon015/SpendDrop` — branch `feature/paybook` is ahead of `master` by the PayBook commit |
| Live URL | Not applicable |
| Development environment | macOS 27.0, Xcode 27.0 (27A266a), iOS 27.0 simulator runtime — Verified on the documenting machine. The project's own README previously said "Xcode 16+"; the project file's `LastUpgradeCheck` is now 2700. |
| Deployment environment | iOS 17.0+ (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`), iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only |

---

## 3. Problem Statement

### 3.1 Verified facts (from the code and README)

- The app targets Malaysian payment flows. The parser understands `RM`, `MYR`, Bahasa Malaysia labels, and Malaysian providers. (Verified: `TransactionParser.swift`, `PaymentProviderDetector.swift`.)
- Payment confirmation screens contain several numbers that are *not* the expense: available balance, credit limit, reward points, cashback, fees, and advertising banners with prices. The code contains explicit rules to reject each of these. (Verified: `checkBalanceOrLimitOnly`, `MonetarySemanticType`, ad keyword list.)
- Interbank transfer receipts name both the sender's bank and the recipient's bank; a naive detector would record the wrong provider. (Verified: `recipientBankIds` logic and the "Sender X vs Recipient Y" tests.)
- The same transaction can be captured twice (notification + receipt, or sharing the same screenshot twice). (Verified: `DuplicateDetector.swift`.)
- The original README states the design principle: "Zero cloud dependencies, zero external database, zero tracking." The code contains no networking. (Verified.)

### 3.2 Project goals (stated in README / implied by design)

- Make capture faster than manual typing ("Capture → Understand → Save").
- Keep all financial data on the device.
- Support the specific formats of Malaysian banks and e-wallets rather than a generic receipt scanner.

### 3.3 Manual process being replaced

Not documented in the project files beyond the README tagline. The reasonable reading is that the previous process was typing expenses by hand or not recording them at all. **Not verified from the available project files.**

### 3.4 Requirements identified (derived from implemented behaviour)

- Extract amount, merchant, provider, category, date/time, reference from an image with no network.
- Reject non-expense amounts (balances, limits, points, ads, fees, cashback, discounts).
- Distinguish successful, failed and balance-only screens.
- Let the user correct everything before saving.
- Work from the Share Sheet as well as inside the app.
- Persist to one store shared by the app and the extension.
- Provide totals, history, and analytics.
- Store bank-transfer payees for quick copy.

---

## 4. Objectives

Only objectives supported by the implementation are listed.

| # | Objective | Evidence |
|---|---|---|
| O1 | Automate expense capture from screenshots/receipts | `OCRService`, `TransactionParser`, `ExpenseReviewView`, `ShareExtension/` |
| O2 | Keep data entirely local (privacy by architecture) | SwiftData store in App Group; no networking code; Settings "100% Local-First" text |
| O3 | Reduce repetitive manual entry with quick chips and suggestions | `AddExpenseView` quick amounts (+RM5/10/20/50) and merchant chips |
| O4 | Improve data accuracy via review, confidence scoring and duplicate detection | `ParsingConfidence`, `MonetaryCandidate.confidenceScore`, `DuplicateDetector` |
| O5 | Provide spending visibility and reporting | `DashboardView` totals, `AnalyticsView` donut/bar charts and top merchants |
| O6 | Support Malaysian payment ecosystem specifically | provider rules for TNG, Maybank/MAE, CIMB/OCTO, RHB, Public Bank, Bank Islam, GrabPay, Boost, DuitNow |
| O7 | Make the parser verifiable on-device without a Mac | `ParserSelfTestView` + `--run-tests` launch argument |
| O8 | Centralise frequently used payee bank details | `PayBookContact`, `PayBook/` views |

---

## 5. Requirements

### 5.1 Functional requirements (all implemented and verified unless noted)

| ID | Requirement | Status |
|---|---|---|
| FR-1 | Add a manual expense with amount, currency label, merchant, category, payment source, date/time, notes | Implemented (`AddExpenseView`) |
| FR-2 | Import an image from Photos and run OCR + parsing | Implemented (Dashboard and Add Expense `PhotosPicker`) |
| FR-3 | Receive an image via iOS Share Sheet and run the same pipeline | Implemented (`SpenDropShare` target) |
| FR-4 | Review/edit parsed fields before saving; show status banner (detected / possible / failed / balance / duplicate) | Implemented (`ExpenseReviewView`, `ShareExtensionView`) |
| FR-5 | Offer alternative amount candidates when several were found | Implemented ("POSSIBLE AMOUNTS" chips in `ExpenseReviewView`) |
| FR-6 | Detect probable duplicates and ask before saving | Implemented (`DuplicateDetector`, alerts in both review screens) |
| FR-7 | Persist expenses and the original image | Implemented (SwiftData + `ImageStorageService` JPEG files) |
| FR-8 | List expenses grouped by day with search and filter chips; swipe to delete | Implemented (`ExpensesView`, `FilterBarView`) |
| FR-9 | View, edit and delete a single expense | Implemented (`ExpenseDetailView`, `EditExpenseView`) |
| FR-10 | Dashboard totals for today, this week, this month; today's list; recent activity | Implemented (`DashboardView`) |
| FR-11 | Analytics by category, payment source, top merchants, with period selector | Implemented (`AnalyticsView`) |
| FR-12 | PayBook: list, search by name, add, edit, delete payees; mask account number in list; copy account number | Implemented (`PayBook/`) |
| FR-13 | Warn on duplicate payee (same bank + same normalised account number) | Implemented (`AddPayBookContactView`, `EditPayBookContactView`) |
| FR-14 | Settings: appearance, sample data seeding, clear all, self-test runner, about | Implemented (`SettingsView`) |
| FR-15 | Default currency preference | **Partially implemented**: the picker stores `app_currency` in `UserDefaults`, but no other code reads it; all expenses are created with `"RM"`. |
| FR-16 | Show provider logos for TNG, Maybank, CIMB, RHB, Apple Pay | Implemented (`Assets.xcassets/provider_*`, `ProviderLogoView`) |

### 5.2 Non-functional requirements

| Area | What the code actually does | Assessment |
|---|---|---|
| Performance | Images are downsampled to a max side of 1280 px before OCR; Vision runs in a detached user-initiated task inside an `autoreleasepool`; SwiftData fetches for duplicate checks use `fetchLimit = 10`; count checks use `fetchLimit = 1` | Implemented. No benchmarks exist. |
| Security | No network; data in App Group container protected by the iOS sandbox; no credentials requested (stated in Settings) | Implemented by architecture; see §14 for gaps (plain-text account numbers, unbounded diagnostic log). |
| Scalability | All expenses are loaded with `@Query` and filtered/aggregated in memory in views | Adequate for personal use; no pagination. |
| Reliability | Container creation falls back from App Group URL → default store → `fatalError`; OCR errors are typed (`OCRError`) and surfaced to the user; the extension has 5 explicit UI phases including `error` and `noTextFound` | Implemented. Several `try? modelContext.save()` calls silently swallow persistence errors. |
| Usability | Haptics on every action, empty states on every list, loading overlays during OCR, large amount keypad, quick chips | Implemented. |
| Maintainability | Clear folder split (Models/Data/OCR/Views/ShareExtension/Utils); shared files compiled into both targets; deterministic project generator script | Good separation; the parser is one 653-line class with large keyword lists that would benefit from data files. |
| Accessibility | Uses system fonts, SF Symbols and system colours, which inherit Dynamic Type and Dark Mode | No explicit `accessibilityLabel`s were found. Not verified with VoiceOver. |
| Availability | Fully offline | Implemented. |

---

## 6. Technology Stack

| Technology | Purpose | Where / how it is used | Verified |
|---|---|---|---|
| Swift (`SWIFT_VERSION = 5.0` build setting; Swift concurrency `async/await`, `Task.detached`, `@MainActor` are used) | Language | All 42 source files | ✅ |
| SwiftUI | UI framework | Every screen; `NavigationStack`, `TabView`, `List`, `Form`, `.searchable`, `.swipeActions`, `.sheet`, `.alert` | ✅ |
| SwiftData | Persistence (Apple's ORM over Core Data/SQLite) | `@Model` classes `Expense` and `PayBookContact`; `ModelContainer` in `ExpenseDataContainer`; `@Query` in views; `#Predicate` in `DuplicateDetector` and `SampleData` | ✅ |
| Vision (`VNRecognizeTextRequest`) | On-device OCR | `OCRService.recognizeText`; `.accurate` level, language correction on, languages `en-US`, `ms-MY`, `zh-Hans` | ✅ (whether Vision honours `ms-MY` is not verified) |
| Swift Charts | Analytics visualisation | `SectorMark` donut and `BarMark` in `AnalyticsView` | ✅ |
| PhotosUI (`PhotosPicker`) | Picking screenshots from the library | `DashboardView`, `AddExpenseView` | ✅ |
| UIKit | Share Extension host, haptics, pasteboard, image rendering | `ShareViewController: UIViewController` hosting SwiftUI via `UIHostingController`; `UIImpactFeedbackGenerator`; `UIPasteboard`; `UIGraphicsImageRenderer` | ✅ |
| UniformTypeIdentifiers | Choosing the best representation of a shared item | `ShareViewController.extractImageWithFallback` | ✅ |
| App Groups (`group.com.spenddrop.shared`, the pre-rename identifier, kept deliberately) | Sharing the database and images between app and extension | Both `.entitlements` files; `ExpenseDataContainer.appGroupIdentifier`, `ImageStorageService`, `shareLog` | ✅ |
| Xcode project (`.xcodeproj`, objectVersion 56) | Build system | Generated by `scripts/generate_xcodeproj.py`, later re-saved by Xcode 27 | ✅ |
| Python 3 (dev tooling only) | Deterministic `project.pbxproj` generator | `scripts/generate_xcodeproj.py` (SHA-1 derived 24-hex IDs) | ✅ |
| Git / GitHub | Version control | 19 commits, `origin` on GitHub | ✅ |
| Backend / API / Database server / Auth provider / Hosting / CDN / Caching / Containers / CI / Monitoring / Third-party SDKs | — | **None.** The app has no server component and no third-party code. | ✅ (absence verified) |

**Why these choices (as evidenced by the implementation):**

- *SwiftData over Core Data or SQLite*: the models are declared with `@Model` and consumed with `@Query`, giving live UI updates with almost no boilerplate. The App Group URL is passed via `ModelConfiguration(schema:url:)` so one store serves both targets.
- *Vision over a cloud OCR API*: satisfies the "no cloud" constraint, has no cost, and works in the memory-constrained extension after downsampling.
- *Rule-based parser over ML*: fully deterministic, testable on-device, and tailored to a small set of known Malaysian layouts. The trade-off is maintenance of keyword lists.
- *Share Extension*: it is the only way to make "screenshot → share → save" a two-tap flow without opening the app.

---

## 7. Architecture

### 7.1 Current architecture (verified)

```
                    ┌──────────────────────────────┐        ┌──────────────────────────────┐
                    │  SpenDrop.app (main target)  │        │ SpenDropShare.appex          │
                    │  @main SpenDropApp           │        │ (iOS Share Extension)        │
                    │  MainTabView                 │        │ ShareViewController (UIKit)  │
                    │   ├ DashboardView            │        │   └ UIHostingController      │
                    │   ├ ExpensesView             │        │       └ ShareExtensionView   │
                    │   ├ PayBookView              │        │         (5-phase state UI)   │
                    │   ├ AnalyticsView            │        └──────────────┬───────────────┘
                    │   └ SettingsView             │                       │
                    └──────────────┬───────────────┘                       │
                                   │  both targets compile the same files  │
                                   ▼                                       ▼
        ┌───────────────────────────────────────────────────────────────────────────────┐
        │  Shared engine (source files added to both targets, no framework)             │
        │                                                                               │
        │  Image ──► OCRService ──► OCRResult ──► TransactionParser ──► ParsedTransaction│
        │           (Vision)        (lines +      ├ PaymentProviderDetector             │
        │                            bboxes)      ├ MerchantDetector                    │
        │                                         ├ CategoryDetector                    │
        │                                         └ amount classification               │
        │                                           (MonetaryCandidate)                 │
        │                                                                               │
        │  ParsedTransaction ──► DuplicateDetector ──► Review UI ──► Expense (@Model)    │
        │                                                                               │
        │  ExpenseDataContainer (ModelContainer)   ImageStorageService (JPEG files)      │
        └──────────────────────────────┬────────────────────────────────────────────────┘
                                       ▼
        ┌───────────────────────────────────────────────────────────────────────────────┐
        │  App Group container  group.com.spenddrop.shared  (legacy id, see §11)        │
        │   ├ Library/Application Support/default.store (SwiftData: Expense, PayBookContact)│
        │   ├ SpendDropReceipts/<uuid>.jpg (original screenshots, JPEG q=0.8)           │
        │   └ share_extension_diagnostics.log (append-only extension log)               │
        └───────────────────────────────────────────────────────────────────────────────┘

        No server. No network. No external API.
```

### 7.2 Runtime flow of the OCR pipeline

1. **Input** — `UIImage` from `PhotosPicker` (`loadTransferable(type: Data.self)`) or from `NSItemProvider` in the extension.
2. **Downsample** — if the longer side > 1280 px, redraw at scale 1.0 (`OCRService.downsampleIfNeeded`, and again in `ShareViewController.downsampleImageIfNeeded`).
3. **OCR** — `VNRecognizeTextRequest` on a detached task. Observations are sorted top-to-bottom using a quantised row band (height 0.018 in normalised coordinates) and left-to-right within a band. Output is `OCRResult { fullText, lines[text, confidence, boundingBox], averageConfidence }`.
4. **Provider detection** — `PaymentProviderDetector.detect` runs ordered rules: Apple Pay (with underlying bank), recipient-bank exclusion, then RHB → CIMB → Maybank/MAE → TNG → Public Bank → Bank Islam → GrabPay → Boost → DuitNow QR / DuitNow → Card → Cash → Unknown. Each result carries `normalizedId`, `confidence`, `paymentMethod` and optional `underlyingBank`.
5. **Context flags** — `checkFailedTransaction`, `checkBalanceOrLimitOnly`, `checkCompletedTransaction`.
6. **Amount extraction and classification** — five regexes collect candidates (including negative `-RM12.00` and standalone decimals). Each candidate is classified into a `MonetarySemanticType` (balance, advertisement, fee, cashback, discount, total, transactionAmount, unknown) using keywords on the line, adjacent lines, a ±2-line window and vertical position (bottom 35 % of the image). Excluded types are filtered; `.total` wins, then highest score.
7. **Merchant and category** — labelled patterns ("Paid to:", "Beneficiary name", Bahasa labels), multi-line label look-ahead (up to 15 lines), 56 known merchants, then a receipt-header heuristic; category from merchant table or keyword rules.
8. **Date, time, reference** — nine date formats and six time formats via `DateFormatter` with `en_US_POSIX`, plus regex fallbacks; reference via one regex over "Ref/Transaction ID/Receipt No/No. Rujukan".
9. **Confidence** — `.high` if completed, amount score ≥ 0.85 and merchant or source known; `.medium` ≥ 0.60; `.low` otherwise or if failed/balance.
10. **Duplicate check** — same amount within ±48 h, then: identical reference (case-insensitive) → same merchant same day → any match within 1 hour.
11. **Save** — `Expense` inserted into `modelContext`; image written to `SpenDropReceipts/`.

### 7.3 Planned architecture

No roadmap file exists in the repository. **Not verified from the available project files.**

---

## 8. Project Structure

```
SpenDrop/                                   (repository root; folder on disk is still named "SpendDrop")
├── SpenDrop.xcodeproj/                     Xcode project (2 targets, 2 shared schemes)
│   └── xcshareddata/xcschemes/
│       ├── SpenDrop.xcscheme
│       └── SpenDropShare.xcscheme
├── SpenDrop/                               All source and resources
│   ├── App/
│   │   └── SpenDropApp.swift               @main entry; launch-argument test/diagnostic hooks; seeds sample data
│   ├── Models/                             SwiftData models and enums (compiled into both targets)
│   │   ├── Expense.swift                   @Model, 19 stored properties, enum bridging, formatted amount
│   │   ├── PayBookContact.swift            @Model, masking + display subtitle
│   │   ├── ExpenseCategory.swift           12 categories with SF Symbol + colour
│   │   ├── PaymentSource.swift             16 providers with logo asset, normalised id, brand colour
│   │   └── ExpenseSourceType.swift         manual / screenshot / photo / receipt / shareExtension
│   ├── Data/
│   │   ├── ExpenseDataContainer.swift      ModelContainer in App Group; preview container; seeding; PayBook launch args
│   │   ├── DuplicateDetector.swift         48-hour window duplicate heuristics
│   │   └── SampleData.swift                18 idempotent sample expenses
│   ├── OCR/                                The extraction engine
│   │   ├── OCRService.swift                Vision wrapper, downsampling, row-band sort
│   │   ├── TransactionParser.swift         Orchestrator + amount classification + date/ref extraction
│   │   ├── PaymentProviderDetector.swift   Sender vs recipient bank rules, Apple Pay + bank
│   │   ├── MerchantDetector.swift          Labelled patterns + 56 known merchants + header heuristic
│   │   ├── CategoryDetector.swift          Keyword → category rules
│   │   ├── MonetaryCandidate.swift         Semantic type enum + candidate struct
│   │   ├── ParsedTransaction.swift         Result model + normalised dictionary
│   │   ├── ImageStorageService.swift       JPEG save/load/delete in App Group
│   │   ├── ImagePipelineDiagnostics.swift  8-step PNG/JPEG/HEIC pipeline diagnostics
│   │   └── TransactionParserTests.swift    48 in-app test cases (not an XCTest target)
│   ├── Views/
│   │   ├── MainTabView.swift               5 tabs; appearance preference; --tab launch arg
│   │   ├── Dashboard/  (DashboardView, SpendingSummaryCard, QuickCashButton)
│   │   ├── Expenses/   (ExpensesView, ExpenseDetailView, EditExpenseView, ExpenseRowView, FilterBarView, PaymentLogoView)
│   │   ├── AddExpense/ (AddExpenseView)
│   │   ├── Review/     (ExpenseReviewView)
│   │   ├── PayBook/    (PayBookView, PayBookDetailView, AddPayBookContactView, EditPayBookContactView)
│   │   ├── Analytics/  (AnalyticsView)
│   │   └── Settings/   (SettingsView, ParserSelfTestView)
│   ├── ShareExtension/
│   │   ├── ShareViewController.swift       UIKit principal class; multi-strategy image loading; shareLog
│   │   ├── ShareExtensionView.swift        ViewModel + SwiftUI phases; saves to shared store
│   │   ├── Info.plist                      NSExtensionActivationRule (image UTIs), principal class
│   │   └── ShareExtension.entitlements     App Group
│   ├── Resources/
│   │   ├── Assets.xcassets                 AppIcon (1024²), AccentColor (light/dark), 5 provider logos
│   │   ├── DiagnosticSamples/              sample_screenshot.png, sample_photo.jpg, sample_camera.heic
│   │   ├── Info.plist                      Display name, camera/photo usage strings, portrait only
│   │   └── SpenDrop.entitlements           App Group
│   └── Utils/
│       ├── CurrencyFormatter.swift         "RM 12.50" formatting and lenient parsing
│       └── HapticFeedback.swift            impact / notification / selection helpers
├── scripts/
│   └── generate_xcodeproj.py               Regenerates project.pbxproj with deterministic IDs
├── docs/
│   ├── SPENDROP_DOCUMENTATION.md           This document
│   └── screenshots/                        Simulator captures taken 2026-09-25
├── README.md
└── .gitignore                              Xcode user data, DerivedData, build products
```

Notes on maintainability:

- There is **no shared framework**. The engine files are listed in both targets' compile sources (see `share_source_paths` in the generator script). This avoids a framework but means every new shared file must be added to both targets; commit `0008dfb` fixed exactly that omission for `SampleData.swift`.
- `DerivedData/` sits inside the repository folder but is git-ignored.

---

## 9. Features

### 9.1 Quick Cash / Manual Expense Entry

**Purpose:** record a cash or card expense in a few taps.

**How it works:** `AddExpenseView` shows a hero amount field (decimal keypad), four increment chips (+RM5/+RM10/+RM20/+RM50) that add to the current value, a horizontal payment-source picker over all 16 `PaymentSource` cases, a 12-category grid, a merchant text field with seven quick chips that also pre-select a category (e.g. "Grab" → Transport), a date/time picker and an optional description.

**User flow:**
1. Tap "Quick Cash" (Dashboard header, empty state, or "+" toolbar).
2. Enter or chip-build the amount.
3. Optionally pick source, category, merchant, date, notes.
4. Tap "Save Expense" (disabled until amount > 0).

**Technical implementation:** `Expense(amount:currency:merchant:category:paymentSource:date:notes:sourceType:)` inserted into `modelContext`; empty merchant becomes "Food / Dining" when category is Food, else "Unknown".

**Validation:** `isValid = parsedAmount > 0` using `CurrencyFormatter.parse` (strips RM/MYR/commas). Save button disabled otherwise.

**Security:** none needed (local).

**Evidence:** `Views/AddExpense/AddExpenseView.swift`; screenshot `01_dashboard.png` shows the Quick Cash button.

### 9.2 Screenshot / Receipt Import from Photos

**Purpose:** parse a payment screenshot without leaving the app.

**How it works:** `PhotosPicker` (Dashboard header icon, Dashboard empty state, and top card in Add Expense). On selection an 8-stage pipeline runs on the main actor: load `Data` → decode `UIImage` → obtain `CGImage` (with `CIImage` fallback) → downsampling check → temp-file write test → App Group write/delete test → `OCRService` → `TransactionParser`. Each stage logs with a `[SpenDrop][IMAGE]` prefix and fails to a user alert naming the stage.

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
- `shareLog()` writes every step to stdout, `NSLog`, and an append-only file in the App Group; the main app prints that file when launched with `--read-share-logs`.

**Evidence:** `ShareExtension/*`, tests "Persistence Lifecycle & Duplicate Verification"; the build produced `SpenDrop.app/PlugIns/SpenDropShare.appex`.

### 9.6 Duplicate Detection

**Purpose:** prevent the same payment being stored twice.

**How it works:** `DuplicateDetector.checkDuplicate(amount:merchant:date:reference:in:)` fetches up to 10 expenses with the identical amount within ±48 h of the target date (`#Predicate`), then applies three rules in order: identical transaction reference; same merchant (substring match either way, ignoring "unknown") on the same calendar day; any candidate within one hour. Returns `DuplicateCheckResult { isDuplicate, matchedExpense, reason }` with a human-readable reason used in the alert.

**Evidence:** `Data/DuplicateDetector.swift`; tests "Duplicate Detection (Identical Transaction)", "Unique Transaction (Non-Duplicate)", "Persistence Lifecycle & Duplicate Verification".

### 9.7 Expense History

**Purpose:** browse and manage all expenses.

**How it works:** `ExpensesView` uses `@Query(sort: \Expense.date, order: .reverse)`. Search matches merchant, category, payment source, notes, or the amount formatted to two decimals. `FilterBarView` provides "All", "Cash Only", "TNG" and one chip per category (toggle on/off). Results are grouped into "Today", "Yesterday", or a medium date string, sorted newest first. Swipe-to-delete with full swipe.

**Empty states:** "No expenses recorded" vs "No matching expenses".

**Evidence:** `Views/Expenses/ExpensesView.swift`, `FilterBarView.swift`; screenshot `02_expenses.png`.

### 9.8 Expense Detail, Edit and Delete

- `ExpenseDetailView`: hero (category icon, amount, merchant), rows for category, payment method (with provider logos and "Apple Pay • Bank"), date, time, source type, reference (if any), notes, original image (loaded from disk), Delete with confirmation alert, Edit button.
- `EditExpenseView`: amount, merchant, wheel category picker, menu payment picker, date, notes; sets `updatedAt`. Save disabled unless amount > 0.

**Evidence:** `Views/Expenses/ExpenseDetailView.swift`, `EditExpenseView.swift`.

### 9.9 Dashboard

Totals computed in memory from `@Query`: today (`isDateInToday`), this week (`dateInterval(of: .weekOfYear)`), this month (`dateInterval(of: .month)`). Shows today's list (tap → detail) and up to five recent non-today expenses. Month/year banner, Quick Cash, screenshot picker, "+" toolbar.

**Evidence:** `Views/Dashboard/DashboardView.swift`; screenshot `01_dashboard.png` (sample data: Today RM 57.30, Week RM 265.50, Month RM 749.60).

### 9.10 Analytics

Segmented period selector (This Month / Last 30 Days / All Time). Metric cards: total spent, average per transaction, top category, top payment. Donut chart (`SectorMark`, inner radius 0.6) of category totals with percentage rows; horizontal bar chart (`BarMark`) of payment sources with counts; top six merchants. Empty state when the period has no expenses.

**Evidence:** `Views/Analytics/AnalyticsView.swift`; screenshot `04_analytics.png`.

### 9.11 PayBook (payment contact book)

**Purpose:** keep bank-transfer payee details at hand.

**How it works:**
- `PayBookContact` stores name, bank, account holder, account number, optional phone; all fields trimmed in `init`, empty phone → `nil`.
- List sorted by name, searchable by name (case-insensitive contains), subtitle shows `bank ••••last4` (masking only when more than four alphanumerics), swipe or button delete with confirmation.
- Detail shows full account number in monospaced font with `.textSelection(.enabled)` and a Copy button that writes to `UIPasteboard.general`, shows "Copied" for two seconds, and fires a success haptic.
- Add/Edit forms require name, bank, holder and account number; duplicate check compares lower-cased bank and alphanumeric-only account number against all contacts and offers "Save Anyway".
- Launch arguments `--seed-paybook`, `--clear-paybook`, `--open-add`, `--open-detail <name>`, `--open-edit`, `--demo-copied`, `--demo-duplicate` exist for demos and UI automation.

**Evidence:** `Models/PayBookContact.swift`, `Views/PayBook/*`, `ExpenseDataContainer.handlePayBookLaunchArguments`; tests 43–48; screenshots `03_paybook.png`, `06_paybook_detail.png`.

### 9.12 Settings

Preferences (default currency — stored but unused elsewhere; appearance system/light/dark applied via `preferredColorScheme`), Data & Device Testing (count, Load Sample Transactions, Run OCR & Parser Self-Test, Clear All Expenses with confirmation), Privacy & Security statement, About rows.

**Evidence:** `Views/Settings/SettingsView.swift`; screenshot `05_settings.png`.

### 9.13 In-App Self-Test Runner and Diagnostics

- `ParserSelfTestView` runs `TransactionParserTests.runAllTests()` on appear and on demand, listing each case with pass/fail, details and actual value.
- Launching with `--run-tests` runs the same suite at startup, prints `[TEST] [PASS|FAIL] …` lines and `[TEST_RUN_SUMMARY] n/m PASSED`, and exits with code 0/1 — usable from `xcrun simctl launch --console-pty`.
- `--run-image-diagnostics` runs `ImagePipelineDiagnostics` over three bundled samples (PNG, JPEG, HEIC) through eight steps (data load, UIImage, CGImage, downsample, temp write, App Group write/read, OCR, parser).

**Evidence:** `OCR/TransactionParserTests.swift`, `OCR/ImagePipelineDiagnostics.swift`, `App/SpenDropApp.swift`; verified run on 2026-09-25.

### 9.14 Receipt Image Storage

`ImageStorageService` writes JPEG (quality 0.8) named `<uuid>.jpg` into `SpenDropReceipts/` in the App Group (falls back to Documents), loads by relative path (with Documents fallback), and deletes. `Expense.imageRelativePath` holds the filename. Deleting an `Expense` does **not** delete its image file (verified: no call to `deleteImage` in delete paths).

### 9.15 Sample Data Seeding

`SampleData.seed` inserts 18 realistic Malaysian expenses spread over today / this week / this month, flagged `isSampleData = true`, and is idempotent (skips if any sample record exists). First-launch seeding is additionally guarded by the `UserDefaults` key `has_seeded_initial_sample_data_v1`.

---

## 10. User Workflows

**Share-sheet capture (primary):**
```
User pays → takes screenshot → Share → "SpenDrop"
  → ShareViewController attaches UI ("Receiving screenshot…")
  → NSItemProvider image load (3 strategies) → downsample 1280
  → "Reading payment details…" (Vision OCR, background task)
  → TransactionParser → DuplicateDetector (shared store)
  → Review form (banner + editable fields)
  → [duplicate?] alert Add Anyway / Cancel
  → Save → Expense + JPEG in App Group → completeRequest
  → Main app: @Query refreshes Dashboard / Expenses / Analytics on next appearance
```

**In-app screenshot capture:**
```
Dashboard or Add Expense → PhotosPicker → 8-stage pipeline
  → ExpenseReviewView (sheet) → Save → dismiss
  → on failure: alert "Couldn't read this image" → Try Again | Add Manually
```

**Manual entry:**
```
Quick Cash → AddExpenseView → amount (keypad/chips) → optional fields → Save (amount > 0)
  → modelContext.insert + save → haptic → dismiss
```

**Edit / delete:**
```
Expenses list → row → ExpenseDetailView → Edit → EditExpenseView → Save (updatedAt set)
                                         → Delete → confirm alert → delete + save
Expenses list → swipe left → Delete (no confirmation)
```

**PayBook:**
```
PayBook tab → "+" → form (4 required) → Save
  → duplicate (bank + account) ? alert "Save Anyway" : insert
PayBook tab → search name → row → detail → Copy (pasteboard, 2 s "Copied")
                                          → Edit → form → Save
                                          → Delete → confirm alert
```

**Verification:**
```
Settings → Run OCR & Parser Self-Test → 48 cases run on device → pass/fail list
CLI: xcrun simctl launch --console-pty <sim> com.spendrop.SpenDrop --run-tests
```

There is no login or admin workflow (see §13).

---

## 11. Database

| Item | Detail |
|---|---|
| Technology | SwiftData (Apple), backed by SQLite. The container is configured with `ModelConfiguration(schema:groupContainer: .identifier("group.com.spenddrop.shared"))`, which places the store at `Library/Application Support/default.store` inside the App Group container. The App Group identifier is the one the app used before it was renamed; it is kept on purpose so existing installs reopen their data (see §19 C12). Falls back to the default store if the container cannot be opened, then to `fatalError`. |
| Schema declaration | `Schema([Expense.self, PayBookContact.self])` in `ExpenseDataContainer.shared`; a separate in-memory `previewContainer` is seeded with sample data for SwiftUI previews. |
| Migrations | None defined (no `VersionedSchema` / `SchemaMigrationPlan`). Schema changes rely on SwiftData lightweight migration. Not verified beyond absence. |
| Indexes | None declared explicitly. `@Attribute(.unique)` on `id` for both models implies a uniqueness constraint. |
| Relationships | **None.** `Expense` and `PayBookContact` are independent (verified by test "PayBook: Data Isolation from Expenses"). |

### 11.1 `Expense`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | primary key, `@Attribute(.unique)` |
| `amount` | Double | > 0 enforced in UI only |
| `currency` | String | always "RM" in practice |
| `merchant` | String | trimmed; empty → "Unknown" |
| `categoryRaw` | String | raw value of `ExpenseCategory` (12 values) |
| `paymentSourceRaw` | String | raw value of `PaymentSource` (16 values) |
| `underlyingBankRaw` | String? | bank behind Apple Pay, or the bank itself for CIMB/Maybank/RHB |
| `paymentMethodRaw` | String? | `ewallet`, `digital_wallet`, `bank_transfer`, `card`, `qr_code`, `cash`, `duitnow`, `duitnow_qr`, `unknown` |
| `date` | Date | transaction time |
| `notes` | String? | trimmed; empty → nil |
| `transactionReference` | String? | from OCR |
| `imageRelativePath` | String? | filename in `SpenDropReceipts/` |
| `sourceTypeRaw` | String | `manual`, `screenshot`, `photo`, `receipt`, `shareExtension` |
| `ocrText` | String? | full OCR text (in-app import only; the extension stores nil) |
| `confidence` | Double? | 1.0 / 0.7 / 0.4 mapped from `ParsingConfidence` |
| `isSampleData` | Bool | seeding flag |
| `createdAt`, `updatedAt` | Date | `updatedAt` refreshed by `EditExpenseView` |

### 11.2 `PayBookContact`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | primary key, unique |
| `name` | String | required, trimmed |
| `bankName` | String | required, trimmed |
| `accountHolderName` | String | required, trimmed |
| `accountNumber` | String | required, trimmed, **stored in plain text** |
| `phoneNumber` | String? | optional, empty → nil |
| `createdAt`, `updatedAt` | Date | |

### 11.3 Relationship diagram

```
┌──────────────────────┐          ┌──────────────────────┐
│ Expense              │          │ PayBookContact       │
│ id (PK, unique)      │          │ id (PK, unique)      │
│ amount, currency     │   (no    │ name, bankName       │
│ merchant, category…  │ relation)│ accountHolderName    │
│ imageRelativePath ───┼──┐       │ accountNumber, phone │
└──────────────────────┘  │       └──────────────────────┘
                          ▼
              SpenDropReceipts/<uuid>.jpg  (file system, App Group)
```

### 11.4 Business logic living near the data layer

- Idempotent seeding (`SampleData.seed`, `seedInitialDataIfNeeded`).
- Duplicate detection query (`DuplicateDetector`).
- Enum bridging via computed properties so raw strings never leak into views.

No passwords, keys or tokens are stored.

---

## 12. APIs

**There are no HTTP/network APIs.** The app neither exposes nor consumes any web endpoint (verified: no `URLSession`, `URLRequest`, or networking imports in the source).

The internal, in-process interfaces that act as the app's "API" are:

| Interface | Signature | Purpose |
|---|---|---|
| `OCRService.shared.recognizeText(from:)` | `async throws -> OCRResult` | Vision OCR |
| `TransactionParser.shared.parse(ocrResult:image:)` | `-> ParsedTransaction` | full parse |
| `TransactionParser.extractAndClassifyAmounts(...)` | `-> (amount, confidence, currency, [MonetaryCandidate])` | amount engine |
| `PaymentProviderDetector.detect(lines:fullText:)` | `-> ProviderDetectionResult` | provider |
| `MerchantDetector.detect(lines:fullText:)` | `-> (merchant?, category?)` | merchant |
| `CategoryDetector.detect(text:detectedMerchant:merchantCategory:)` | `-> ExpenseCategory` | category |
| `DuplicateDetector.shared.checkDuplicate(amount:merchant:date:reference:in:)` | `-> DuplicateCheckResult` | duplicates |
| `ImageStorageService.shared.saveImage/loadImage/deleteImage` | | receipt files |
| `ParsedTransaction.toNormalizedDictionary()` | `-> [String: Any]` | stable export shape |

**Launch-argument "CLI" (process arguments read at startup):**

| Argument | Effect |
|---|---|
| `--run-tests` | run 48 tests, print results, exit 0/1 |
| `--run-image-diagnostics` | run PNG/JPEG/HEIC pipeline diagnostics and print report |
| `--read-share-logs` | print the extension's App Group log |
| `--tab <0–4>` | open a specific tab |
| `--seed-paybook`, `--clear-paybook` | seed / clear PayBook contacts |
| `--open-add`, `--open-detail <name>`, `--open-edit`, `--demo-copied`, `--demo-duplicate` | PayBook UI states for demos/automation |

---

## 13. Authentication & Authorization

- **Authentication:** none. SpenDrop is a single-user, on-device app with no accounts, sessions or tokens. The Settings screen explicitly states that the app never asks for bank logins, passwords, OTPs or PINs. (Verified.)
- **Authorization:** none at the application level. The iOS sandbox and App Group entitlement (`com.apple.security.application-groups` = `group.com.spendrop.shared`) are the only access-control boundaries: only the two signed targets can read the store and images.
- **Roles / admin / protected routes / middleware:** not applicable.
- **OS permissions:** `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` strings exist in `Info.plist`. The photo library is accessed through `PhotosPicker`, which does not require the full-library permission. No camera capture code was found, so the camera string is currently unused. (Verified.)
- **Device-level protection (Face ID / passcode lock for the app):** not implemented.

---

## 14. Security Review

| Area | Finding | Classification | Evidence |
|---|---|---|---|
| Network exposure | No networking code; no endpoints | Implemented (by absence) | source grep |
| Secrets in repo | No API keys, tokens or `.env` files. The Apple Development Team ID is present in `project.pbxproj` (`DEVELOPMENT_TEAM`); this is not a secret but is identifying, so it is redacted here. | Implemented | `project.pbxproj` |
| Data at rest | SwiftData store and JPEGs in the App Group container rely on default iOS Data Protection; no additional encryption | Needs improvement (acceptable for personal use; account numbers are sensitive) | `ExpenseDataContainer`, `ImageStorageService` |
| PayBook account numbers | Stored and displayed in plain text; masked only in the list; copied to the system pasteboard without expiry (`UIPasteboard.general.string =`) | Needs improvement: consider `setItems(_:options: [.expirationDate])` and `localOnly` | `PayBookDetailView.copyAccountNumber` |
| Diagnostic logging | `shareLog` appends to `share_extension_diagnostics.log` forever (no rotation) and logs merchant + amount on save; `[SpenDrop][IMAGE]` prints the first five OCR lines to the console | Needs improvement: gate behind `#if DEBUG`, rotate/trim log | `ShareViewController.swift:6-32`, `ShareExtensionView.swift:685`, `DashboardView.swift:417` |
| Input validation | Amount must be > 0; PayBook required fields; merchant/notes trimmed; account numbers normalised for comparison | Implemented | views and model inits |
| Injection | `#Predicate` macros are type-checked; no string-built queries; no SQL | Implemented | `DuplicateDetector`, `SampleData` |
| XSS / CSRF / rate limiting / security headers / HTTPS | Not applicable (no web surface) | N/A | — |
| File handling | Only image files decoded via `UIImage(data:)`; security-scoped URLs are started/stopped correctly | Implemented | `loadViaLoadItem` |
| Extension memory safety | Downsampled to 1280 px, `format.scale = 1.0`, `autoreleasepool` | Implemented | `OCRService`, `ShareViewController` |
| Error swallowing | `try? modelContext.save()` in Add/Edit/Delete/Review/Settings/PayBook; a failed save is silent | Needs improvement | multiple views |
| Hard-coded developer path | `ImagePipelineDiagnostics` contains a fallback absolute path under the developer's home directory | Needs improvement (dev-only artefact) | `ImagePipelineDiagnostics.swift:63` |
| Bundled sample images | Until 2026-09-25 two of the three diagnostic samples contained real data (a photographed third-party delivery order with an account number and signature, and a photo of an identifiable person). Both were replaced with script-rendered synthetic images with the same filenames, and the two original files were removed from the unpushed local commits before the repository was pushed, so they never reached GitHub. | Fixed | `Resources/DiagnosticSamples/`, `docs/screenshots/case-study/README.md` |
| Dependency risk | Zero third-party dependencies | Implemented | — |
| App lock | No biometric/passcode gate | Not implemented | — |

The system should not be described as "fully secure". Its threat model is a personal device with the iOS sandbox as the boundary.

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

| Situation | Behaviour | Evidence |
|---|---|---|
| Invalid amount | Save button disabled; review screens show "Tap to enter amount" / "Enter amount to save" in red | all forms |
| OCR cannot decode image / no text / Vision failure | `OCRError` with localized descriptions; in-app: alert "Couldn't read this image" with the failing stage and "Try Again" / "Add Manually"; extension: `noTextFound` phase with manual entry and retry | `OCRService`, `DashboardView.handleImportFailure`, `ShareExtensionView` |
| No input item / attachments in Share Sheet | `error` phase with message and Cancel | `ShareViewController.loadImageAsync` |
| Image load fails across all strategies | `NSError` domain `com.spendrop.share` code -1 → `error` phase | `extractImageWithFallback` |
| App Group container unavailable | store falls back to default location; images fall back to Documents | `ExpenseDataContainer`, `ImageStorageService` |
| `ModelContainer` creation fails | second attempt with default config, then `fatalError` | `ExpenseDataContainer` |
| Duplicate detected | banner + confirm alert | review screens, PayBook forms |
| Destructive actions | confirmation alerts for expense delete (detail), contact delete, clear all; swipe-delete on expenses has none | views |
| Persistence save failure | mostly `try?` (silent); the extension logs the error via `shareLog` | see §14 |
| Empty data | dedicated empty states on Dashboard, Expenses (two variants), Analytics, PayBook (two variants), self-test list | views |
| Loading | dimmed overlay with spinner and "Reading transaction..." (app); phase views (extension) | views |
| User cancels extension | `cancelRequest(withError: NSUserCancelledError)` | `ShareViewController` |

---

## 17. UI / UX

- **Structure:** five-tab `TabView` (Dashboard, Expenses, PayBook, Analytics, Settings), each in its own `NavigationStack`; creation and editing happen in sheets; PayBook detail is a push.
- **Visual language:** system grouped backgrounds, rounded cards (16–20 pt continuous corners), SF Symbols, rounded-design numerals for amounts, brand-coloured capsules for payment sources, custom logo assets for five providers, category colours reused in charts.
- **Dashboards:** summary cards + lists (Dashboard), metric cards + charts (Analytics).
- **Forms:** custom card-style forms for expenses; native `Form` for PayBook.
- **Tables/lists:** `List` with sections (`insetGrouped`), swipe actions, searchable bars.
- **Responsive behaviour:** SwiftUI layout adapts to iPhone widths; iPhone-only target, portrait only (`UISupportedInterfaceOrientations`). iPad and landscape are not supported.
- **Loading / empty / error states:** present on every screen (see §16).
- **Dark mode:** system appearance respected; `AccentColor` has a dark variant; user can force light/dark in Settings.
- **Haptics:** impact on primary actions, selection on chips, notification on success/warning/error.
- **Accessibility:** relies on system components (Dynamic Type, VoiceOver labels from `Label`/`Text`). No custom accessibility modifiers, no explicit testing. Not verified.

**Screenshots (iPhone 17 Simulator, iOS 27.0, 2026-09-25, sample data loaded):**

| File | Screen |
|---|---|
| `docs/screenshots/01_dashboard.png` | Dashboard with Today/Week/Month totals and today's list |
| `docs/screenshots/02_expenses.png` | Expenses history with filter chips and day grouping |
| `docs/screenshots/03_paybook.png` | PayBook list with masked account numbers |
| `docs/screenshots/04_analytics.png` | Analytics metric cards and category donut |
| `docs/screenshots/05_settings.png` | Settings |
| `docs/screenshots/06_paybook_detail.png` | Payee detail with Copy button |

**Case-study set (2026-09-25, fresh iPhone 17 Simulator, synthetic data only):** `docs/screenshots/case-study/` holds nine frames plus an architecture diagram, each documented with purpose, caption and verification status in `docs/screenshots/case-study/README.md`. They include the Share Sheet with SpenDrop, the Share Extension review after OCR ("Payment Detected"), the in-app review with the "POSSIBLE AMOUNTS" candidate row, the duplicate-protection alert, and the on-device test runner showing 48/48. They were produced with temporary launch-argument hooks (recorded in `capture-hooks.patch` and reverted afterwards) because the Share Sheet cannot be driven by script on this machine.

---

## 18. Development Process

Reconstructed from `git log` (19 commits, one author, 2026-09-16 → 2026-09-18) plus the uncommitted working tree.

| Phase | Date | Commits | What was built |
|---|---|---|---|
| **Milestone 1 — Core tracker** | 2026-09-16 | `b2ec656` .gitignore → `95d3a7b` SwiftData model → `feb1513` manual cash entry → `dea5b44` history + dashboard → `b3aa40e` analytics, settings, app shell → `094e618` Xcode project, resources, README | Models, all main tabs, sample data, project generator |
| **Milestone 2 — OCR & parser** | 2026-09-16 | `9c9e76e` Vision OCR + Malaysian parser (7 files, +1,094) → `1da3d87` review screen + self-test runner → `2c68234` project/README update | `OCRService`, `TransactionParser`, `MerchantDetector`, `CategoryDetector`, `ExpenseReviewView`, `ParserSelfTestView` |
| **Milestone 3 — Share Extension** | 2026-09-17 | `aead78c` target + entitlements → `76b5f0e` App Group persistence + `DuplicateDetector` → `9c6753c` extension wired to OCR/review (+581) → `034c099` extension/duplicate tests → `74e6f42` project/README → `0008dfb` fix `SampleData` target membership + automatic signing → `37effa6` 18 sample expenses → `26595a0` fix SwiftData import in tests | `SpenDropShare`, shared container, duplicate protection |
| **Extraction overhaul** | 2026-09-18 | `20d06c8` "master bug fix, payment extraction overhaul, provider logos, and 42 simulator tests" (44 files, +3,979 / −705) | `PaymentProviderDetector`, `MonetaryCandidate`, `ImagePipelineDiagnostics`, provider logo assets, `PaymentLogoView`, real-reference tests, negative amounts, ad exclusion, sender/recipient logic |
| **PayBook V1** | 2026-09-18 (branch `feature/paybook`) | `efd5f99` (11 files, +977) | `PayBookContact`, four PayBook views, seeding/launch args, six PayBook tests |
| **Uncommitted (2026-09-25)** | — | Xcode 27 re-saved `project.pbxproj` and schemes (`LastUpgradeVersion 2700`, share scheme now launches via SpringBoard); project renamed to SpenDrop | this documentation and screenshots added |

Observations:

- Commit messages are descriptive and milestone-oriented; the last two use conventional-commit prefixes (`fix:`, `feat(paybook):`).
- Two small fix commits (`0008dfb`, `26595a0`) show real compile issues found when the second target was introduced.
- The whole codebase was written in three calendar days; the git timestamps are the only timeline evidence.
- No tags, no pull requests, no CI configuration.

---

## 19. Challenges & Solutions

Each item is grounded in code, tests or commits. Where the *history* of the problem is inferred from comments rather than observed, it is labelled.

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
- **Result:** the renamed app reopens the existing store on the device without any data copy. Both targets still build; 48/48 tests pass.
- **Lesson:** storage identifiers are part of a product's contract with its users. A rename that touches them needs a migration or, as here, a decision to keep them.

### C11 — Testing without a Mac in the loop
- **Solution:** tests are plain Swift functions compiled into the app and runnable from Settings or via `--run-tests` with a process exit code, instead of an XCTest bundle.
- **Trade-off:** no Xcode test navigator integration, no code coverage; test code ships in the binary.

---

## 20. Testing & Verification

### 20.1 Automated tests (in-app suite, run 2026-09-25 on iPhone 17 Simulator, iOS 27.0)

| Group | Tests | Expected | Actual | Status | Evidence |
|---|---|---|---|---|---|
| Provider/merchant end-to-end parsing | TNG McDonald's; Maybank MYDIN; CIMB Shell; Apple Pay Starbucks; QR unknown merchant; Receiver/Payee name; Malaysian bank auto-detection; Unknown provider extraction | fields match | match | ✅ 8/8 | `--run-tests` output |
| Amount selection | Receipt total > subtotal; RM22 vs RM450 ad; RM51 total priority; RM50 over fee/balance; Low-confidence flagging; Normalized model | correct amount/flags | correct | ✅ 6/6 | same |
| False positives | Account balance; Credit limit; Reward points; Failed payment | no expense / flagged | as expected | ✅ 4/4 | same |
| Duplicates & persistence | Identical transaction; Unique transaction; Persistence lifecycle; Consecutive RM10/25/50; Idempotent seeding | detect / not detect / persist | as expected | ✅ 5/5 | same |
| Provider detection unit cases | TNG; Maybank/MAE; CIMB; RHB; Apple Pay standalone; +CIMB; +Maybank; Unknown fallback; Logo assets present | provider + bank | as expected | ✅ 9/9 | same |
| Real-reference screenshots | CIMB QR (ads); CIMB FPX notification; CIMB→Maybank; Maybank→RHB; Maybank Scan & Pay; RHB→CIMB; RHB DuitNow QR; TNG −RM12.00; TNG interbank (ads); TNG QR RM0.01 | amount, sender, merchant | as expected | ✅ 10/10 | same |
| PayBook | Masking & subtitle; Persistence CRUD; Duplicate logic; Name search; Isolation from expenses; Trimming & phone normalisation | as named | as expected | ✅ 6/6 | same |
| **Total** | | | | **48/48 PASSED** | `[TEST_RUN_SUMMARY] 48/48 PASSED` |

Notes: the suite uses synthetic OCR text (`makeOCRResult(text:)`), so it verifies the **parser**, not Vision's recognition quality. Persistence tests run against the real shared container.

### 20.2 Build verification

| Test | Expected | Actual | Status | Evidence |
|---|---|---|---|---|
| `xcodebuild … -scheme SpenDrop build` (Debug, simulator, signing disabled) | both targets compile; appex embedded | `** BUILD SUCCEEDED **`; `SpenDrop.app/PlugIns/SpenDropShare.appex` present | ✅ | build log 2026-09-25 |
| Compiler warnings | 0 | 4 (unused `statusDisplayText`; unreachable `catch`; unused loop var `i`; `var lastError` never mutated) | ⚠️ non-blocking | build log |
| Rename completeness | no "SpendDrop"/"spenddrop" left in user-facing names, targets, schemes, bundle IDs, plists, scripts, README | 0 occurrences apart from the deliberately retained App Group identifier and receipts folder name | ✅ | grep 2026-09-25 |

### 20.3 Diagnostics

`--run-image-diagnostics` exercises PNG/JPEG/HEIC decode, downsampling, temp and App Group storage, OCR and parser on three bundled synthetic images. Run on 2026-09-25 after the samples were replaced: Vision OCR and Parser passed for all three (PNG: RM18.50 McDonald's Food, High; JPEG and HEIC: RM19.08 Mamak Food, High).

### 20.4 Manual / device testing

The README describes manual testing on iPhone 17 Pro Max and 16 Pro Max, including the Share Sheet flow and duplicate warning. No test logs or recordings exist in the repository. **Not verified from the available project files.**

### 20.5 Not covered

No XCTest/XCUITest targets, no UI automation suite (although launch arguments for UI states exist), no accessibility audit, no performance benchmarks.

---

## 21. Deployment

| Item | Detail |
|---|---|
| Hosting / domain / DNS / HTTPS / CDN | Not applicable (no server) |
| Build process | Open `SpenDrop.xcodeproj`, select scheme `SpenDrop`, run. Command line: `xcodebuild -project SpenDrop.xcodeproj -scheme SpenDrop -destination 'platform=iOS Simulator,name=iPhone 17' build` |
| Signing | `CODE_SIGN_STYLE = Automatic` with a development team set in the project; App Groups capability required on both targets. Device builds need the App Group `group.com.spenddrop.shared` registered to the team; automatic signing registered it for the new bundle identifiers on 2026-09-25. |
| Bundle identifiers | `com.spendrop.SpenDrop` (app), `com.spendrop.SpenDrop.ShareExtension` (extension). These changed with the rename, but the App Group identifier did not, so a device that had the old app installed reopens the same store from the new app (verified on the developer's iPhone 17 Pro Max and on the simulator, 2026-09-25). |
| Environment variables / secrets | None used |
| Environments | Debug and Release configurations only; no staging concept |
| Database deployment | Created on first launch by SwiftData in the App Group container |
| CI/CD | None (no `.github/workflows`, fastlane config absent though ignored in `.gitignore`) |
| Distribution | No App Store / TestFlight / ad-hoc artefacts in the repository. Not verified. |
| Production infrastructure | Not applicable |

---

## 22. Current Status

### Completed (verified)
- Manual expense entry, history, detail/edit/delete, dashboard, analytics, settings.
- Vision OCR + Malaysian transaction parser with provider, merchant, category, date/time, reference, status and confidence.
- Amount candidate classification with ad/balance/fee/cashback/discount exclusion.
- Review screen with candidate chips and duplicate confirmation.
- Share Extension with shared App Group store, five UI phases, manual fallback, diagnostics log.
- Duplicate detection.
- PayBook V1 (list, search, masking, copy, add/edit/delete, duplicate alert).
- 48 in-app tests passing; CLI test hook; image pipeline diagnostics.
- Project renamed to SpenDrop (2026-09-25) and verified to build and pass tests on simulator and on an iPhone 17 Pro Max, reopening the pre-rename data.
- Real-data diagnostic sample images replaced with synthetic ones; image-pipeline diagnostics pass on all three.
- Case-study screenshot set captured and documented.

### In progress
- `feature/paybook` branch is not merged into `master`.
- Nothing outstanding on the branch after the 2026-09-25 commits.

### Pending (not present in the code; suggestions only)
- Nothing is formally planned in the repository. See §23.

### Known limitations
- Currency preference is stored but not applied; all amounts are RM.
- Camera capture is not implemented although the usage string exists.
- Deleting an expense leaves its receipt JPEG on disk.
- Swipe-delete in the history has no confirmation.
- Persistence errors are swallowed with `try?`.
- Extension log grows without bound and contains transaction details.
- Parser is keyword-driven; unseen layouts fall back to "Unknown" with low confidence.
- On column-aligned paper receipts Vision can return the label ("TOTAL") and the amount as separate observations; the total then loses its label and a line item may be selected, with the review screen correctly showing "Possible Expense Detected". Observed 2026-09-25 with a synthetic receipt.
- The AM/PM token was not carried through on one synthetic screenshot (9:42 PM read as 9:42 AM). Observed 2026-09-25.
- iPhone-only, portrait-only, English UI only.
- No schema migration plan; changing `@Model` properties may require reinstall.
- Tests live in the app binary rather than a test target.
- The repository folder on the developer's disk still uses the old name "SpendDrop"; the GitHub repository was renamed.

---

## 23. Future Improvements

| Priority / Area | Proposed improvement | Reason |
|---|---|---|
| High / Data safety | Replace `try? save()` with handled errors and user feedback | silent data loss is possible today |
| High / Privacy | Gate diagnostic logging behind `#if DEBUG`; rotate or cap `share_extension_diagnostics.log`; avoid logging amounts/merchants | logs persist in the App Group |
| High / Security | Copy account numbers with `UIPasteboard.setItems(_:options:)` using `expirationDate` and `localOnly`; consider Face ID lock for PayBook | account numbers are sensitive |
| Medium / Architecture | Move Models, Data and OCR into a Swift Package or framework shared by both targets | removes duplicate target membership errors (cf. commit `0008dfb`) |
| Medium / Testing | Add an XCTest target that wraps `TransactionParserTests`; add fixture images for Vision-level regression | enables coverage and CI |
| Medium / CI | GitHub Actions running `xcodebuild build` and `--run-tests` on a simulator | catch regressions on push |
| Medium / Data | Delete receipt JPEG when its expense is deleted; add a `VersionedSchema` | disk growth, migrations |
| Medium / Feature | Apply the currency setting; add camera capture (string already present) | complete existing UI |
| Medium / Parser | Externalise keyword lists and merchant table to JSON; add confidence calibration data | maintainability |
| Low / UX | Confirmation for swipe delete; iPad/landscape layouts; localisation (Bahasa Malaysia) | polish |
| Low / Housekeeping | Fix the four compiler warnings; remove the hard-coded developer path; rename the GitHub repository and local folder to SpenDrop | cleanliness |

---

## 24. Case Study

### The Problem
Recording daily spending in Malaysia means juggling cash, several e-wallets, multiple bank apps, DuitNow QR and Apple Pay. Each app shows a confirmation screen, but none of them export to a single ledger. People screenshot receipts and rarely transcribe them, so the data is lost. Cloud receipt scanners exist, but they send financial screenshots off-device.

### The Goal
Build an iPhone app where a payment screenshot becomes a saved, categorised expense in two taps, with all processing on the device, tuned to Malaysian formats and providers.

### The Approach
1. Start with a solid local-first tracker (SwiftData, SwiftUI) and realistic sample data.
2. Add Vision OCR and a deterministic, testable parser rather than a black-box model.
3. Make capture frictionless with a Share Extension sharing the same store via an App Group.
4. Harden extraction against real screenshots (ads, balances, interbank receipts, negative amounts) and encode each fix as an on-device test.
5. Extend with PayBook for the transfer-heavy use case.

### The Solution
A two-target iOS app (`SpenDrop`, `SpenDropShare`) with a shared OCR/parsing engine, a review-before-save workflow, duplicate protection, dashboard and analytics, and a payee book — 8,722 lines of Swift with zero third-party dependencies.

### Key Features
Screenshot-to-expense via Share Sheet or Photos; semantic amount classification; Malaysian provider detection with sender/recipient disambiguation and Apple Pay underlying bank; merchant/category inference; duplicate detection; dashboard, filters, charts; PayBook with masking and copy; 48 on-device tests.

### Technical Architecture
See §7: SwiftUI front end, SwiftData store in an App Group, Vision on a background task, rule-based parser producing a `ParsedTransaction`, identical engine compiled into app and extension.

### Challenges
Ad-price exclusion using bounding-box position; recipient-bank exclusion; balance/limit/points rejection; negative amounts; strict-weak-ordering sort crash; extension black screen and image loading; extension memory; two-process shared store. See §19.

### Results (verifiable)
- Debug build succeeds for both targets (2026-09-25).
- 48/48 in-app tests pass, including ten "real reference" screenshot cases.
- Six simulator screenshots demonstrate the UI with sample data.
- No network code; no dependencies.
- No user metrics, accuracy percentages or performance numbers exist. None are claimed.

### What I Learned
SwiftData with App Groups; Share Extension lifecycle and `NSItemProvider` quirks; Vision coordinate space and observation ordering; regex-based information extraction with semantic classification; designing tests that run on-device; deterministic Xcode project generation.

### Future Direction
Shared framework, XCTest + CI, safer persistence and logging, pasteboard hygiene, migrations, currency support, camera capture, localisation.

---

## 25. Skills Demonstrated

**Technical**
- Swift, Swift concurrency (`async/await`, `Task.detached`, `@MainActor`, cancellation)
- SwiftUI (navigation, sheets, alerts, searchable lists, swipe actions, custom components, Charts)
- SwiftData modelling, predicates, fetch limits, shared containers
- Apple Vision text recognition and coordinate handling
- UIKit interop (`UIHostingController`, `UIViewController` lifecycle) inside an app extension
- Regular expressions and heuristic text parsing (English + Bahasa Malaysia)

**Development**
- Multi-target Xcode project with shared sources and entitlements
- Scripted project generation (Python) with deterministic identifiers
- Launch-argument hooks for automation and demos
- Diagnostic logging strategy for extensions

**Database**
- Schema design for enum-backed fields, idempotent seeding, uniqueness constraints, in-memory preview containers

**Infrastructure**
- App Groups, entitlements, automatic signing configuration
- Simulator-based verification via `xcodebuild` and `simctl` (no CI yet)

**Security**
- Privacy-by-architecture (offline), sandbox boundaries, awareness of pasteboard and logging risks (documented as gaps)

**Problem Solving**
- Converting real-world screenshot failures into targeted rules and regression tests
- Spatial + lexical classification of numeric candidates
- Diagnosing extension-specific failures without direct console access

**Project Management**
- Milestone-based delivery in git (M1–M3, overhaul, PayBook) with descriptive commits and a feature branch

---

## 26. Portfolio Version

**Project title:** SpenDrop — On-device OCR expense tracker for Malaysian payments

**1-line description:** Share a payment screenshot to SpenDrop and it becomes a categorised expense, parsed entirely on your iPhone.

**Problem:** Malaysians pay through many apps (TNG, Maybank, CIMB, RHB, DuitNow, Apple Pay); nothing consolidates the confirmations, and cloud scanners compromise privacy.

**Solution:** A native SwiftUI app plus Share Extension that runs Apple Vision OCR and a custom rule-based parser to extract amount, merchant, provider, category, date and reference, rejects balances/ads/fees, flags duplicates, and stores everything in a local SwiftData store shared through an App Group.

**Key features:** Share Sheet capture · semantic amount classification · Malaysian provider detection (incl. sender vs recipient bank, Apple Pay + bank) · review-before-save · duplicate protection · dashboard, filters, Swift Charts analytics · PayBook payee book with masking and copy · 48 on-device tests.

**Tech stack:** Swift, SwiftUI, SwiftData, Vision, Swift Charts, PhotosUI, UIKit (extension), App Groups, Xcode. No third-party dependencies, no backend.

**My contribution:** Sole developer — architecture, data model, OCR/parsing engine, extension, UI, tests, project tooling.

**Challenges:** Ad-price and balance false positives, interbank sender/recipient ambiguity, negative amounts, Vision sort ordering, extension image loading and memory limits, cross-process persistence.

**Outcome / status:** Four milestones complete; builds and passes 48/48 tests on iOS 27 simulator (verified 2026-09-25). Not released.

**GitHub:** https://github.com/tirukon015/SpendDrop (to be renamed to SpenDrop)

**Live demo:** Not available (native iOS app; no store listing).

---

## 27. GitHub README Version

The repository `README.md` was rewritten to this structure on 2026-09-25 (see the file for the full text): Overview · Features · Tech Stack · Architecture · Project Structure · Installation · Environment Variables (none) · Running Locally · Database Setup (automatic) · API (none; internal interfaces and launch arguments) · Authentication (none) · Testing · Deployment · Screenshots · Known Limitations · Future Improvements · Project Status · License (none declared).

---

## 28. Evidence & Traceability

| Claim | Evidence | Location | Status |
|---|---|---|---|
| App renamed to SpenDrop everywhere | grep for old name returns 0 hits; targets, schemes, bundle IDs, App Group, display names updated | whole repo | Verified 2026-09-25 |
| Two targets, extension embedded | `PBXNativeTarget` entries; `Embed Foundation Extensions` phase; build output `PlugIns/SpenDropShare.appex` | `SpenDrop.xcodeproj/project.pbxproj` | Verified |
| iOS 17+, iPhone only, portrait | `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = 1`, `UISupportedInterfaceOrientations` | `project.pbxproj`, `Resources/Info.plist` | Verified |
| Version 1.3.0 | `MARKETING_VERSION = 1.3.0` | `project.pbxproj` | Verified |
| No networking / dependencies | no networking APIs; no SPM/Pods files | source tree | Verified |
| SwiftData in App Group | `ModelConfiguration(schema:url:)` with `group.com.spendrop.shared` | `Data/ExpenseDataContainer.swift` | Verified |
| Two models, no relationships | `@Model` classes; isolation test | `Models/`, test 47 | Verified |
| Vision OCR, accurate level, 3 languages | `VNRecognizeTextRequest` config | `OCR/OCRService.swift:62-65` | Verified |
| Row-band sort to avoid sort crash | comment + implementation | `OCR/OCRService.swift:81-95` | Verified (crash history inferred) |
| Amount semantic classification | `MonetarySemanticType`, rules 1–8 | `OCR/TransactionParser.swift:215-331`, `OCR/MonetaryCandidate.swift` | Verified |
| Negative amount support | regex with `[-–—]` | `OCR/TransactionParser.swift:144-148`; test 40 | Verified |
| Sender vs recipient bank logic | `recipientBankIds`, `fromAccountText` | `OCR/PaymentProviderDetector.swift:78-206`; tests 35–38 | Verified |
| Apple Pay underlying bank | `underlyingBank` fields | `PaymentProviderDetector.swift:35-76`, `Expense.underlyingBankRaw`; tests 28–30 | Verified |
| 56 known merchants | array count | `OCR/MerchantDetector.swift:10-78` | Verified |
| Duplicate detection rules | 48 h window, 3 rules | `Data/DuplicateDetector.swift` ; tests 11, 12, 21 | Verified |
| Share Extension accepts images | activation rule | `ShareExtension/Info.plist` | Verified |
| Three-strategy image loading | `loadViaLoadItem/DataRepresentation/FileRepresentation` | `ShareExtension/ShareViewController.swift:176-311` | Verified |
| Extension diagnostics log | `shareLog` + `--read-share-logs` | `ShareViewController.swift:6-32`, `App/SpenDropApp.swift:46-58` | Verified |
| Downsampling to 1280 px | two implementations | `OCRService.swift:140-158`, `ShareViewController.swift:313-331` | Verified |
| PayBook masking / copy / duplicate alert | model + views | `Models/PayBookContact.swift`, `Views/PayBook/*`; tests 43–48 | Verified |
| Currency preference unused | only reference is the picker | `Views/Settings/SettingsView.swift:8` (sole hit) | Verified |
| Receipt image not deleted with expense | no `deleteImage` call in delete paths | `ExpensesView`, `ExpenseDetailView`, `SettingsView` | Verified |
| 48 tests pass | simulator run output | `[TEST_RUN_SUMMARY] 48/48 PASSED` | Verified 2026-09-25 |
| Build succeeds, 4 warnings | `xcodebuild` log | scratch build log | Verified 2026-09-25 |
| 19 commits, 3 days, one author | `git log` | repository | Verified |
| Project generated by script | deterministic IDs via SHA-1 | `scripts/generate_xcodeproj.py` | Verified |
| Sample data: 18 records, idempotent | array + predicate guard | `Data/SampleData.swift`; test 23 | Verified |
| Screenshots | simulator captures | `docs/screenshots/*.png`, `docs/screenshots/case-study/*.png` | Verified |
| App reopens pre-rename data | legacy App Group id + `.identifier` container; store injected on simulator; device install | `Data/ExpenseDataContainer.swift`, §19 C12 | Verified 2026-09-25 |
| Sample images synthetic | rendered by script; real-data originals purged from unpushed history | `Resources/DiagnosticSamples/` | Verified 2026-09-25 |
| Manual device testing on iPhone 17 Pro Max | README statement only | `README.md` (previous version) | Not verified from the available project files |
| Performance numbers, user counts, accuracy rates | — | — | None exist; none claimed |

---

## 29. Final Summary

SpenDrop is a complete, working, offline iOS expense tracker whose distinguishing engineering is a Vision-based OCR pipeline and a carefully hardened, test-backed parser for Malaysian payment screenshots, delivered both in-app and through a Share Extension over a shared SwiftData store. The codebase is dependency-free, cleanly separated into models, data, engine, views and extension, and ships its own 48-case verification suite that passed in full on 2026-09-25 after the project was renamed from SpendDrop to SpenDrop and rebuilt.

The main areas for maturation are operational rather than functional: error handling around persistence, logging hygiene, pasteboard security for account numbers, a proper test target with CI, and schema migration planning. Everything stated above is traceable to a file, a commit, or the verification run recorded in §20.

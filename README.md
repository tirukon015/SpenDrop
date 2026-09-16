# SpendDrop 💧
**Personal Expense Tracker**

> **Capture → Understand → Save**  
> *"Whatever I spend, I can drop it into SpendDrop."*

SpendDrop is an independent, native iOS personal expense tracking application built exclusively with Apple's modern Swift, SwiftUI, SwiftData, Vision, and Share Extension frameworks.

---

## 🎯 Target Devices
- **iPhone 17 Pro Max** (Primary test & daily driver)
- **iPhone 16 Pro Max**

---

## 🚀 Milestone 1 Features (Completed)
- **Standalone Xcode Project**: Full iOS 17+ architecture (`SpendDrop.xcodeproj`).
- **SwiftData Local-First Storage**: Zero cloud dependencies, zero external database, zero tracking.
- **Fast Cash Entry**: 1-tap "Quick Cash" shortcut, hero amount keypad, increment chips (`+RM5`, `+RM10`, `+RM20`, `+RM50`).
- **Smart Merchant & Category Suggestions**: Quick chips for Malaysian daily spending (`McDonald's`, `Mamak`, `Grab`, `MYDIN`, `Starbucks`, `7-Eleven`, `Shell`).
- **Unified Expense History**: Grouped by day, search across merchants/amounts/notes, filter chips, swipe to delete.
- **Native iOS Dashboard**: Real-time totals (**Today**, **This Week**, **This Month**) and today's expenses list.
- **Expense Details & Editing**: Full edit sheet, deletion prompts, and detail breakdown.
- **Apple Charts Analytics**: Interactive Donut chart for categories and horizontal Bar chart for payment sources.
- **Settings & Testing Utilities**: Sample data seeder, data wiper, system/light/dark mode.

---

## 🔍 Milestone 2 Features: Vision OCR & Transaction Parser (Completed)
- **Apple Vision Framework OCR**:
  - Completely offline, on-device OCR using `VNRecognizeTextRequest` (`recognitionLevel = .accurate`).
  - Asynchronous background processing with smooth "Reading transaction..." loading state.
  - Zero external paid AI APIs.
- **Malaysian Context & Format Parser**:
  - Formats: `RM 25.90`, `RM25.90`, `MYR 25.90`, `Amount: RM25.90`, `Paid RM 25.90`, `Total RM25.90`.
  - **False Positive Protection**: Rejects non-expense numbers from account balances (`Available Balance RM1,250`), credit limits (`Credit Limit RM5,000`), reward points (`2,500 points`), and phone numbers.
  - **Multiple Amount Prioritization**: In receipts with Subtotal, Tax, and Grand Total, prefers the Grand Total.
  - **Failed Transaction Detection**: Flags "Payment Failed" / "Declined" transactions and warns the user.
- **Merchant & Category Detection**:
  - Detects Malaysian stores, e-wallets, telcos, utilities, and restaurants (`McDonald's`, `KFC`, `Starbucks`, `Zus`, `MYDIN`, `7-Eleven`, `Lotus's`, `Grab`, `Shell`, `Shopee`, `TNB`, etc.).
  - Contextual fallback to `nil` / "Unknown" to avoid hallucinated names.
- **Payment Source Detection**:
  - Detects Touch 'n Go (TNG), Maybank / MAE, CIMB OCTO, RHB Mobile, Apple Pay, DuitNow QR, and Cards.
- **Minimal Expense Review Screen**:
  - High confidence ("Expense Detected ✓") vs low confidence ("Possible Expense ?") display.
  - Interactive editing of amount, merchant, category, payment method, date & time.
  - Optional description field (never required).
  - Original screenshot preview and local disk storage (`ImageStorageService`).
- **In-App Automated Self-Test Runner**:
  - Run all automated test cases directly on device in **Settings → Run OCR & Parser Self-Test** with live pass/fail verification.

---

## 📲 Milestone 3 Features: iOS Share Extension (Completed)
- **Native iOS Share Extension Target (`SpendDropShare`)**:
  - Integrated into iOS Share Sheet for all image types (`public.image`: PNG, JPEG, HEIC, Screenshots).
  - Minimal, ultra-fast workflow:
    `Payment Done` → `Take Screenshot` → `Tap Share` → `Select SpendDrop` → `Auto-Parse` → `Confirm & Save` → `Done`.
- **Shared App Group Storage**:
  - Both the Main App and Share Extension read and write to the same local SwiftData database container at `group.com.spenddrop.shared`.
  - Zero backend, zero cloud, 100% offline and local-first.
- **Asynchronous Extension Lifecycle**:
  - Safely extracts `UIImage` from `NSItemProvider` (supporting raw UIImage, file URLs, and Data).
  - Runs Vision OCR on a background task while displaying clean "Reading transaction..." progress.
  - Reuses the robust `OCRService`, `TransactionParser`, and `MerchantDetector` without duplicating code.
- **Duplicate Protection**:
  - Automatically queries the shared store via `DuplicateDetector` to identify matching recent expenses (by amount, merchant, date, or reference).
  - Warns the user with a "Possible Duplicate Detected" alert with `[Add Anyway]` and `[Cancel]` options.
- **Instant Main App Reflection**:
  - Saved extension expenses automatically appear in Dashboard, Unified History, and Analytics.
  - Foreground reactivation triggers instant totals recalculation.

---

## 🛠 Project Structure
```
SpendDrop
├── SpendDrop.xcodeproj
├── SpendDrop/
│   ├── App/
│   │   └── SpendDropApp.swift
│   ├── Models/
│   │   ├── Expense.swift
│   │   ├── ExpenseCategory.swift
│   │   ├── PaymentSource.swift
│   │   └── ExpenseSourceType.swift
│   ├── Data/
│   │   ├── ExpenseDataContainer.swift
│   │   ├── DuplicateDetector.swift
│   │   └── SampleData.swift
│   ├── OCR/
│   │   ├── OCRService.swift
│   │   ├── ParsedTransaction.swift
│   │   ├── MerchantDetector.swift
│   │   ├── CategoryDetector.swift
│   │   ├── TransactionParser.swift
│   │   ├── ImageStorageService.swift
│   │   └── TransactionParserTests.swift
│   ├── Views/
│   │   ├── MainTabView.swift
│   │   ├── Dashboard/
│   │   │   ├── DashboardView.swift
│   │   │   └── Components/
│   │   │       ├── SpendingSummaryCard.swift
│   │   │       └── QuickCashButton.swift
│   │   ├── Expenses/
│   │   │   ├── ExpensesView.swift
│   │   │   ├── ExpenseDetailView.swift
│   │   │   ├── EditExpenseView.swift
│   │   │   └── Components/
│   │   │       ├── ExpenseRowView.swift
│   │   │       └── FilterBarView.swift
│   │   ├── AddExpense/
│   │   │   └── AddExpenseView.swift
│   │   ├── Review/
│   │   │   └── ExpenseReviewView.swift
│   │   ├── Analytics/
│   │   │   └── AnalyticsView.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       └── Components/
│   │           └── ParserSelfTestView.swift
│   ├── ShareExtension/
│   │   ├── ShareViewController.swift
│   │   ├── ShareExtensionView.swift
│   │   ├── Info.plist
│   │   └── ShareExtension.entitlements
│   ├── Utils/
│   │   ├── CurrencyFormatter.swift
│   │   └── HapticFeedback.swift
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── SpendDrop.entitlements
```

---

## 📱 How to Run & Test on iPhone 17 Pro Max
1. Open `SpendDrop.xcodeproj` in **Xcode 16+**.
2. Select your Apple Development Team under **Signing & Capabilities** for both targets:
   - `SpendDrop` (App)
   - `SpendDropShare` (Share Extension)
3. Connect your **iPhone 17 Pro Max** or Simulator.
4. Select `SpendDrop` scheme and press **⌘ + R** to run.
5. **Testing the Share Extension**:
   - Take a screenshot of any payment (TNG, Maybank, CIMB, Apple Pay, receipt).
   - Tap the screenshot thumbnail or open Photos.
   - Tap **Share** (iOS Share Sheet).
   - Tap **SpendDrop** in the app row.
   - Watch the Share Extension parse the transaction and display the review sheet.
   - Tap **Save Expense**.
   - Open SpendDrop: the expense is already saved and reflected in Dashboard totals and History!
6. **Testing Duplicate Protection**:
   - Share the exact same screenshot again.
   - SpendDrop will display the warning: *"Possible Duplicate Detected: Matching expense recorded..."* with options to `Add Anyway` or `Cancel`.

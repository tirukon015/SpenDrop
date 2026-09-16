# SpendDrop 💧
**Personal Expense Tracker**

> **Capture → Understand → Save**  
> *"Whatever I spend, I can drop it into SpendDrop."*

SpendDrop is an independent, native iOS personal expense tracking application built exclusively with Apple's modern Swift, SwiftUI, and SwiftData frameworks.

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
- **Unified Expense History**:
  - Grouped by day (Today, Yesterday, Specific Date).
  - Search across merchants, categories, payment methods, amounts, and notes.
  - Interactive filter chips (All, Cash Only, TNG, Categories).
  - Swipe to delete with haptic confirmation.
- **Native iOS Dashboard**:
  - Real-time spend totals: **Today**, **This Week**, **This Month**.
  - Today's expenses list with payment badges & category icons.
- **Expense Details & Editing**: Full edit sheet and detailed inspection view with deletion safety prompts.
- **Apple Charts Analytics**: Interactive Donut chart for categories and horizontal Bar chart for payment sources.
- **Settings & Testing Utilities**:
  - Instant "Load Sample Transactions" button for immediate physical device verification.
  - Clear data utility.
  - Light mode / Dark mode / System theme support.

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
│   │   └── SampleData.swift
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
│   │   ├── Analytics/
│   │   │   └── AnalyticsView.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   ├── Utils/
│   │   ├── CurrencyFormatter.swift
│   │   └── HapticFeedback.swift
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── SpendDrop.entitlements
```

---

## 📱 How to Run on iPhone 17 Pro Max / iPhone 16 Pro Max
1. Open `SpendDrop.xcodeproj` in **Xcode 16+**.
2. Under **Signing & Capabilities** for target `SpendDrop`:
   - Select your Personal Apple ID / Team.
   - The bundle identifier defaults to `com.spenddrop.SpendDrop`.
3. Connect your **iPhone 17 Pro Max** or select the iOS Simulator.
4. Press **⌘ + R** (Run) to build and deploy.
5. In the app:
   - Tap **Quick Cash** to record a cash expense in seconds.
   - Go to **Settings → Load Sample Transactions** to immediately populate realistic data and explore the Dashboard & Analytics.

# SpenDrop — iOS ↔ Android feature parity

The inventory comes from reading the iOS sources (see `Docs/IOS-Audit.md`), the Web app, and the Supabase migrations.

**Test evidence**
- **U**: `:core` JVM unit tests (ported iOS cases + `Common/BusinessRules` vectors).
- **R**: Android tests on the JVM (Robolectric): real Compose screens, Room, share intents.
- **B**: implemented and builds; exercised only by reading/compiling, no automated test.
- **D**: verified on a physical phone. **None yet**: no phone was connected during the build, and the emulator couldn't start because the Mac had too little free disk (see IMPLEMENTATION_STATUS.md).

**Status:** PASS = implemented, with automated evidence. IMPL = implemented, needs device check. PARTIAL / N/A as described.

## Navigation & app shell

| Feature | iOS | Android | Tested | Status / notes |
|---|---|---|---|---|
| 5 tabs: Home, Transactions, PayBook, Breakdown, More | ✓ | ✓ | R | PASS. Tab title spelled "PayBook" everywhere (iOS shows "Paybook" in one title, a known iOS slip). |
| More hub: Account, Accounts, Settings | ✓ | ✓ | R | PASS |
| Appearance System / Light / Dark | ✓ | ✓ | B | IMPL. Same values as iOS (`system`/`light`/`dark`). |
| Splash / launcher icon from the iOS artwork | ✓ | ✓ | B | IMPL. Adaptive icon. |

## Authentication (same Supabase project, same accounts)

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Email sign-in | ✓ | ✓ | U(mock server) | PASS. Not yet run against the live project with a real account. |
| Create account with PKCE email confirmation (`spendrop://auth-callback`) | ✓ | ✓ | U(mock) | PASS (mock) / IMPL (live) |
| Password reset link → set new password | ✓ | ✓ | U(mock) | PASS (mock) / IMPL (live) |
| Google sign-in (OAuth PKCE, browser) | ✓ | ✓ (Custom Tab) | U(mock) | IMPL. Needs a device and browser. |
| Session persistence, refresh within 60 s, offline keeps session, revoked → signed out | ✓ | ✓ | U(mock) | PASS |
| Sign out (local data untouched) | ✓ | ✓ | B | IMPL |
| Delete cloud account (backups first, then `delete_my_account`) | ✓ | ✓ | B | IMPL. Not run, since it would delete a real account. |
| Client validation (8+ chars, upper, lower, digit; email) and iOS error wording | ✓ | ✓ | U | PASS |
| Local-first (fully usable signed out) | ✓ | ✓ | R | PASS |

## Transactions

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Add expense (amount, merchant, category, funding account, channel, date+time, notes) | ✓ | ✓ | R | PASS |
| Quick amount buttons (+RM5/10/20/50) and Quick Cash | ✓ | ✓ | B | IMPL |
| Record types: Expense / Money In / Money Out / Transfer | ✓ | ✓ | U (validation) | IMPL (UI) |
| Money movement kinds (income, loans, repayments, refund, other, own transfer) and validation | ✓ | ✓ | U | PASS |
| Edit expense (relink account, learn, re-apply or remove split) | ✓ | ✓ | B | IMPL |
| Edit / delete money record | ✓ | ✓ | B | IMPL |
| Delete expense | ✓ | ✓ (swipe with Undo, or detail) | R (repository) | PASS. Deletes are tombstones. |
| Expense detail (fields, split, who owes whom, receipt image) | ✓ | ✓ | B | IMPL |
| Unified timeline grouped by day (Today / Yesterday / date) | ✓ | ✓ | U | PASS |
| Type chips All / Expenses / Money In / Money Out / Shared / Transfers | ✓ | ✓ | U | PASS |
| Search (merchant, category, funding, channel, notes, amount; movements by kind, note, person, account) | ✓ | ✓ | U | PASS |
| Date filters Today … Last Month, Custom Range | ✓ | ✓ | U | PASS |
| Multi-select category / channel / funding filters (shared with Breakdown) | ✓ | ✓ | U | PASS |
| Sort Newest / Oldest | ✓ | ✓ | U | PASS |
| Spent / In / Out header | ✓ | ✓ | U | PASS |
| Learned category per merchant, learned channel per merchant+funding | ✓ | ✓ | U | PASS |

## Funding accounts vs payment channels

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Separate "Funding account (where money came from)" and "Payment channel (how)" pickers | ✓ | ✓ | R | PASS |
| 11 channels incl. DuitNow QR, TNG QR, Online Banking; UNKNOWN never guessed | ✓ | ✓ | U | PASS |
| Accounts auto-created/linked from funding text, channel names never become accounts | ✓ | ✓ | U | PASS |
| Accounts screen: recorded in/out/net (not a bank balance), detail, add/edit/archive, "Not linked" | ✓ | ✓ | U (math) / B (UI) | IMPL |

## Split money (contributors)

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Inline split while adding/reviewing (before first save) | ✓ | ✓ | R | PASS |
| Equal / Parts / Custom Amount | ✓ | ✓ | U, R (equal) | PASS |
| Auto Calculate per split, default ON; OFF requires exact total | ✓ | ✓ | U (Common vectors) | PASS |
| Fixed amounts (fixed + equal share of the rest) | ✓ | ✓ | U (Common vectors) | PASS |
| Remaining / allocated amount, iOS problem messages | ✓ | ✓ | U | PASS |
| Hybrid Split: group fixed amounts (a total divided between the group, several groups), individual fixed amounts (one person, several), the rest split equally between a chosen group; a person can be in every layer; live, saved and reopened | ✓ | ✓ | U (shared `split-hybrid-vectors.json`, 27 cases + layers, live changes, reload, bad-rule fallback, backup, cloud rows), R (Add Expense flow at phone and tablet widths; v1→v2 database upgrade) | PASS |
| Paid for someone; payer Me / someone else | ✓ | ✓ | U | PASS |
| Rounding: integer sen, largest remainder, extra sen to Me when I paid | ✓ | ✓ | U (Common vectors) | PASS |
| Same as last time suggestion | ✓ | ✓ | U | PASS |
| Add a new PayBook person from the split picker | ✓ | ✓ | R | PASS |

## PayBook (people, balances, settlements)

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| People: name, notes, photo, frequent, archived | ✓ | ✓ | B | IMPL. Photos stay on the device, as on iOS. |
| Payment methods (type, provider list, custom, identifier, label, notes, masked, copy, duplicate check) | ✓ | ✓ | B | IMPL |
| Balances per person/currency, summary (owed to you / you owe / settled) | ✓ | ✓ | U, R | PASS |
| Filter All / They Owe Me / I Owe Them; Frequent / Other / Archived groups; search | ✓ | ✓ | U | PASS |
| Mark Paid, Settle Selected, Different Amount (auto/manual), Apply Credit, Settle All, Undo | ✓ | ✓ | U, R (Settle All) | PASS |
| Delete blocked while a balance exists (archive offered) | ✓ | ✓ | U | PASS |
| Settlement errors shown to the user | ✗ (iOS swallows them) | ✓ | B | Improvement |
| History list with +/− effects | ✓ | ✓ | U | PASS |
| "Save recipient to PayBook" button in Add Expense | ✓ | ✗ | — | PARTIAL. Android adds people from the split/merchant pickers instead. |

## Home & Breakdown

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Today / This Week / This Month spending (my share when someone else paid) | ✓ | ✓ | U, R | PASS |
| Shared-this-month line, Cash Flow this month, Balances card | ✓ | ✓ | U, R | PASS |
| Today's expenses, Recent Activity, empty state actions | ✓ | ✓ | R | PASS |
| Breakdown Spending: totals, avg/day, comparison, daily chart 7/30, categories (donut), channels, funding (tap to filter), shared & refunds, top merchants, trend D/W/M | ✓ | ✓ | U, R | PASS |
| Breakdown Cash Flow: in, out, net, by type, trend | ✓ | ✓ | U | PASS |
| Mode remembered (`breakdown_mode`) | ✓ | ✓ | B | IMPL |

## Import: screenshots, receipts, PDF, share

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| On-device OCR | Vision | ML Kit (bundled, no Play Services needed) | B | IMPL. Needs a device: ML Kit's native code can't run on the JVM. |
| Parser: amounts (candidates, totals over subtotal/tax, ads excluded), merchant (~55 known), date/time, reference, failed/balance/limit detection | ✓ | ✓ | U (59 ported iOS cases) | PASS |
| Category / channel / provider / direction suggestions with reasons and confidence | ✓ | ✓ | U | PASS |
| Review screen: banner, Save as, screenshot, possible amounts, uncertain funding/category hints | ✓ | ✓ | R (shared text) | PASS |
| Duplicate protection (strong → Merge or Add Anyway; weak → warning; manual never checked) | ✓ | ✓ | U | PASS |
| Share target: images, PDF, text, multiple | Share Extension | ShareActivity | R (text) | PASS (text) / IMPL (image, PDF, multiple: need a device for OCR) |
| In-app import: screenshot/photo (photo picker), PDF/file (file picker) | Photos | ✓ (+PDF, which iOS can only take via share) | B | IMPL |
| Take a photo of a paper receipt (in-app camera, CAMERA runtime permission requested in context, Settings fallback, photo-picker fallback) | declared (`NSCameraUsageDescription`), no camera screen in code | ✓ CameraX | R (permission flows), D (permission state via adb) | IMPL |
| Permissions & Access screen (real Android states) | — | ✓ | R | PASS |
| PDF receipt: text pages (≤5) else OCR of rendered pages (≤3) | ✓ | ✓ | U, R (PdfBox text) | PASS (text path) / IMPL (OCR path) |
| Multi-transaction bank statement PDF | ✗ | ✗ | — | N/A. Not in iOS or Web; nothing to reproduce. |
| Receipt image kept with the expense (optimised, local only) | ✓ | ✓ | B | IMPL |
| "Couldn't read" → Enter manually / Retry | ✓ | ✓ | B | IMPL |
| Bulk Screenshot Import: up to 30 screenshots → separate drafts (history lists give one per row), batch + saved duplicate check (Skip by default / Add Anyway / Merge), collapsed cards that open the full editor incl. Split Money, "Unable to detect" cards, "Add N Transactions" saving each through the normal save path with its own screenshot | ✓ | ✓ (Home → scan → Bulk Import, picking 2+ screenshots, or sharing 2+ images) | U (shared `bulk-import-vectors.json`, BulkReview), R (review queue → Add N) | PASS (logic, UI with text) / IMPL (OCR of real screenshots needs a device) |
| Apple Pay Shortcuts automation | ✓ | ✗ | — | N/A. Apple-only feature; Android has no equivalent public API. |

## Backup, restore, cloud

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Automatic local backup after changes + daily/before-shrink history | ✓ | ✓ | B | IMPL |
| Export / Import backup JSON (iOS format v4, cross-platform) | ✓ | ✓ | U (codec), R (round trip) | PASS |
| Restore from local backup | ✓ | ✓ | R (merge) | PASS |
| Cloud Backup (same bucket, row, verify, prune, retention 30/90) | ✓ | ✓ | U (protocol) | IMPL. Not run against the live project (needs a signed-in account). |
| Daily automatic backup at a chosen time | BGTask | WorkManager | U (schedule) | IMPL |
| Restore from cloud with ranges, preview, safety copy, merge by id | ✓ | ✓ | U, R (merge) | IMPL (live download untested) |
| Live sync with the Web App (per-record cloud tables, deployed during the night) | ✗ (planned) | ✓ SyncService | U, R (mock server: pull, push, cursor, no echo, account guard) | IMPL. Same protocol as the Web (`Docs/Sync-Architecture.md`). Not yet run against the live project; needs a signed-in account. Goes beyond iOS. |

## Settings & data

| Feature | iOS | Android | Tested | Status |
|---|---|---|---|---|
| Record counts, privacy text, about (real version, not hard-coded) | ✓ | ✓ | B | IMPL |
| Load / remove sample data (exact removal) | ✓ | ✓ | U, R | PASS |
| OCR & parser self-test | ✓ | ✓ | U, R | PASS |
| Clear All Expenses (safety copy first) | ✓ | ✓ | B | IMPL. Same scope as iOS (expenses only). |
| Screenshot storage stats | ✓ | ✓ | B | IMPL. Android always stores optimised copies, so there is no "Optimize Existing" button. |
| Default Currency picker | ✓ (has no effect on iOS) | ✗ | — | Left out on purpose: a control that does nothing would be a fake button. RM is used, as on iOS. |

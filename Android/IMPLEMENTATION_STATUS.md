# SpenDrop Android — Implementation status

Last updated: 2026-10-07 (overnight autonomous build).

## Summary

**COMPLETE WITH DOCUMENTED LIMITATIONS.** Every meaningful iOS feature is on Android (see `FEATURE_PARITY.md`), plus live sync with the Web App.
- Business rules are ported 1:1 from iOS and covered by 279 JVM tests, including the shared `Common/BusinessRules` vectors.
- 24 Android tests run the real screens, database, share target, import pipeline, auth and sync on the JVM.
- **Nothing has been run on a physical phone or an emulator yet** (reasons below). Start there in the morning.

## What was done

1. **Audit:** iOS sources, `Docs/IOS-Audit.md`, the Web app, `Common/`, Supabase migrations, and read-only probes of the live Supabase project.
   - At the start of the night only `backups` existed.
   - Around 09:30 (local time) the Web session's per-record tables were live; their existence was confirmed with an anon probe ("permission denied", not "not found"). Android was then extended with live sync.
   - I created no migrations and touched no Supabase data.
2. **Toolchain:** installed user-locally with no admin rights.
   - Installed: JDK 17, Android SDK 37, Gradle 9.8 wrapper.
   - Versions used: AGP 9.4.1, Kotlin 2.4.20, Compose BOM 2026.09, Room 2.8.5, ML Kit 16.0.1, PdfBox-Android 2.0.27.0, Robolectric 4.17.
3. **`:core`:** the domain model and every iOS rule (money, splits, ledger and settlements, filters/analytics, accounts, duplicates, parser and self-test, classifier, backup/restore, cloud protocol, sync merge, sample data).
   - Includes the iOS split change made tonight by the other session (an empty custom-amount box counts as RM 0.00).
4. **`:app`:**
   - Data: Room (local-first), repository, local auto-backup.
   - Cloud: auth (same Supabase project), Cloud Backup with daily WorkManager job, live Sync.
   - Screens: all of them.
   - Import: ML Kit OCR, PDF, and the share target. The launcher icon is the new full-bleed SpenDrop icon (shared with iOS/Web).
5. **Review pass:** an independent code review of the app layer found 13 medium/low issues and no high ones. All are fixed:
   - Heavy backup/restore work moved off the main thread.
   - Cloud actions survive leaving the screen; half-finished uploads are always cleaned up.
   - The sign-in link exchange survives activity recreation.
   - A cold-start share waits for the database before checking duplicates.
   - A rate-limited token refresh no longer signs the user out.
   - "Merge with Existing" relinks the account.
   - The payment source follows the chosen funding account.
   - Double-tap guards; a missing record closes the editor; single-instance password screen; responses are closed on cancellation.

## Later on 2026-10-07

- Installed and run on the OPPO (CPH2269, Android 11): Google sign-in and live sync checked by hand.
- Camera runtime permission, in-app receipt camera, Permissions & Access screen.
- UI spacing pass on all screens; more room under the status bar for page titles.
- **Hybrid Split** (`Common/BusinessRules/split-hybrid.md`): group fixed + individual fixed + remaining. Shares are saved as normal amounts; the rule is one optional `splitRule` on the expense (database version 2, tested upgrade from version 1). Cloud: needs migration `20261008000000_hybrid_split.sql`; until it's applied the rule stays on the device and the split syncs as plain custom amounts.
- **Bulk Screenshot Import** (same rules as iOS and Web: `Common/BusinessRules/bulk-import.md`). Tests: `./gradlew :core:test` 298, `:app:testDebugUnitTest` 52, 0 failures.

## Verification

| Check | Result |
|---|---|
| `./gradlew :core:test` | 279 tests, 0 failures |
| `./gradlew :app:testDebugUnitTest` | 24 tests, 0 failures (see below) |
| `./gradlew :app:lintDebug` | 0 errors; warnings are style/deprecations (and one inside BouncyCastle, a PdfBox dependency SpenDrop doesn't use for networking) |
| `assembleDebug`, `assembleRelease` (R8), `bundleRelease` | Build successfully |
| Physical devices (OPPO A57, Redmi Note 12 5G) | **Not done.** `adb devices` was empty every time it was checked. |
| Emulator | **Not done.** The emulator needs about 7.4 GB free; the Mac had 4.5–7.4 GB. I didn't delete your files; I removed the emulator again so builds keep working. |
| Live Supabase sign-in, backup, sync | **Not done.** There is no test account, and I didn't create accounts or send emails on production. All flows are tested against a mock server with the same endpoints. |

The 24 Android tests cover:
- Auth: 12, against a mock Supabase server.
- Room repository.
- Sample-data load.
- Backup round trip between two "devices".
- Import of shared text, a generated bank-transfer PDF, an unsupported file, and an empty share.
- Share → review → save through `ShareActivity`.
- The add-split-expense → Home → PayBook → Settle All → Breakdown flow.
- Sample data load/remove in the UI.
- Sync: first sync pulls Web data and pushes phone data in FK order without echo, then uses the cursor; and the guard that refuses to mix accounts.

## Morning checklist (device)

1. Install `release/SpenDrop-debug.apk` on the OPPO A57 and the Redmi Note 12 5G.
2. Add an expense with a split, then check Home, PayBook and Breakdown.
3. Screenshot a payment, Share it to **Add to SpenDrop**, and check the OCR review, then save.
4. Share a PDF receipt.
5. Pick a screenshot via Home → scan icon.
6. Sign in (Email or Google) → More → Account:
   - Turn on **Sync**. Records should match SpenDrop on the web both ways.
   - Turn on **Cloud Backup** and run **Back Up Now**.
   - **Restore** an iPhone backup.

## Known limitations / open items

1. Device and live-backend verification (above).
2. Release APK/AAB are unsigned: no key exists and none was invented. See README → Release signing.
3. APK size: about 76 MB debug and 52 MB release, universal (ML Kit and PdfBox for all CPUs). The AAB lets Play deliver about 15–20 MB.
4. Receipt images: Android keeps its screenshots on the phone. They are not uploaded to the `receipts` bucket, and Web receipts are not shown on Android yet.
5. iOS doesn't sync yet (planned by the other session), so iPhone data reaches Android through Cloud Backup restore or the Web's iPhone import.
6. Not ported because they are iOS-only: Apple Pay Shortcuts automation, HEIC optimiser. Left out on purpose: the iOS "Default Currency" picker, which has no effect on iOS. Not reproduced: the "Save recipient to PayBook" button (people are added from pickers instead).
7. `targetSdk` 36 (`compileSdk` 37). Raise it after device testing.

## Repository hygiene

- All Android code is in `Android/`. No Web, iOS, Supabase or `Common/` files were modified.
- The commit is on a separate branch `feature/android-app`, made through a separate git worktree. Your working tree, its current branch (`feature/multi-platform-webapp`, used by the Web session) and its uncommitted changes were not touched.
- Git-ignored: `Android/local.properties` (public Supabase URL/key, SDK path), `keystore.properties`, build outputs, and the APK/AAB in `Android/release/`.

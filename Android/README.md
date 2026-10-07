# SpenDrop for Android

The native Android client of SpenDrop: the same product as the iPhone app (and the Web app), built with Kotlin and Jetpack Compose. It records expenses and money movements, splits bills with PayBook people, reads payment screenshots and PDF receipts on the device, and shows the same Home and Breakdown numbers as iOS.

Like iOS, SpenDrop on Android is **local-first**: everything works on the phone without an account. Signing in (same Supabase project, same account as iOS/Web) is optional and enables:

- **Sync with SpenDrop Cloud**: the same records as SpenDrop on the web (live, per record, the same tables and protocol as the Web App).
- **Cloud Backup**: the same private `backups` storage and JSON format as iOS, so a backup made on iPhone can be restored on Android and the other way round.

## Install the APK (no build needed)

| File | Use |
|---|---|
| `release/SpenDrop-debug.apk` | Install this on a phone to try SpenDrop. Debug-signed, package `com.spendrop.app.debug`. |
| `release/SpenDrop-release-unsigned.apk` | Optimised (R8) release build. **Unsigned**: sign it before installing (see "Release signing"). |
| `release/SpenDrop-release-unsigned.aab` | Play Store bundle. Unsigned until you add a key. |

1. Copy `SpenDrop-debug.apk` to the phone (USB, Drive, Nearby Share), or run `adb install -r release/SpenDrop-debug.apk`.
2. Open it and allow "Install unknown apps" for the app you opened it from if Android asks.
3. Open SpenDrop. No sign-in is needed. More → Account to sign in for Cloud Backup.
4. Take a screenshot of a payment → Share → **Add to SpenDrop** → review → Save.

## Requirements

- macOS / Linux / Windows with **JDK 17** (Android Studio's bundled JBR works).
- Android SDK with **platform 37** and build-tools. Android Studio installs these.
- Android 8.0 (API 26) or newer on the phone.

The project was built on this Mac with a user-local toolchain (no admin rights needed):

```bash
export JAVA_HOME=~/.spendrop-toolchain/jdk/Contents/Home   # Temurin 17
export ANDROID_HOME=~/Library/Android/sdk
```

## Configure Supabase (public values only)

Create `Android/local.properties` (git-ignored):

```properties
sdk.dir=/Users/<you>/Library/Android/sdk
supabase.url=https://<project>.supabase.co
supabase.publishableKey=<publishable or anon key>
```

These are the same public client values as `iOS/SpenDrop/Resources/CloudConfig/SupabaseConfig.plist`. Never put a service-role key here. Without them the app still works fully; cloud features show "isn't set up in this build". `SPENDROP_SUPABASE_URL` / `SPENDROP_SUPABASE_KEY` environment variables also work (CI).

Sign-in links (email confirmation, password reset, Google) return to `spendrop://auth-callback`, the same redirect iOS uses, so no Supabase change is needed.

## Build

```bash
cd Android
./gradlew assembleDebug          # app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease        # app/build/outputs/apk/release/app-release-unsigned.apk (R8 shrunk)
./gradlew bundleRelease          # app/build/outputs/bundle/release/app-release.aab
```

Open the `Android/` folder in Android Studio to run and debug.

## Tests

```bash
./gradlew :core:test              # 279 business-logic tests (pure JVM)
./gradlew :app:testDebugUnitTest  # 24 Android tests: Robolectric UI flows, Room, share target, import, auth, sync
./gradlew :app:lintDebug          # Android Lint (0 errors)
```

- `:core` tests include the shared cross-platform rules in `../Common/BusinessRules` (split and money vectors), so Android, iOS and Web are held to the same numbers.
- The UI tests run the real Compose screens on the JVM (Robolectric): add a split expense with a new person → Home, PayBook, Settle All, Breakdown; sample data load/remove; Share → review → save.

## Run on a phone

1. On the phone: Settings → About phone → tap **Build number** 7 times → Developer options → **USB debugging** on.
   - OPPO/realme (ColorOS): also turn on "Disable permission monitoring" if installs are blocked.
   - Xiaomi/Redmi (MIUI/HyperOS): also turn on **Install via USB** (needs a Mi account and SIM) and "USB debugging (Security settings)".
2. Connect by USB, accept the "Allow USB debugging?" prompt.
3. `~/Library/Android/sdk/platform-tools/adb devices` must list the phone as `device`.
4. `adb install -r release/SpenDrop-debug.apk` then open SpenDrop.

## Permissions (and testing them with ADB)

| Permission | Type | Why |
|---|---|---|
| `android.permission.INTERNET` | install-time, auto-granted | sign-in, sync, cloud backup |
| `android.permission.CAMERA` | **runtime**, asked when you tap *Take Photo of Receipt* | in-app receipt camera |
| `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE` | install-time, added by WorkManager | daily cloud backup job |

Screenshots, photos and PDFs need **no** permission (photo picker, file picker, share sheet). App info → Permissions therefore lists only **Camera**. In-app: More → Settings → **Permissions & Access**.

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
PKG=com.spendrop.app.debug                       # release build: com.spendrop.app
cd Android && ./gradlew assembleDebug            # 1. build
$ADB devices                                     #    phone must show as "device"
$ADB install -r app/build/outputs/apk/debug/app-debug.apk   # 2. install (keeps data)
$ADB shell pm list packages | grep spendrop      # 3. installed package
$ADB shell dumpsys package $PKG | sed -n '/requested permissions:/,/install permissions:/p'   # 4. declared
$ADB shell dumpsys package $PKG | grep "android.permission.CAMERA:"   # 7. state: granted=true/false + flags
$ADB shell pm revoke $PKG android.permission.CAMERA                   # 5. reset (runtime permissions only)
$ADB shell pm clear-permission-flags $PKG android.permission.CAMERA user-set user-fixed   # forget "Don't ask again"
$ADB shell pm grant $PKG android.permission.CAMERA                    #    grant without the dialog (testing)
$ADB shell am start -n $PKG/com.spendrop.app.MainActivity             # 6. launch
```

`pm grant` / `pm revoke` only work for runtime permissions (here: CAMERA). INTERNET and the other install-time permissions are always granted and can't be changed. After `pm revoke`, SpenDrop shows the camera as not allowed and asks again on the next use. `pm clear-permission-flags … user-fixed` undoes a "Don't ask again" for testing.

## How sharing works (Share Target)

SpenDrop registers for the Android share sheet (`ShareActivity`) for `image/*`, `application/pdf` and `text/plain`, single or multiple, plus "Open with" for images and PDFs. It never watches screenshot folders and needs **no storage permission**: Android hands over a temporary content URI, which SpenDrop copies into its private cache immediately. This works with every gallery and file manager (Samsung, Xiaomi, OPPO, Vivo, Pixel, Tecno…). Shared content opens a review screen on top of the app you shared from; after saving you're back where you were, and any unsaved form in SpenDrop itself is left alone.

Sharing two or more images opens **Bulk Import** (below).

In the app, Home → scan icon → "Screenshot or Photo" (Android photo picker) or "PDF or File" (file picker) does the same without sharing.

## Bulk Screenshot Import

Home → scan icon → **Bulk Import Screenshots** (or pick 2+ screenshots, or share 2+ images to SpenDrop). Up to 30 screenshots are read on the phone, two at a time. Each payment becomes its own normal draft (a bank-history screenshot gives one per row); possible duplicates (already saved, or twice in the batch) are skipped unless you choose Add Anyway or Merge. Tap a card to open the full transaction form, including Split Money. **Add N Transactions** saves each one separately, with its own screenshot as the receipt. Rules: `../Common/BusinessRules/bulk-import.md`.

## Release signing

No signing key is in the repository. To sign:

```bash
keytool -genkeypair -v -keystore spendrop-release.jks -alias spendrop -keyalg RSA -keysize 4096 -validity 10000
```

Create `Android/keystore.properties` (git-ignored):

```properties
storeFile=spendrop-release.jks
storePassword=...
keyAlias=spendrop
keyPassword=...
```

Then `./gradlew assembleRelease bundleRelease` produces signed outputs. Keep the keystore safe: Play updates need the same key (or use Play App Signing).

## Documents

- `ARCHITECTURE.md`: layers, data flow, import pipeline, auth, backup, sync.
- `FEATURE_PARITY.md`: every iOS feature and its Android status/test evidence.
- `IMPLEMENTATION_STATUS.md`: what was done, verified, and what is still open.

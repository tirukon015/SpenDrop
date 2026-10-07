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

## How sharing works (Share Target)

SpenDrop registers for the Android share sheet (`ShareActivity`) for `image/*`, `application/pdf` and `text/plain`, single or multiple, plus "Open with" for images and PDFs. It never watches screenshot folders and needs **no storage permission**: Android hands over a temporary content URI, which SpenDrop copies into its private cache immediately. This works with every gallery and file manager (Samsung, Xiaomi, OPPO, Vivo, Pixel, Tecno…). Shared content opens a review screen on top of the app you shared from; after saving you're back where you were, and any unsaved form in SpenDrop itself is left alone.

In the app, Home → scan icon → "Screenshot or Photo" (Android photo picker) or "PDF or File" (file picker) does the same without sharing.

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

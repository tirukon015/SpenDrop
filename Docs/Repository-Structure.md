# Repository structure

SpenDrop is **one product** in **one GitHub repository** with **separate application directories**.

## Before (iOS only, until 7 Oct 2026)

```
SpenDrop/
├── SpenDrop/              iOS app sources
├── SpenDrop.xcodeproj
├── SpenDropUITests/
├── scripts/               Xcode project generator
├── supabase/migrations/   backup SQL
├── docs/
└── README.md
```

A snapshot of that state is kept as branch `standalone-ios-app` and tag `ios-standalone-2026-10-07`.

## After

```
SpenDrop/
├── iOS/                   the native iOS app — moved as-is (git history kept)
│   ├── SpenDrop.xcodeproj
│   ├── SpenDrop/          App, Data, Models, OCR, Views, ShareExtension, Resources
│   ├── SpenDropUITests/
│   └── scripts/
├── WebApp/                Next.js + TypeScript + Tailwind web app (PWA)
├── Common/                platform-neutral contracts
│   ├── Constants/         payment channels, categories, movement kinds, account types, split methods, currencies (JSON)
│   ├── DataModels/        the shared record model (what every client stores/syncs)
│   ├── BusinessRules/     split, balances, settlements, account-vs-channel rules + shared test vectors (JSON)
│   ├── Validation/        input rules (money, dates, text limits)
│   └── Design/            design tokens (colours, radii, typography, navigation)
├── Supabase/
│   └── supabase/migrations/   SQL (CLI layout: `cd Supabase && supabase db push`)
├── Docs/
└── README.md
```

## Why

- **iOS/** — the iOS app is a complete, working, tested product. Moving it into its own folder keeps it intact while
  other clients join. All Xcode paths are project-relative, so the move needed **no project-file changes**; the app,
  Share Extension and device builds, all in-app suites and all UI tests passed from `iOS/`.
- **WebApp/** — the browser client has a different toolchain (Node, Next.js). Keeping it separate means no React in
  the Xcode project and no Swift in the web build. Vercel builds only this folder (Root Directory = `WebApp`).
- **Common/** — not shared *code* (Swift and TypeScript can't share source), but shared *contracts*: the exact enum
  values stored in the database, the financial rules, and JSON test vectors that every platform's tests must pass.
  The Web tests already load these files; the iOS tests can adopt them next.
- **Supabase/** — the backend is shared by all clients, so its migrations live beside them, not inside one app.
  The inner `supabase/` folder keeps the standard Supabase CLI layout.
- **Docs/** — architecture and product documentation for every platform in one place.

## Android (future)

Android is **not** created yet. When it starts it becomes `Android/` (Kotlin, Room, ML Kit, Android share sheet) and
uses the same `Common/` contracts, the same Supabase tables and RLS, and the same sync protocol
(`Docs/Sync-Architecture.md`). Nothing in the backend is iOS- or web-specific.

## Things to know

- `iOS/scripts/generate_xcodeproj.py` is out of date relative to the project; **do not re-run it** (it would drop files
  from targets). Edit the project in Xcode.
- The real `iOS/SpenDrop/Resources/CloudConfig/SupabaseConfig.plist` stays git-ignored (path updated in `.gitignore`).
- `WebApp/.env.local` is git-ignored; only `.env.example` (no real values) is committed.

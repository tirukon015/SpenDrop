# SpenDrop Web App

The responsive web client of SpenDrop — same account, same data, same rules as the iPhone app.
Next.js 16 (App Router, Cache Components), React 19, TypeScript, Tailwind CSS 4, Supabase (Auth, Postgres + RLS,
Storage). Installable as a PWA.

```bash
npm install
cp .env.example .env.local          # public Supabase URL + publishable/anon key
npm run dev                         # http://localhost:3000
NEXT_PUBLIC_SPENDROP_DEMO=1 npm run dev   # explore with synthetic data, no Supabase
```

Checks: `npm run typecheck` · `npm run lint` · `npm test` · `npm run build` · `npm run test:e2e`.

- Architecture: `../Docs/Architecture.md` · Data model: `../Docs/Data-Model.md` · Sync: `../Docs/Sync-Architecture.md`
- Setup & deployment (Supabase migration, auth redirect URLs, Vercel): `../Docs/WebApp-Setup.md`
- Shared rules this app is tested against: `../Common/`

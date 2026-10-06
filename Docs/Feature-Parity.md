# Feature parity (7 Oct 2026)

✅ implemented and tested · 🟡 partial · ❌ not yet · — not applicable

| Feature | iOS | Web | Shared rule / contract | Notes |
|---|---|---|---|---|
| SpenDrop account (sign in/out) | ✅ Google, email + verification | ✅ Google, email sign-in/up, reset | Supabase Auth | Web Google sign-in needs the Web callback URL allow-listed in Supabase (Docs/WebApp-Setup.md) |
| Delete account | ✅ | ✅ (type DELETE) | `delete_my_account()` + file removal | |
| Works without an account | ✅ local-first | — (demo mode for development only) | | The Web App is account-based by design |
| Add / edit / delete expense | ✅ | ✅ | `Data-Model.md` | Web delete = tombstone |
| Money In / Out / own Transfer | ✅ | ✅ | money-movement-kinds.json | Transfers never count as income/spending |
| Funding account vs payment channel | ✅ | ✅ | payment-channels.json, account-types.json | UNKNOWN explicit; never guessed |
| Categories | ✅ | ✅ | categories.json | |
| Search, filters, sort | ✅ | ✅ | QuickDate ranges (Mon–Sun weeks) | Web adds amount range, person, funding, channel filters |
| Splitting: equal / parts / custom | ✅ | ✅ | split-test-vectors.json (15 shared cases) | Exact sen, extra sen to Me when I paid |
| Auto Calculate (default ON, per transaction) | ✅ | ✅ | same vectors | OFF freezes amounts; never global |
| Fixed amounts (pin) | ✅ | ✅ | same vectors | Fixed + equal share of the remainder; not persisted after save (both) |
| Remaining / unassigned validation | ✅ | ✅ | same wording | Save blocked until it adds up |
| Paid for Someone / Someone paid for me | ✅ | ✅ | | |
| Split at import (before first save) | ✅ Share Extension & scan review | ✅ Add form after scanning | | |
| PayBook balances, They Owe Me / I Owe Them | ✅ | ✅ | personBalances (positive = they owe me) | |
| Per-transaction debts, Mark as Paid | ✅ | ✅ | DebtLedger | |
| Record payment, credit, apply credit | ✅ | ✅ | SettlementService | |
| Settle All (assign → offset → pay), Undo | ✅ | ✅ | same algorithm | Web Undo = tombstones |
| PayBook payment details (copy) | ✅ | ✅ | | |
| PayBook photos | ✅ | ❌ | | Device-only on iOS |
| Funding account list + recorded activity | ✅ | ✅ | accountActivity | "Not your bank balance" |
| Home: Today / Week / Month, Cash flow, Balances | ✅ | ✅ | | Web adds category & funding mini-breakdowns on wide screens |
| Breakdown: spending, cash flow, by category/channel/funding, top merchants, daily, comparison | ✅ | ✅ | analytics.ts | |
| OCR of payment screenshots | ✅ Apple Vision | 🟡 tesseract.js | parse rules ported from iOS | Web accuracy on real Malaysian receipts not yet measured; always reviewed before saving |
| PDF receipts | ✅ Share Extension | ❌ | | |
| Share sheet import | ✅ Share Extension | ❌ | | Web Share Target API is a roadmap item |
| Evidence-first category/channel + learning | ✅ | ✅ | classify.ts mirrors iOS | Learned rules sync through the cloud tables |
| Duplicate warnings | ✅ | ✅ (reference / amount+day+merchant) | | |
| Receipts / screenshots stored | ✅ on device (HEIC) | ✅ private bucket (WebP, signed URLs) | | Not shared between platforms yet |
| Sharing | ✅ iOS share sheet | ✅ Web Share API + clipboard | text only, no public links | |
| Cloud backup (snapshots) | ✅ daily, retention, range restore | 🟡 reads iOS backups for import | backups table/bucket | Web data lives in cloud records already |
| Two-way sync iOS ↔ Web | ❌ | ✅ (Web side) | Sync-Architecture.md | iOS sync is the next phase |
| Sample data | ✅ with confirmation | 🟡 skipped on import by default | | |
| Appearance (System/Light/Dark) | ✅ | ✅ | tokens.json | |
| Responsive (phone/tablet/desktop) | — | ✅ | | Playwright tests at 390/820/1366/1920 px |
| PWA (installable, offline page) | — | ✅ | | No offline writes yet |
| Accessibility | ✅ VoiceOver labels | ✅ axe: 0 serious/critical | | |
| Apple Pay automation (Shortcuts) | ✅ | — | | iOS-specific |

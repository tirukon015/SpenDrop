# Backup and sync

## Two different things

| | **Backup** — "I have a safety copy" | **Sync** — "my devices share the same current data" |
|---|---|---|
| Today on iOS | ✅ Daily automatic JSON snapshot to the private `backups` bucket + `backups` row (30/90-day retention). Restore is always explicit (by date range). | ❌ Not implemented. iOS does not read or write the cloud records yet. |
| Today on Web | Uses the iOS backups as an *import source* ("Bring in iPhone data"). | ✅ The Web App reads/writes the cloud records directly; every browser/device signed into the same account sees the same data. |
| Destructive? | Never: restore merges, never deletes. | Never: deletes are tombstones; older writes never overwrite newer ones. |

Backup stays even when sync arrives — they solve different problems.

## How data gets from the iPhone to the Web today

1. iPhone: More → Account → cloud backup (existing feature) uploads a snapshot.
2. Web: **More → Bring in iPhone data** lists those backups (RLS: only your own) and, on your confirmation,
   imports one into the cloud records (`WebApp/src/lib/data/backup-import.ts`):
   - records keep their iOS UUID (lowercased) → re-importing never duplicates;
   - accounts with the same name are merged (like iOS `AccountLinker`);
   - if the cloud copy is newer (`updated_at`), it is kept;
   - sample data is skipped unless you opt in;
   - nothing is ever deleted; missing references become empty links and are counted.
3. Changes made on the Web are **not yet** visible on the iPhone (see "Next: iOS sync").

## Sync protocol (implemented on Web, designed for iOS/Android)

- **Identity:** every record has a stable UUID from the device that created it. Never match records by
  merchant/amount/date (that is duplicate *detection* for new input, not identity).
- **Pull:** per table, `select * where server_updated_at > cursor order by server_updated_at, id` in pages of 1000
  (keyset pagination; rows sharing the boundary timestamp are fetched together). The client stores the max
  `server_updated_at` it has seen per table. RLS limits every query to the signed-in user.
- **Push:** upsert whole records. Expense + shares go through `save_expense_with_shares`, payment + allocations
  through `record_settlement` — atomic, RLS-checked.
- **Conflicts:** last-writer-wins on `updated_at` (the editing device's clock). The server ignores an incoming
  expense whose `updated_at` is older than the stored one. Shares belong to their expense and are replaced with it.
- **Deletes:** set `deleted_at` (+ `updated_at`). Clients have no DELETE permission. Rows are physically removed only
  when the user deletes their account (cascade from `auth.users`). A tombstone is never "restored" automatically.
- **Offline:** the Web keeps a per-user IndexedDB cache (cleared on sign-out) for instant start and offline
  *reading*. Writes require a connection (clear message when offline). An offline write queue is on the roadmap.
- **Attachments:** Web receipts are compressed in the browser (≤1600 px WebP) and stored in the private `receipts`
  bucket at `{user_id}/{expense_id}/{uuid}.webp`; viewed through 10-minute signed URLs; removed when the expense is
  deleted or the receipt replaced.

## Next: iOS sync (planned, not built)

The tables and protocol are ready. The iOS work, in order, without replacing SwiftData:
1. Add `server_updated_at` cursors and a sync queue to the iOS store (additive SwiftData schema V6).
2. Push local changes (expense+shares via `save_expense_with_shares`) and pull remote changes into SwiftData by id.
3. Map tombstones to local deletes (with the same "never silently restore" rule).
4. Keep cloud backup as is. Make first-sync explicit ("Start syncing this iPhone with your SpenDrop account").
5. Then decide whether iOS screenshots join the `receipts` bucket (compressed, opt-in).

## Duplicate prevention

- Stable ids make sync/import idempotent.
- New input is checked like on iOS: same transaction reference = strong duplicate; same amount + day + merchant =
  possible duplicate → the user decides ("Save Anyway").

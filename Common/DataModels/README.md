# Data models

The canonical record model is documented in [`Docs/Data-Model.md`](../../Docs/Data-Model.md) and implemented by:

- the database: `Supabase/supabase/migrations/20261007000000_spendrop_cloud_records.sql`
- iOS: `iOS/SpenDrop/Models/*.swift` (SwiftData)
- Web: `WebApp/src/lib/domain/types.ts`

Entities: **User** (Supabase Auth) · **Account** (funding account) · **Person** (PayBook) · **PersonPaymentMethod** ·
**Expense** · **ExpenseShare** (contributor share) · **MoneyMovement** · **SettlementAllocation** ·
**ClassificationRule** · **ChannelRule** · **Receipt** (Web: `expenses.receipt_path` in the private `receipts` bucket) ·
**Backup** (`backups` table + bucket: iOS snapshots).

Every record carries sync metadata: `id` (stable UUID), `created_at`, `updated_at` (last-writer-wins), `deleted_at`
(tombstone) and, in the cloud, `user_id` + `server_updated_at` (pull cursor). See `Docs/Sync-Architecture.md`.

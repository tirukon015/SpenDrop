# iOS live sync — design

Status: implemented on branch `feature/ios-sync` (not merged, not released). Scope: the existing SwiftUI +
SwiftData app talks to the same Supabase per-record tables the Web App and Android already use
(`20261007000000_spendrop_cloud_records.sql`, `20261008000000_hybrid_split.sql`). Nothing on the server changes.

## 1. What exists today (findings)

| Area | Finding |
|---|---|
| Local store | SwiftData, schema V6 (`Data/SchemaVersions.swift`), App Group store shared with the Share Extension. Safe-open with pre-upgrade snapshots; never deleted. |
| Models | `Expense` (+ cascade `ExpenseShare`), `Account`, `PayBookProfile` (+ cascade `PayBookPaymentMethod`), `MoneyMovement`, `SettlementAllocation`, `ClassificationRule`, `ChannelRule`, `SampleDataRecord` (demo-data register), legacy `PayBookContact`. Every model has a stable `UUID id`. `Account`, `ExpenseShare` and `SettlementAllocation` have **no `updatedAt`**. Money on `Expense` is `Double amount` (converted with `Money.minorUnits`), everywhere else integer minor units. |
| Mutations | Spread over ~40 call sites: views (`ExpensesView`, `ExpenseDetailView`, PayBook views, `MoneyMovementFormView`, Settings "Clear All"), data services (`SplitDraft`, `PersonLedger`, `TransactionReconciliationEngine`, `SampleData`, `UserDataBackupService` import/restore, `AccountLinker`, Bulk Import), and the Share Extension (separate process, same App Group store). Deletes are **hard deletes** (`context.delete`), with cascade/nullify rules. |
| Auth | `AuthService` (@MainActor, @Observable): Supabase Auth over HTTP, session in Keychain, `validAccessToken()` refreshes when < 60 s left; an invalid refresh token signs the cloud session out (local data untouched). |
| Cloud | `CloudBackupService`: append-only JSON snapshots + `backups` rows, opt-in, daily `BGProcessingTask` (`com.spendrop.SpenDrop.dailyBackup`), `NWPathMonitor`. **No live sync on iOS.** HTTP goes through the `HTTPTransport` protocol (fakeable in tests). |
| Web | `SupabaseSource`: pull per table `server_updated_at > cursor` ordered `(server_updated_at, id)`, pages of 1000; plain upserts `on_conflict=id`; expense + shares through `save_expense_with_shares`. |
| Android | `SyncService`: pull all tables, LWW merge on `updated_at` locally, then push records changed since a watermark; bulk upserts with `Prefer: resolution=merge-duplicates`; expenses via the RPC; a failing batch is retried row by row so one bad row can't block the rest. Sample data is never pushed. |
| Server rules | RLS owner-only on every table, `user_id default auth.uid()`, no DELETE grant (deletes = `deleted_at` tombstones), `server_updated_at` set by a trigger (pull cursor). `save_expense_with_shares` ignores a write whose `updated_at` is older than the stored one (LWW) and tombstones shares not in the new list. **Plain upserts are not guarded on the server** — Web/Android avoid clobbering by pulling (LWW-merging) before pushing. |

## 2. Design overview

```
 UI / services ──save()──▶ SwiftData (main store)            ◀── apply pulled rows (sync context, excluded)
                    │ ModelContext.willSave/didSave
                    ▼
            SyncChangeRecorder  (ids + op only, O(changed objects), no I/O)
                    │ Task (utility)
                    ▼
     SyncEngine (actor, ModelActor on the main store + its own outbox store)
        ├─ Outbox (separate SwiftData store "SpenDropSync.store": SyncOperation rows)
        ├─ push: bulk upserts / RPC / tombstone PATCH   ──HTTPTransport──▶ Supabase REST (RLS)
        └─ pull: per-table keyset cursor, page 500, apply in background
                    ▲
            SyncCoordinator (@MainActor, tiny): debounce, NWPathMonitor, foreground/launch,
            BGAppRefresh, backoff timer, SyncStatusModel (published only on change)
```

### Local-first save path
Saving is unchanged: views keep calling `modelContext.save()`. The recorder observes `ModelContext.willSave`
synchronously and only reads `insertedModelsArray / changedModelsArray / deletedModelsArray` → `(table, id, op)`
tuples (no fetches, no encoding). After `didSave` it hands the tuples to the engine on a utility-priority task. The
save call never awaits the network, auth, the outbox write, or JSON encoding. Saves made by the sync engine's own
context are ignored (no echo ops).

Mapping: `Expense`→`expenses`; an `ExpenseShare` change → an op on its parent expense (shares travel with the
expense through the RPC); `Account`→`accounts`; `PayBookProfile`→`people`; `PayBookPaymentMethod`→
`person_payment_methods`; `MoneyMovement`→`money_movements`; `SettlementAllocation`→`settlement_allocations`;
`ClassificationRule`, `ChannelRule`. `PayBookContact` and `SampleDataRecord` are never synced. Sample expenses
(`isSampleData`) are skipped at record time; registered sample records are skipped at send time.

### Outbox (persistent)
Separate SwiftData store in the App Group (`SpenDropSync.store`), so **the user's main schema is not changed (stays
V6; no migration)**. One `SyncOperation` per `(userId, table, entityId)`:
`operation (create|update|delete)`, `status (pending|failed|held)`, `retryCount`, `nextAttemptAt`, `createdAt`,
`changedAt` (time of the latest local change), `lastError`, `attempted` (an upsert was ever sent), `userId`.
An op is removed only after the server confirmed (2xx).

Coalescing (one row per entity):
- CREATE + UPDATE* → one upsert; UPDATE* → one upsert.
- CREATE … DELETE before any send attempt → both dropped (the server never saw it).
- any upsert that was attempted … DELETE → a tombstone.
- DELETE … CREATE (same id re-inserted, e.g. restore/undo) → upsert.
- A new local change resets a failed op to pending.
Payload = the latest local state read **at send time**, so coalescing is trivially correct.

### Deletes / tombstones
iOS keeps its hard deletes (visible UX unchanged); the outbox remembers `(table, id, time)`. The tombstone is a
`PATCH /rest/v1/<table>?id=in.(…)&updated_at=lt.<T>` with `{deleted_at: T, updated_at: T}` — no full row needed, so
it works after the object is gone; the `updated_at=lt.T` filter means a newer edit made on another device is never
tombstoned (LWW). For an expense the shares are tombstoned as well (`expense_shares?expense_id=in.(…)`). PATCHing an
id the server never had touches 0 rows (harmless, idempotent). Mass-delete guard: a single save that deletes more
than 100 synced records (e.g. Settings → "Clear All Expenses") records the tombstones as **held**; they are not sent
until the user confirms in Account → Sync ("Apply held deletions"). Locally the delete happens as before.

### Scheduler (event driven, no polling)
- After a recorded change: debounce 1.5 s (each new change restarts it) → one sync cycle.
- `NWPathMonitor`: offline → no attempts; offline→online → one cycle (pull + push).
- App launch (after the first frame, `Task(priority: .utility)`) and every return to foreground → full cycle.
- `BGAppRefreshTask` `com.spendrop.SpenDrop.sync` (registered next to the daily backup task) → full cycle.
- Backoff: one one-shot timer to the earliest `nextAttemptAt` (no loops).
- Cycles never overlap: the engine is an actor with a `running/rerun` flag; requests during a cycle collapse into
  one follow-up cycle.

### Batching
- Plain tables: bulk `POST /rest/v1/<table>?on_conflict=id` with
  `Prefer: resolution=merge-duplicates,return=minimal`, chunks of 100, in FK order
  (accounts → people → payment methods → expenses → movements → allocations → rules). If a chunk fails with a
  validation error it is retried row by row so one bad row never blocks the others (same as Android).
- Expenses: `POST /rest/v1/rpc/save_expense_with_shares` per expense (atomic expense + split), up to 4 in flight.
- Local objects are fetched by id in chunks of 100 (`#Predicate { ids.contains($0.id) }`); bodies are encoded in
  the engine actor, never on the main thread.
- Idempotency: every row carries its stable UUID; repeating a request (lost response, retry) upserts the same row.

### Conflicts (same rule as Web/Android: last-writer-wins on `updated_at`, the editing device's clock)
- `updated_at` sent = `max(entity.updatedAt, op.changedAt)` (op time for the 3 types without `updatedAt`).
- Before pushing a table the engine pulls that table (incremental cursor). For an entity with a pending op:
  server `updated_at` > `op.changedAt` → the server copy is newer: it is applied locally, the op is dropped and the
  status `conflicts` counter goes up (nothing silently lost: the newer edit wins everywhere, Web/Android agree).
  Otherwise the local pending edit is kept and the pulled row is skipped.
- Expenses are additionally guarded by the RPC on the server. Tombstones by the `updated_at=lt.T` filter.
- Without a pending op: server newer than local `updatedAt` → applied; local newer (edited while sync was off) →
  an upsert is queued.
- Residual race (documented): another device writing a plain-table row between our pre-pull and our upsert
  (milliseconds) is overwritten by our older edit; the same window exists on Web/Android. A server-side guard
  (`updated_at` check in a trigger) would close it — not done here (no server changes in this task).

### Pull
Per table, keyset cursor `(server_updated_at, id)` stored per user:
`GET /rest/v1/<t>?select=*&or=(server_updated_at.gt.C,and(server_updated_at.eq.C,id.gt.I))&order=server_updated_at.asc,id.asc&limit=500`.
Each page is applied in the engine's background context and saved, then the cursor advances (cursor only moves
after the data is safely written). Never the whole table in memory. Tombstones → local hard delete (cascade rules as
the app's own delete); a tombstone for an id we don't have does nothing; never "un-deletes". Local-only fields
(OCR text, image path, underlying bank, matching data) are preserved. Relationships are resolved by id (account,
payer, share person, movement person/expense/accounts); missing references stay nil and keep the name snapshots.
Full pull (all 9 tables) runs on launch, foreground, reconnect, BG refresh, "Sync Now", and at most once a minute
after a push (so Web/Android edits arrive without realtime).

### Realtime
Not implemented (deliberately, to keep risk low): it needs `alter publication supabase_realtime add table …` on
production and a websocket client. Instead: pull on launch, foreground, reconnect, after pushes (throttled) and in
BGAppRefresh. If realtime is wanted later: foreground-only socket, `postgres_changes` filtered by `user_id`, used
only as a trigger for the same incremental pull (never trusting socket data).

### Isolation
- Every request uses the signed-in user's access token (`AuthService.validAccessToken`); the client never sends
  `user_id` (server default `auth.uid()`, RLS enforces owner-only).
- Every op stores the `userId` it belongs to. This iPhone's data is linked to one account (`owner`, like Android);
  ops are recorded for the owner (also while signed out — the queue is kept). A cycle runs only when
  `session.userId == owner`; it selects only ops with that `userId`. Signed in as another account → nothing is
  sent, status "This iPhone's data is linked to another account".
- Signed out → no sync, no requests.

### Status
`SyncStatusModel` (@MainActor @Observable): `state (off | synced | pending | syncing | offline | failed | conflict |
authRequired | otherAccount)`, `pendingCount`, `failedCount`, `heldDeletes`, `conflicts`, `lastSyncDate`,
`lastError`. Assignments happen only when the value changed. Only Account → "Sync across devices" observes it;
expense lists don't.

### Failure handling
| Result | Action |
|---|---|
| 2xx | op removed |
| offline / timeout / URLError network | cycle stops; ops untouched; next attempt when the network returns |
| 5xx, 408, 429 | `retryCount += 1`, `nextAttemptAt = now + min(2^n · 2 s, 15 min) · jitter(0.8…1.2)` |
| 401 | force-refresh the token once and retry the request; still 401 → pause (`authRequired`), ops kept |
| 400 / 409 / 422 / other 4xx | row isolated; op → `failed` with `lastError`, not retried automatically (a new local edit or "Retry" re-queues it); local data kept |

### Startup
Nothing on the launch path: the coordinator starts in the root view's `.task` after the first frame and runs its
first cycle on a `.utility` task. The outbox store opens lazily inside the engine actor.

### Large datasets
Pushes are outbox-driven (only changed ids); pulls are cursor-driven and paged; local objects are fetched by id in
chunks. The only full scan is the one-time bootstrap when sync is first enabled for an account: it reads **ids only**
(chunks of 500) and enqueues them with `changedAt = updatedAt` so a newer server copy still wins.

### Settings
Account → new "Sync across devices" section (signed-in only): toggle (default **on** when signed in, per user),
status line, pending / failed counts, last sync, "Sync Now", "Apply held deletions" (only when there are some).
Signed-out users see nothing new and nothing is recorded or sent. Cloud Backup is unchanged and independent.

## 3. Not done / limitations
- Realtime websocket (see above). Changes from other devices arrive on launch/foreground/reconnect/BG refresh,
  after the next local push (throttled to once a minute), or "Sync Now".
- Receipt images / screenshots are not synced (`receipt_path` is not uploaded from iOS; Web receipts are not
  downloaded).
- `record_settlement` RPC is not used; payments and allocations sync as plain rows (same tables).
- Learned rules: the server enforces one rule per merchant key; a rule created on two devices with different ids
  fails with 409 for the second one (shown as failed; local rule kept).
- Accounts merged by name on the Web during "Bring in iPhone data" keep the Web's id; pushing the iPhone's own
  account id creates a second account row with the same name (no data loss, possible duplicate name).
- The Share Extension (separate process) does not record ops itself; the app catches up on launch/foreground by
  enqueuing records with `updatedAt`/`createdAt` newer than the last catch-up mark.
- The plain-table race described under Conflicts.
- Instruments profiling was not run (headless environment); latency/request counts are measured in the test suite.

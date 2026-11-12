# Driver offline data and automatic synchronization

Updated: 2026-11-11. Source implemented; staging, physical-device background acceptance and deployment remain outstanding. See the [implementation plan](OFFLINE_FIRST_SYNC_IMPLEMENTATION_PLAN.md) and [acceptance report](OFFLINE_SYNC_ACCEPTANCE_REPORT.md).

## Modes and rollout

Servers without synchronization support retain the network-first, read-only fallback. Protocol-capable servers enable immediate saved reads with background refresh. Supported delivery writes use the durable queue when the server allows new commands.

`GET /driver/sync/capabilities` reports `{protocol:1, acceptNewCommands:true|false, offlineWriteMaxAgeHours:24}` when the receipt table exists. An administrator enables new queued actions in **Settings > General > Offline deliveries > Offline delivery recording**. The database value defaults to false; the old environment variable is ignored. Save changes and refresh the mobile app while connected; no backend restart is needed. Existing installations can save this new settings row without reseeding or a schema migration. Disabling the flag preserves processing of existing queued work. Devices reuse their last known policy while disconnected and learn changes on reconnect.

The deployed database must contain `driver_sync_receipts` through its actual migration history. The current consolidated baseline includes this table. Review the target's actual consolidated migration history before deployment. Do not run schema push or replay the baseline against an existing database. This implementation has not migrated any configured/production database.

## Supported workflows

- Downloaded profile, assignment pages/details, history pages/filters and proof metadata remain readable offline.
- Delivered/failed outcomes, photos/signatures and full-order return collection can be saved for downloaded, dispatched active work. Capture alone is a draft; **Save proof** commits durable storage.
- Offline enqueueing requires a remembered verified session, the same API/account scope and an assignment checked within 24 hours. The server rechecks ownership, versions and workflow rules.
- Dispatch/start and skip/prioritize remain online-only. Payments, refunds, stock and warehouse receipt retain existing server/staff workflows.
- Map tiles, road routes and historical GPS replay are outside this feature. Live tracking stops after transport failure establishes offline mode and resumes after recovery.

## Local storage

Drift uses private `hyops_driver_cache.sqlite`. Schema v3 upgrades v1/v2 additively, retaining `driver_read_cache` and the confirmed records/outbox. The v2 tables are confirmed profile/trip/stop/pickup/history records, `sync_outbox`, `local_attachments`, `sync_metadata` and `sync_leases`; v3 adds `local_proof_cache` for downloaded photos. This migration runs only on the phone's local SQLite database and requires no additional backend migration.

Opening **Photos / signature** is independent of permission to record delivery actions. Captured proof files remain readable through both local and server proof IDs. Photos opened online are saved privately for later offline viewing (seven-day expiry, up to 100 MB per account). Photos without a downloaded copy explain the connection requirement. Downloaded caches are removed on logout/access invalidation; pending evidence retains its separate lifecycle. The photo viewer remains accessible in read-only offline mode. The offline banner explains server setup, disabled recording, or a missing remembered session instead of silently disabling all actions. Online refresh rechecks the server capability so enabling synchronization is picked up without requiring a new login.

Existing page snapshots retain endpoint, filter, page, membership and totals. Missing downloaded pages are explicitly unavailable. There is no duplicate `local_query_pages` table: request-keyed snapshots already serve that purpose. Confirmed entities use scoped IDs and JSON payloads; pending overlays stay separate. Older trip versions cannot overwrite newer confirmed versions. Custom SQL emits explicit Drift table-update notifications; resume/polling also requery after native worker activity.

Snapshots normally expire after seven days. Unresolved/unreconciled scopes retain supporting snapshots without extending the 24-hour write eligibility. Pending/quarantined files are never cache-pruned. Acknowledged, reconciled proof files are eligible for cleanup after seven days. Recovery removes unreferenced proof/temp files older than one day, checking references across all accounts first. Missing referenced files become visible errors.

Proofs live in private `driver_proofs`. A flushed temporary file is renamed before a transaction stores file metadata and an upload command. An action reports success only after the SQLite transaction commits. SHA-256 verifies proof bytes before upload; server limits and image normalization still apply. SQLite/private files are not an application-encrypted vault. Android backup is disabled; iOS application-support data is excluded from backup and uses device protection. Credentials remain in device-bound secure storage; iOS background access requires the first device unlock.

## Identity and sessions

Native sessions bind storage to a SHA-256 namespace derived from the full API base and server-verified driver ID. Secure storage preserves the binding across refresh. Legacy token-scoped snapshots can reopen during an old remembered offline session; online validation refreshes data into the verified account namespace.

Revocation clears credentials/visible records and quarantines queued work under its original account/environment. Reauthentication as the same verified driver can resume it after current ownership checks. Logout with pending work offers sync first or explicit discard-and-sign-out. Discard invalidates requests before deleting device copies; accepted server effects remain recorded. Cleanup failure is reported and does not prevent signing out.

## Queue and consistency

Supported writes use the same path online/offline. Each command persists its UUID operation key, payload hash/version, original trip version, dependencies, sequence, frozen send payload, state, retry time and eventual receipt. File metadata and upload commands commit together. Delivery depends on its proof uploads.

`SyncCoordinator` coalesces enqueue, startup/resume, socket, polling and manual triggers. A scoped SQLite lease serializes foreground/background workers and expires after two minutes after process death. The first release drains serially; independent trips continue after a permanent conflict elsewhere. Foreground polling retains the configured interval, default 30 seconds.

Before sending, the coordinator authenticates, resolves prior receipts and reads current assignment state. Only acknowledged local receipts may bridge the original trip version to subsequent commands. Other changes cause a conflict. Frozen requests retain their key/payload after ambiguous failures. Acknowledgment is separate from read reconciliation: refresh failure cannot turn an accepted action back into an unsent write.

Persisted retries use exponential backoff/jitter and honor numeric/HTTP-date `Retry-After`. Transport errors, 429 and selected transient 5xx responses retry. Validation/conflicts require attention; authentication refresh remains coordinated. Queued operations disable generic HTTP POST replay.

The sync panel shows pending work, upload progress, errors, last download/upload times and accepted changes awaiting refresh. Unsent actions can be explicitly discarded. Attempted conflicts/rejections require an authenticated negative receipt check before discard; ambiguous work stays protected. Corrected intent uses a new key. Work approaching 30 days prompts staff review and remains saved. Automatic deletion of unresolved deliveries is disabled pending an approved retention policy.

## Server guarantees

`driver_sync_receipts` stores actor, canonical request hash and minimal accepted result in the same PostgreSQL transaction as each mutation. Advisory operation locks and entity row locks serialize concurrent duplicates. Key reuse with different details rejects. Outcomes/collection return previous/accepted trip versions.

`GET /driver/sync/operations/:key` serves only the originating authenticated actor. Unknown/other actors' keys both return `{accepted:false,result:null}`. Receipt lookup permits acknowledgment after reassignment without granting access to the reassigned trip. Operational POSTs continue to check current ownership. Newly discovered assignment loss removes cached/visible operational details while retaining queued evidence.

## Native background execution

Workmanager is pinned to `0.10.10`. Android schedules network-constrained one-off/15-minute periodic work. iOS processing/periodic identifiers and UIScene/plugin launch handlers are configured. Workers restore their own secure session/database and verify scheduled origin/scope before draining; task input contains no token.

The OS controls execution timing. Foreground resume/restart recovers after force-stop, expiration or missed scheduling. Background timing, signing, locked-device behavior and native plugin operation still require Android/iOS device acceptance. Dart tests do not establish native build or physical background acceptance.

## Verification

From Flutter: `flutter test --no-pub` and `flutter analyze --no-pub --no-fatal-infos`.

From backend: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-database.ps1 -Suite Sync`. This creates a disposable loopback database, verifies the receipt migration and runs driver/return/proof integration suites using the current consolidated schema. The older `Driver` harness references legacy migration files absent from this workspace; it was not used for successful acceptance.

Primary references: [Flutter offline-first support](https://docs.flutter.dev/app-architecture/design-patterns/offline-first), [Drift streams](https://drift.simonbinder.eu/dart_api/streams/), [Workmanager setup](https://docs.page/fluttercommunity/flutter_workmanager/quickstart).

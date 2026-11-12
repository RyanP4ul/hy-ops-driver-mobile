# Offline-first synchronization acceptance

Date: 2026-11-11. Overall status: **PARTIALLY**. Source and automated consistency checks are complete; native builds/device acceptance, staging and deployment are separate pending work.

## Automated evidence

Settings-control follow-up: offline recording is now controlled by the database setting `mobile_offline_delivery_recording_enabled` through **Settings > General > Offline deliveries**. The old environment variable is ignored. The updated disposable database suites report **28 passed / 271 assertions**, including admin authorization, boolean validation, saving without reseeding, optimistic version conflicts, mobile capability changes and existing receipt access after disabling. Two targeted frontend schema tests pass, and changed frontend source files pass ESLint. Full frontend tests/type checking are blocked by existing missing `fleet-map-1` modules, generated validators referencing those modules, and outdated fleet-routing fixtures. The database wrapper emits sandbox permission diagnostics even though all underlying cases passed; no configured database was used.

- Flutter full suite: **110 passed**, including **24 offline-sync/storage tests** and additional offline UI coverage. Latest run completed in approximately 24 seconds.
- Dedicated sync tests use actual on-disk Drift/SQLite databases, close/reopen the database and client, and exercise proof dependencies, sequential outcomes/pickups, lost responses, reassignment, external version conflicts, retries, cross-connection leases, v1 migration, account binding, revocation, rollout disable/drain behavior, local transaction rollback, corruption and reviewed discard.
- Disposable PostgreSQL `-Suite Sync`: 27 tests passed, 255 assertions across driver, customer-return and private-proof suites. It verified the actual additive receipt migration, concurrent duplicate commands, different-payload key rejection, actor isolation, ownership, stock/payment preservation and feature-gate behavior.
- Flutter analyzer passes with `--no-fatal-infos`: **no errors or warnings**; remaining findings are informational style suggestions across existing and changed files.
- Backend TypeScript reports three existing errors in `tests/lalamove.test.ts` (lines 153, 172, 173: NodeNext extension/import.meta configuration). No changed sync source is reported by the check. These unrelated tests were not modified.

Commands:

```powershell
# hyops_flutter
flutter test --no-pub
flutter test --no-pub test/offline_sync_test.dart
flutter analyze --no-pub --no-fatal-infos

# hy_ops/backend
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-database.ps1 -Suite Sync
node ../frontend/node_modules/typescript/bin/tsc --noEmit
```

The new `Sync` harness uses the current consolidated schema because the older `Driver` suite tries to reconstruct migration files no longer present in this workspace. The successful Sync run created a new loopback fixture and stopped it afterward; it did not use configured database credentials or production R2 storage.

## Offline button/photo correction

The photo-screen entry button previously depended on write eligibility, so server-disabled/read-only mode prevented even viewing local proof. Viewing is now independent of recording permissions. Captured proof files can be read through their server IDs after upload, and photos opened online are cached privately for seven days (100 MB per account). The local SQLite schema upgrades v1/v2 to v3 with `local_proof_cache`; queued work is preserved. Downloaded copies clear on logout/access invalidation. No additional PostgreSQL migration was added and no configured database was changed.

Tests cover downloading/opening a photo after a database restart with writing disabled, uploaded proof/server-ID lookup, missing downloads, scope/logout cleanup, v2 queue-preserving upgrade and local pending files when protocol support is absent. UI tests cover opening photos in read-only mode and enabled delivery/failure actions in a remembered, protocol-enabled offline session. The banner now explains offline recording restrictions, and online refresh rechecks changed server capabilities.

Offline delivery writes still require the updated backend, receipt migration, **Settings > General > Offline deliveries > Offline delivery recording**, an updated mobile build and a remembered verified session with downloaded active work. The deployment gate remains off by default. This correction does not activate a running server or deploy a new APK.

## Platform limits

Workmanager `0.10.10` and its transitive native plugins resolved into the lockfile/package configuration. `flutter pub get` subsequently reported Windows desktop symlink/Developer Mode support is unavailable. ADB discovery could not run because the sandbox could not create its Android user directory. Android build/install, actual force-stop/background execution and native secure-storage acceptance were not completed. iOS compilation/signing and locked-device scheduling require macOS and an iOS device.

Source includes Android network constraints/backup exclusion, iOS processing/periodic task identifiers, launch/plugin registration, private support-directory protection, and a headless worker that restores credentials independently and validates origin/scope. These configurations are not evidence of physical background execution.

## Activation and release checklist

1. Review the target's current consolidated Drizzle migration journal and backup. Ensure receipt storage exists through the target's actual migration process. The current consolidated baseline includes it; the earlier incremental `0001_driver_sync_receipts.sql` is no longer present in this workspace. Never replay the baseline or run schema push to force compatibility.
2. Deploy the updated backend with **Offline delivery recording** switched off in Settings initially. Check the authenticated capability response and migration readiness.
3. Rebuild mobile with its native dependencies and correct API/WS settings. Validate remembered startup, camera/signature capture, disk-full handling, account switch/logout and private-file recovery on target devices.
4. In staging, enable **Settings > General > Offline deliveries > Offline delivery recording**; sign in/refresh so mobile learns the policy. Download an active dispatched trip, disconnect, save proof and several outcomes, force-stop/reopen and reconnect. Verify exact server effects, inventory/financial invariants and visible pending-to-confirmed transitions.
5. Test assignment cancellation/reassignment, authentication revocation, multiple workers, iOS expiration/first-unlock and Android power/force-stop/restart behavior. Record platform, app/API version and observed results.
6. Confirm the proposed 24-hour eligibility window and unresolved evidence retention policy with operations. Current source warns near 30 days and preserves unresolved work until explicit review/discard; it never silently expires deliveries.
7. Pilot with selected drivers before wider enablement. Monitor queue depth/age, conflicts, retry errors and acceptance latency without logging tokens/customer payloads/proofs.

Rollback disables new enqueueing while a compatible engine continues processing existing commands. Retain receipt history and the local schema. An older app that cannot read the outbox is not a safe rollback while pending work exists.

No deployment or configured-database change was performed during implementation.

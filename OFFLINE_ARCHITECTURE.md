# Driver offline data

Online requests use the HYOps API first. Drift stores a successful, decoded response so the same view can be read after a connection failure. This is a network-first, read-only offline fallback, as requested; operational actions are never queued or applied locally.

## Stored data

`DriverCacheDatabase` uses Drift's native SQLite executor in a background isolate. The file is `hyops_driver_cache.sqlite` in the app's private application-support directory. Schema version 1 creates one **local** table, `driver_read_cache`:

| Column | Purpose |
|---|---|
| `scope_key` | SHA-256 of API origin plus refresh-session identity; no raw token is written to SQLite. |
| `request_key` | Endpoint and sorted query parameters, including page/date/status filters. |
| `payload` | JSON snapshot of the validated server response. |
| `saved_at` | UTC save time for stale-data labels and seven-day expiry. |

Profile, downloaded trip/history pages, trip details and proof metadata can be read offline. Downloading a trip page also stores each included trip's detail. Missing pages/filters show an unavailable-saved-data message instead of inventing empty records. Expired or corrupt snapshots are discarded. Proof image bytes, map tiles and road geometry are not persisted by this cache.

This does not add or migrate any HYOps backend/PostgreSQL table. The SQLite cache is app-private storage, not an encrypted database; refresh credentials remain in native secure storage.

## Switching modes

- An API connection error or transport timeout without an HTTP response activates offline mode. Wi-Fi presence alone is not treated as proof that the backend is reachable.
- HTTP 401/403/404/500, cancellation and certificate failures do not fall back to cached responses. Unauthorized/inaccessible reads invalidate the relevant session's cache.
- Cached startup requires the same securely remembered session and its previously downloaded profile. It opens a read-only view, not a fresh offline password login. Offline devices cannot discover a new server-side revocation until reconnecting.
- The visible offline banner and saved timestamp explain stale data. Periodic refresh, app resume or **Retry connection** validates the session and reloads data. Actions unlock only after a successful online refresh without cache fallback. A revoked session is cleared instead.

## Actions

Trip start, delivered/failed commands, proof capture/upload and route requests are disabled in offline UI. State/repository guards reject direct calls, and the HTTP layer blocks non-authentication writes while a connection failure is known. There is no outbox, optimistic outcome write or reconnect replay. Existing operation keys still protect an explicit retry after an ambiguous online timeout.

Local browsing, downloaded pagination/filter views, theme preferences, phone-number copy and logout remain available. Logout clears local credentials, visible records and the session's cache even if the server cannot be reached. If cache deletion fails, credentials/scope are still invalidated; the failure is logged. Late network responses cannot repopulate a logged-out scope. GPS and assignment sockets stop in offline mode and resume after online validation.

## Verification

Run `flutter test --no-pub --concurrency=1`. Offline tests use actual Drift/SQLite (including reopening an on-disk database), isolated HTTP adapters and meaningful session/action/layout checks. Android instrumentation also checks saved data after an actual force-stop/relaunch using an intentionally unreachable endpoint, then validates recovery and logout against the disposable backend fixture.

The native Android/iOS transport remains the target; this does not add Flutter web support. Native setup follows the [Drift platform documentation](https://drift.simonbinder.eu/platforms/).

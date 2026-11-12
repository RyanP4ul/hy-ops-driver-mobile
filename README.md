# hyops_flutter

A new Flutter project.

## Connecting to production or local development

With no endpoint configured, the app uses the production HTTP API at
`https://hy-ops-frontend.vercel.app/api`. The frontend forwards `/api/*` to the
Render backend. Live tracking connects directly to
`wss://hy-ops-backend.onrender.com/ws`; the frontend has no `/ws` rewrite.

Create the Flutter asset `.env` before building from a fresh checkout:

```powershell
Copy-Item .env.example .env
```

Set `API_URL` to the full HTTP API base. If it is blank, the app uses
`BASE_URL` with `/api` for the Next.js proxy. If both are blank, it uses the
production default. An explicit compile-time `API_URL` or `BASE_URL` takes
precedence over the bundled values. For a local Next.js proxy, set `WS_URL`
to the backend WebSocket endpoint, such as `ws://localhost:5173/ws` for a
desktop client. The proxy only forwards HTTP API requests. A compile-time
`WS_URL` overrides dotenv, and a compile-time HTTP endpoint without a
compile-time WebSocket override derives its own socket endpoint.
For the Android emulator, use `10.0.2.2` in place of `localhost` in local URLs.
On a physical phone, use the development machine's reachable LAN address.

Rebuild and restart after changing endpoints. Vercel environment variables
apply to the deployed proxy. The bundled Flutter asset is readable by app
users, so it must contain public endpoint settings only.

Run against production explicitly:

```powershell
flutter run --dart-define-from-file=config/production.json
```

Build an installable production APK:

```powershell
flutter build apk --release --dart-define-from-file=config/production.json
```

For local development, edit `config/local.example.json` to use your computer's
LAN address and run:

```powershell
flutter run --dart-define-from-file=config/local.example.json
```

The example connects directly to Bun on port 5173. Local HTTP/WS endpoints are for debug
builds; release builds require HTTPS/WSS. When overriding `API_URL` to point
directly at a backend, omit `/api`; that prefix belongs to the Next.js proxy.

For the deployed proxy, configure Vercel's **Production** environment variable
`NEXT_PUBLIC_BACKEND_URL=https://hy-ops-backend.onrender.com` and redeploy the
frontend after changes. The production backend must include the mobile auth
and `/driver/*` routes. Use a driver account to sign in.

To check the proxy without credentials, open
`https://hy-ops-frontend.vercel.app/api/auth/me`. An unauthenticated JSON **401**
is expected and confirms that the auth endpoint responds. A 404/HTML page,
gateway error, or timeout indicates a routing, deployment, or availability issue.

Endpoint configuration files contain public service URLs only; do not put
passwords, tokens, or server secrets in them.

## Automatic refresh

Offline-first reads, durable delivery/proof/return commands and automatic foreground/native synchronization are documented in [OFFLINE_ARCHITECTURE.md](OFFLINE_ARCHITECTURE.md). Deploy the backend receipt migration first. Enable **Settings > General > Offline deliveries > Offline delivery recording** on the backend after staging/device acceptance; new queued writes default to disabled. Existing queued work can drain while new enqueueing is disabled. Rebuild after `flutter pub get` for Workmanager's native plugins. Windows desktop plugin setup may require Developer Mode; Android/iOS remain the targets. See the [acceptance report](OFFLINE_SYNC_ACCEPTANCE_REPORT.md) for remaining platform checks.

### Immediate delivery assignments

While signed in with the app open, new deliveries, reassignments, cancellations,
and schedule changes arrive through an authenticated WebSocket. The app reloads
the current trip list automatically and shows a dismissible delivery-specific
banner. This is independent of GPS permission.
Disabling in-app notifications hides the banner but still updates the trip list.
Reconnect and resume reconcile missed changes, and the configured polling timer
remains a fallback. This does not implement operating-system push notifications
while the app is closed or suspended.

Deploy the backend migration `0004_driver_assignment_events.sql` through the
configured `bun run db:migrate` command before updating the backend and mobile app.
It installs the assignment trigger in the production migration history; applying
only the legacy `_migrations` directory is not required. The backend PostgreSQL
connection must support `LISTEN/NOTIFY` (use a direct/session connection, not a
transaction-pooling connection). Keep the Render WebSocket endpoint configured
as described above.

After sign-in or restoring a saved session at startup, the app reads
`mobile_automatic_refresh_interval_ms` from the database through the authenticated
`GET /driver/settings` endpoint. Set a positive whole number of milliseconds
(for example, `10000` for 10 seconds). The value controls automatic data refresh
while the app is active; assignment WebSocket events still trigger immediate refreshes.

The interval is reused when the app resumes. Restart the app or sign in again to
load a changed database value. Missing, invalid, zero, or negative values fall back
to 30 seconds. Settings are cached for offline startup; if settings cannot be loaded,
the app uses the 30-second default. Deploy the backend endpoint with the mobile update.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# HYOps Driver — Comprehensive UI/UX Audit & Redesign Plan

**Target App:** `hyops_flutter` (HYOps Driver Mobile Client)  
**Audit Sources:** Screen recording `Recording_2026-11-11_224414.mp4` (`00:00`–`01:04`), static UI preview captures (`.tmp/driver-ui-preview/`, including light/dark & `TripsScreen`), and full codebase review (`lib/` and `test/`).  
**Constraint:** Preserve 100% of existing business logic, offline-first outbox synchronization, proof-of-delivery (POD) gating, Manila (`UTC+8`) schedule handling, and API contracts. **No application code is modified in this phase.**

---

## 1. Executive Summary

HYOps Driver is functionally solid—it supports real-time WebSocket assignment updates, background GPS tracking, grouped multi-order stops, return pickups, POD capture, and an offline-first outbox. However, **the UI currently feels like an internal administrative form ported onto mobile rather than a purpose-built field tool for a delivery driver.**

Across the 65-second video walkthrough and codebase audit, five systemic issues stand out:

1. **Startup State Race & Layout Jumping (`00:06`–`00:11`):** On launch, the home screen visibly flashes a false *"Offline delivery recording is not enabled on the server"* warning and *"No saved trips"* empty state (`00:07`), pops cached trips in (`00:08`), and then teleports `SyncPanel` from the top of the screen to the bottom (`00:09`) when online validation finishes, followed by `TrackingBadge` popping in (`00:10`).
2. **Primary Action Discoverability Failure (`00:29`–`00:33`, `00:41`–`00:48`):** On an active pending stop (`ORD-000002`), the primary delivery button (`Record delivery`) is **completely hidden** until proof is uploaded. The driver only sees four visually identical outlined buttons (`View Road Routes`, `Report Failed Attempt`, `Photos / signature`, `View All Order Items`), giving zero indication of how to complete a delivery.
3. **Deep Accordion Nesting & Technical Clutter (`00:16`–`00:25`, `00:53`):** Grouped stops expose raw 22–25 character internal hashes (`OG-bf9ddc112c51452e8b77`, `CP-cd166275cbe84013aea7d8`) as headlines, nest 3 levels of collapsible cards (`_GroupedStopCard` → `_StopCard` → buttons), repeat customer address/phone/payment disclaimers per order, and surface `SyncPanel` on 4 separate screens.
4. **Fragmented Design System & Mixed Libraries:** `pubspec.yaml` pulls in `forui`, `forui_lucide`, `shadcn_ui` (unused), `lucide_icons_flutter` (unused), and Material 3. Screens mix `FLucideIcons` (thin line icons in bottom nav) with `Material Icons` (thick icons in buttons), mix `Panel` (`8px` radius + border) with sharp-cornered `RecordRow` slabs (`0px` radius, no border), and toggle theme via a `ValueKey` on `MaterialApp` that destroys the entire navigation stack.
5. **Missed Field-Ergonomic Essentials:** Phone numbers copy to clipboard instead of offering one-tap calling (`tel:`), `RoadRouteService` discards OSRM distance and ETA, the map overlays blend white-on-white over street tiles and leave a `36px` transparent gap under the docked bottom card, and `ProfileScreen` omits `notifications` and `keepScreenOn` toggles that already exist in `AppState`.

---

## 2. Detailed Existing UI/UX Analysis (Video + Code Audit)

### 2.1 Video Walkthrough Findings (`00:00`–`01:04`)

| Timestamp | Screen / Flow | Observed Behavior & Issues |
| :--- | :--- | :--- |
| `00:00`–`00:03` | Native Splash | Large centered blue gradient `H` logo (`assets/logo.png`) on pure white background. |
| `00:04`–`00:06` | `DriverLoadingScreen` | Abrupt jump from large native splash logo to a tiny `56px` logo with `"HYOps Driver"`, `"Opening your account..."`, and a `24px` spinner. |
| `00:07` | Home (Initial Frame) | **Severe UX bug:** Flashes amber warning (`Offline delivery recording is not enabled on the server...`), `SyncPanel` (`Not updated yet`), and `"No saved trips"` empty state before cache/capability checks finish. |
| `00:08` | Home (Cache Loaded) | Cached data pops in: `SyncPanel` (`Saved Today, 22:42`) sits **above** `"Next stop"` and `"Assignment"`. |
| `00:09`–`00:14` | Home (Online Validated) | `SyncPanel` disappears from the top and reappears **below** `"Assignment"`, shifting the entire screen upward by ~100px (`HomeScreen` lines 42 vs 122). `TrackingBadge` (`Location shared with dispatch`) pops in at `00:10`. `"truck - ABC-1234"` displays uncapitalized `"truck"`. Progress says `"1 of 2 stops recorded"` while Trip Detail says `"1 of 2 orders recorded"`. |
| `00:15`–`00:18` | `TripDetailScreen` (`Delivery 1`) | Repeats `SyncPanel` at top with dual timestamps (`Last upload Today, 20:52` + `Updated 22:43`). Trip summary omits a progress bar. Stop group header shows raw UUID **`1. OG-bf9ddc112c51452e8b77`** as the primary title. |
| `00:19`–`00:25` | Grouped Stop Expanded | Expanding `ORD-000001` (Delivered) and `ORD-000002` (Pending) inside the group creates 3 nested borders/headers. Raw **`CP-cd166275cbe84013aea7d8 / Original allocation: PHP 0.98`** appears above the delivery address. `"Delivery notes"` uses `SectionTitle` (`20px` bold + `24px` top padding), towering over address and contact details. Delivered `ORD-000001` still displays **`Collect on delivery PHP 29.97`**, `"Staff records payment receipts."`, and active `"Photos / signature"` button. |
| `00:25`–`00:28`, `00:43`–`00:44` | `OrderItemsScreen` | Tapping `"View All Order Items"` from either order opens the same grouped list, only changing sort order. Displays grammatical bugs (`"1 item · 1 units"`, `"Qty: 50 roll"`), unlabeled variant (`"52"`, `"36"`), and omits per-order status badges (`Delivered` vs `Pending`). |
| `00:29`–`00:33` | `ORD-000002` Action Area | **No delivery completion CTA is visible** (`Record delivery` is hidden until proof exists). Four equal-weight outlined buttons (`View Road Routes`, `Report Failed Attempt`, `Photos / signature`, `View All Order Items`) have inconsistent heights (`64px` grid vs `48px` buttons) and inconsistent casing (Title Case vs Sentence Case). Phone `+63-555-0101` only copies on tap. |
| `00:34`–`00:40` | `NavigationScreen` / `RoadRouteMap` | Status pills (`Following location`, `Tap map to hide controls`, `Camera paused`) have white `P.surface` background with zero elevation or border, visually disappearing into bright OSM map tiles so text appears to float raw over streets. When panning (`00:37`), `"Recenter"` shifts layout below the header. **No distance/ETA**, **no fit-route overview**, **no external Maps/Waze launch**, and the bottom `Destination` panel hovers `36px` above the bottom screen edge (`SafeArea(minimum: EdgeInsets.only(bottom: 36))`), letting map tiles leak underneath it. |
| `00:45`–`00:48` | `ProofSheet` | Missing top-right close (`X`) button (unlike `HistoryDetailSheet`). Does not display which order (`ORD-000002` / `Miguel Cunanan`) is receiving proof. Capture buttons (`Camera`, `Choose photo`, `Sign`) wrap into an awkward 2+1 layout. `"Checking saved proofs..."` lacks a progress indicator. |
| `00:51`–`00:54` | `HistoryScreen` & `HistoryDetailSheet` | Repeats `SyncPanel` at top. `"Filter by Manila dates"` uses timezone jargon. List item uses unbordered `RecordRow` slab on `#F3F5F8` bg with 6 stacked lines of redundant text (`Delivered` pill + `"Delivery confirmed"`). Sheet repeats customer name (`Miguel Cunanan`) as header and `Contact`, right-aligns long addresses awkwardly in `KvRow`, wraps `CP-cd166275...` across lines, and formats item names (`Sakolin - 52`) differently than `OrderItemsScreen`. |
| `00:55`–`01:01` | `ProfileScreen` & Sign-Out | Repeats `TrackingBadge` + `SyncPanel` a 4th time. Raw phone `639482734769` lacks formatting. `Appearance` uses three full-width `ListTile` rows instead of a compact segmented control. Missing `Notifications` and `Keep screen on` settings. `Sign out` button is small/under-weighted and its confirmation dialog uses primary indigo instead of semantic destructive styling. |
| `01:02`–`01:04` | `LoginScreen` | Cleanest screen overall, though `"Keep me signed in"` does not explain that it is **required for offline recording** (`app_state.dart` line 64), and two separate error slots exist (`AppScope.error` above email, `_error` below checkbox). |

### 2.2 Evaluation of Current Visual & Interaction Patterns

- **Layouts & Spatial Hierarchy:** `WorkspaceList` (`maxWidth: 1100`) and `WorkspaceColumns` (`>=680px`) provide solid structural intent for tablets/desktops, but on `390px` phones every screen leads with the same unprioritized vertical stack: Heading → `SyncPanel` → controls → full-bleed sharp `RecordRow` slabs or flat `Panel`s.
- **Typography (`T` in `lib/core/palette.dart`):**
  - Only 6 styles exist (`display` 28, `title` 20, `body` 15, `bodyBold` 15, `small` 13, `smallBold` 13).
  - Because there is no intermediate `16px–17px` subheading or `11px–12px` micro/overline style, `SectionTitle` (`20px` + `24px` top padding) is used inside nested order cards (`"Delivery notes"`), competing directly with page-level section headers.
  - Long identifiers (`OG-...`, `CP-...`) and monetary figures (`PHP 1,498.52`) lack tabular numerals (`FontFeature.tabularFigures()`) and clean truncation/copy affordances.
- **Colors & Contrast (`P` in `lib/core/palette.dart`):**
  - Brand indigo (`#3444A5` light / `#495DC5` dark) and slate surfaces (`#F3F5F8` / `#FFFFFF` light, `#111622` / `#1B2230` dark) are clean and professional—not flashy or AI-slop.
  - However, `P.bg` vs `P.surface` separation in light mode is subtle in outdoor sunlight, `StatusPill` uses low-contrast pastel fills (`0xFFDDF1E6`, `0xFFD9F1F6`, `0xFFFFF0C7`) with sharp `4px` corners, and `P.signal` (`#FFC629`) is defined as the "hazard yellow" driver-visibility color in `palette.dart` but is almost completely unused (only in legacy `StopSpine` and `SegmentedProgress`).
  - `P.dark` is a **mutable global static boolean**, forcing `HyOpsApp` to key `MaterialApp` on `ValueKey('${P.dark}:...')`, which tears down the entire app tree on theme changes.
- **Buttons & Controls:**
  - `BigButton` (`56px`, full-width, `8px` radius) vs `FilledButtonTheme` (`52px`) vs `OutlinedButtonTheme` (`48px`) vs `_StopActionGrid` (`minHeight: 64`) vs `SmallAction` (`FButton` from `forui`) produce five different button sizing/styling behaviors.
  - Semantic intent is flat: `Report Failed Attempt` (destructive/exception) looks identical to `View All Order Items` (read-only reference).
- **Forms, Dialogs & Bottom Sheets:**
  - Inconsistent modal framing: `HistoryDetailSheet` has a drag handle + top-right `X` close button + `20px` horizontal padding; `ProofSheet` has a drag handle + **no `X` button** + fixed `0.8` height + `24px` padding; `_OutcomeSheet` has a drag handle + **no `X` button** + `"Go back"` text button; `SyncPanel` `"Saved work"` sheet has **no drag handle** + **no `X` button** + `0.65` height.
  - `SignatureDialog` is locked to a small `300 × 160` box inside `AlertDialog` with no prompt line or responsive sizing.

---

## 3. Existing Flutter Project Architecture Audit

### 3.1 Current File & Responsibility Map

| Layer | Files | Assessment & Findings |
| :--- | :--- | :--- |
| **App Entry & Theme** | `main.dart`, `app.dart`, `core/palette.dart`, `core/theme.dart`, `core/icons.dart`, `core/format.dart` | `app.dart` wraps everything in `FTheme` solely for `SmallAction` (`FButton`). `MaterialApp` `ValueKey` resets routes on theme switch. `core/icons.dart` defines `Ic` via `forui_lucide`, yet screens bypass it with `Icons.*`. `core/format.dart` contains legacy `rm()` naming for PHP currency and lacks singular/plural helpers or phone formatting. |
| **State & Data** | `state/app_state.dart`, `data/models.dart`, `repositories/driver_repository.dart`, `services/assignment_socket.dart`, `services/location_tracking_service.dart` | `AppState._showSaved(startup: true)` notifies listeners with `loggedIn = true; _offlineView = true` **before** reading cached trips or calling `_prepareSync()`, causing the `00:07`–`00:09` screen flicker. `AppState` already maintains `notifications` and `keepScreenOn` booleans (`lines 43, 783–791`), unused by `ProfileScreen`. `Trip` has `kind` (`Multi-delivery` / `Single delivery`), `stops`, `pickups`, `canStartAt()`, `doneCount`, `progress`. `Stop` has `distanceKm` and `etaMin` fields (currently initialized to `NaN`/`0` in `Stop.fromJson`). |
| **Navigation & Shell** | `features/shell/main_shell.dart`, `features/location/location_gate.dart` | Responsive breakpoints exist (`<720` `NavigationBar`, `720–1079` `NavigationRail`, `>=1080` extended `NavigationRail`). `MaterialBanner` for `assignmentNotice` lives outside `Navigator` in `app.dart`, lacks a `"View trip"` action, and pushes the UI down abruptly. |
| **Feature Screens** | `auth/login_screen.dart`, `home/home_screen.dart`, `trips/trips_screen.dart`, `trips/trip_detail_screen.dart`, `trips/order_items_screen.dart`, `trips/proof_sheet.dart`, `trips/delivery_sheets.dart`, `navigation/navigation_screen.dart`, `navigation/road_route_map.dart`, `navigation/route_service.dart`, `history/history_screen.dart`, `history/history_detail_sheet.dart`, `profile/profile_screen.dart` | `trip_detail_screen.dart` is 705 lines mixing trip header, pickups, grouped stop accordion, stop accordion, payment math, and button grids. `stop_spine.dart` (320 lines) is dead/legacy code with no active route (referenced only by `test/multiple_customer_orders_test.dart`). `RoadRouteService` parses `geometry.coordinates` from OSRM but discards `routes[0].distance` and `routes[0].duration`. |
| **Shared Widgets** | `widgets/common.dart`, `widgets/driver_ui.dart`, `widgets/payment.dart`, `widgets/sync_panel.dart`, `widgets/tracking_badge.dart`, `widgets/workspace.dart` | `SegmentedProgress` and `IconTile` in `common.dart` are unused in active screens. `RecordRow` lacks outer framing/radius when used standalone on `P.bg`. `SyncPanel` embeds full telemetry everywhere. |
| **Dependencies (`pubspec.yaml`)** | `forui`, `forui_lucide`, `shadcn_ui`, `lucide_icons_flutter` | `shadcn_ui` and `lucide_icons_flutter` are **completely unused** in `lib/`. `forui` is used in only 2 lines (`app.dart` + `SmallAction` in `common.dart`). |

### 3.2 Compatibility & Business Logic Constraints to Preserve

Any UI/UX redesign **must preserve**:
- **Manila Time (`UTC+8`):** `manilaSchedule()` and `Trip.canStartAt()` departure gating on scheduled Manila date/time.
- **Grouped Stop Planning:** `deliveryStopGroups()` grouping strictly by `orderGroupId` (never by customer or payment), and `planGroupedOrder(tripId, stopId, skip: ...)` server persistence.
- **POD Requirement Gate:** Delivery confirmation (`recordOutcome` without reason) must remain gated on verified/saved proof (`ProofSheet` → `_OutcomeSheet` or pre-uploaded proof), preserving idempotency operation keys (`_operationKeys`).
- **Offline Capability & Sync Safety:** `offlineActionRestriction` messaging when server offline writes are disabled or `"Keep me signed in"` (`Remember me`) is unchecked, `discardUnsent` confirmation, and `Sign out` pending-work warning.
- **Return Pickups & Warehouse Return:** Explicit *"Retrieve goods only. No cash collection or refund"* guardrail, confirmation dialog (`Confirm goods collected`), and `returning` trip state (`Route to warehouse`).
- **Financial Transparency:** Order total, paid amount, collect-on-delivery (`collectNow`), and `"Staff records payment receipts"` policy, plus combined payment attribution (`combinedPaymentNumber`, `combinedPaymentAllocation`) kept accessible (just formatted cleanly).
- **Existing Test Suite Hooks:** `test/driver_ui_test.dart`, `test/mobile_acceptance_test.dart`, `test/pod_delivery_flow_test.dart`, `test/grouped_delivery_stops_test.dart`, `test/order_items_screen_test.dart`, `test/customer_return_ui_test.dart`, `test/road_route_camera_test.dart`, and `test/multiple_customer_orders_test.dart`.

---

## 4. Redesign Guidelines & Unified Design System

### 4.1 Aesthetic Direction ("Calm Field Utility" — Anti-AI-Slop)

Design for a driver checking the app **one-handed in bright daylight or inside a cab between stops**.
- **Do:** Flat crisp surfaces (`elevation: 0` on lists/cards; `elevation: 2–3` only on floating map controls and modal sheets), hairline `1px` borders (`line`), clear typographic hierarchy, immediate primary CTAs, generous `48dp+` tap targets, and high-contrast semantic pills.
- **Do NOT:** Use decorative gradients, glowing shadows, floating multi-colored dashboard KPI tiles, excessive corner rounding (`>16px` cards or `>12px` buttons), gratuitous micro-animations, or generic SaaS hero illustrations.

### 4.2 Unified Library & Icon Strategy

1. **Standardize on Material Design 3:** Build all buttons, segmented controls, dialogs, sheets, and switches directly on Material 3 (`FilledButton`, `OutlinedButton`, `TextButton`, `SegmentedButton`, `SwitchListTile`, `NavigationBar`, `NavigationRail`).
2. **Remove Unused / Redundant UI Dependencies (Phase 1):**
   - Remove `shadcn_ui` and `lucide_icons_flutter` from `pubspec.yaml` (0 usages in `lib/`).
   - Migrate `SmallAction` (and legacy `StopSpine` if retained for tests) from `forui`'s `FButton` to Material `OutlinedButton.icon`, and remove `FTheme` from `app.dart`.
3. **Single Icon Family (`Ic` in `lib/core/icons.dart`):**
   - Route **100% of app icons** through `Ic` (backed by `forui_lucide` `FLucideIcons`—clean, uniform `2px` stroke weight) instead of mixing `FLucideIcons` and `Icons.*`. Add missing glyphs (`camera`, `image`, `signature`/`penTool`, `refreshCw`, `close`/`x`, `alertTriangle`, `copy`, `externalLink`, `phoneCall`, `mail`, `lock`, `eye`, `eyeOff`, `calendar`, `wifiOff`, `slidersHorizontal`, `bell`, `sunProtection`/`monitorSmartphone`, `maximize2`, `checkCircle2`).

### 4.3 Color System (Reactive `ThemeExtension` / `ColorScheme`, No Global `P.dark`)

Replace mutable `P.dark` static state with an immutable `HyOpsColors` `ThemeExtension<HyOpsColors>` attached to both `lightTheme` and `darkTheme` in `MaterialApp(themeMode: ..., theme: ..., darkTheme: ...)`.

| Token | Light | Dark | Usage |
| :--- | :--- | :--- | :--- |
| `bg` | `#F4F6F9` | `#0F141E` | Scaffold canvas |
| `surface` | `#FFFFFF` | `#18202E` | Cards, rows, sheets, nav bar |
| `surfaceSubtle` | `#EEF2F7` | `#20293A` | Nested summary strips, item quantity chips, filter well |
| `ink` | `#131C2B` | `#F1F5F9` | Primary headings, customer names, amounts |
| `muted` | `#475569` | `#9FB0C7` | Labels, timestamps, supporting text (WCAG AA `>=4.5:1`) |
| `line` | `#D5DEE8` | `#2E3A4E` | `1px` borders and dividers |
| `controlLine` | `#7D8DA1` | `#62738D` | Input outlines, unselected toggles |
| `primary` | `#2F42A3` | `#5B72E8` | Primary actions, active stop outline, selected nav |
| `primarySoft` | `#E8ECFF` | `#232F54` | Active card tint (`Next stop`), nav indicator, active chip |
| `onPrimary` | `#FFFFFF` | `#FFFFFF` | Text/icons on `primary` |
| `success` / `successSoft` | `#166534` / `#DCFCE7` | `#4ADE80` / `#133122` | Delivered, live GPS connected, fully paid |
| `info` / `infoSoft` | `#0369A1` / `#E0F2FE` | `#38BDF8` / `#0E2D3D` | In progress, returning, grouped stop, Net 30 |
| `warn` / `warnSoft` | `#92400E` / `#FEF3C7` | `#FBBF24` / `#382A0E` | Collect on delivery, scheduled, skipped, offline warning |
| `danger` / `dangerSoft` | `#B91C1C` / `#FEE2E2` | `#F87171` / `#3D1A1A` | Failed attempt, cancelled, GPS off, destructive sign-out |

### 4.4 Typography, Spacing & Shape Scale

- **Typography (`HyOpsText`):** Enable `FontFeature.tabularFigures()` on currency amounts, order numbers, counts, and timestamps.
  - `pageTitle`: `26sp`, `w700`, height `1.15`, tracking `-0.4`
  - `sectionTitle`: `18sp`, `w700`, height `1.25`, tracking `-0.2`
  - `cardTitle`: `16sp`, `w600`, height `1.3` (used for group headers, subheadings like `Delivery notes`)
  - `body`: `15sp`, `w400`, height `1.4`
  - `bodyStrong`: `15sp`, `w600`, height `1.4`
  - `caption`: `13sp`, `w500`, height `1.35`, color `muted`
  - `badge`: `12sp`, `w700`, height `1.2`, tracking `0.1`
- **Spacing Grid:** `4 / 8 / 12 / 16 / 24 / 32`. Section gap `24px`, card internal padding `16px`, card stack gap `12px`, phone page gutter `16px`, tablet/desktop gutter `24–28px`.
- **Radii:** Controls/buttons/inputs `8px`, Cards/Panels/Dialogs `12px`, Bottom sheets top radius `16px`, Status badges `6px`, Map control pills `999px` (capsule) with `1px` `line` border + subtle shadow.
- **Touch & Accessibility:** Minimum interactive target `48 × 48dp`; primary bottom/field action `52px` height; zero horizontal truncation of critical order/amount strings (`Wrap` / flexible columns tested at `320px` width + `1.6x` text scaling).

### 4.5 Standardized Button & Component Hierarchy

| Variant | Component | Visual Rule | Allowed Usage |
| :--- | :--- | :--- | :--- |
| **Primary CTA** | `AppButton.primary` | Filled `primary`, `52px` height, `8px` radius, full width on mobile | 1 per screen/card (`Continue trip`, `Start trip`, `Complete delivery`, `Confirm delivery`, `Sign in`) |
| **Secondary Action** | `AppButton.secondary` | Outlined `1px` `controlLine`, `surface` bg, `48px` height | Supporting actions (`Directions`, `Order items`, `Proofs`, `Call`) |
| **Tonal / Utility** | `AppButton.tonal` | Filled `primarySoft`, `primary` ink, `48px` height | Map `Recenter`, `Resume order` |
| **Destructive / Exception** | `AppButton.dangerOutline` / `danger` | Outlined `danger` (`48px`) for `Report failed attempt`; Filled `danger` for confirming failure or destructive sign-out | Failure reporting & destructive dialogs only |
| **Tertiary** | `TextButton` | `48px` min target, `primary` or `muted` ink | `View all trips`, `Skip for now`, `Clear filters`, `Cancel` |

---

## 5. Screen-by-Screen & Feature Redesign Plan

### 5.1 Startup, Native Splash & Session Loading (`main.dart`, `app_state.dart`, `driver_ui.dart`)

- **Problems Found:**
  1. `00:04`–`00:06`: Large native splash logo shrinks abruptly to a `56px` logo in `DriverLoadingScreen`.
  2. `00:07`–`00:11`: `AppState._showSaved(startup: true)` notifies UI with `loggedIn = true` and `_offlineView = true` **before** SQLite cached trips and `_prepareSync()` metadata load, causing a jarring 3-step flash (`No saved trips` + false offline-writes warning → cached trips + top `SyncPanel` → `SyncPanel` jump to bottom).
- **Redesign Solution:**
  - **Essential:** In `AppState.initialize()` / `_showSaved(startup: true)`, hydrate `driver`, `currentTrips`, `trips`, `history`, `lastSynced`, and cached `syncSupported`/`offlineWritesEnabled` metadata (`restoreSync()`) **atomically in memory before flipping `initialized = true`** (or keep `DriverLoadingScreen` visible until the single cached snapshot is ready). Never transition to `MainShell` with empty `trips` and stale `_offlineView` flags.
  - **Essential:** Match `DriverLoadingScreen` logo size (`96px`) and background cleanly to `flutter_native_splash.yaml` (`#FFFFFF` light / `#0F141E` dark) with an inline progress bar or calm `"Loading your shift..."` status so the handoff feels seamless.

### 5.2 Authentication (`LoginScreen` — `01:02`–`01:04`)

- **Problems Found:**
  1. `"Keep me signed in"` does not inform the driver that offline recording requires it (`app_state.dart` line 64).
  2. Two disconnected error areas (`AppScope.error` at top, `_error` above Sign In button) can clash or repeat.
- **Redesign Solution:**
  - **Essential:** Consolidate session-expired / login-validation feedback into **one single `FeedbackStrip`** directly above the primary `"Sign in"` button (and keep `"Retry saved session"` integrated inside that banner when `restorePending` is true).
  - **Essential:** Replace plain `"Keep me signed in"` checkbox label with title `"Keep me signed in"` + subtitle `"Required to record deliveries when offline"`.
  - **Optional:** Trim redundant `"staff"` copy (`"Sign in with credentials issued by HYOps dispatch."` + `"Need access or a password reset? Contact dispatch."`).

### 5.3 Location Gate (`LocationGate` / `_LocationOffPage`)

- **Problems Found:** Good functional gating, but lacks visual parity with redesigned `AppButton` / `Panel` and does not distinguish *GPS service disabled* vs *App location permission denied* clearly when permission is revoked later.
- **Redesign Solution:**
  - **Essential:** Use consistent `12px` card container or clean centered `420px` layout with semantic `warnSoft` icon badge (`Ic.locationOff`), clear bullet explaining *why* (dispatch tracking + road routing), `AppButton.primary('Open location settings')`, and `AppButton.secondary('Check status')`.

### 5.4 App Shell, Navigation & Global Status (`HyOpsApp`, `MainShell`, `SyncPanel`)

- **Problems Found:**
  1. `MaterialApp(key: ValueKey('${P.dark}:...'))` destroys the entire widget tree and pops active routes when changing appearance in Profile!
  2. `AssignmentSocket` notice uses a raw top `MaterialBanner` outside `Navigator` with only `"Dismiss"` and no tap-to-view action.
  3. `SyncPanel` is repeated verbatim on Home, Trips, History, and Profile, consuming ~80–120px of screen height and creating redundant `"Up to date / Last upload / Updated"` lines.
- **Redesign Solution:**
  - **Essential:** Remove `P.dark` from `MaterialApp`'s key (key only on account/session state if needed, or let `Consumer`/`AnimatedBuilder` drive `themeMode` cleanly via `ThemeData` light & dark). Switching themes stays smooth on the Profile tab.
  - **Essential — Collapse Healthy `SyncPanel` into a Global App Bar / Status Strip:**
    - Extract a compact **`GlobalStatusChip`** (or slimmer header status row) shown when healthy: e.g., `● Live · Synced 22:43` with a `48dp` refresh icon button—**no separate `Last upload` vs `Updated` duplication**.
    - Expand into a prominent **`SyncAttentionBanner`** **only** when at least one actionable condition exists: `isOffline`, `pendingSyncCount > 0`, `syncing`, `hasOldWork`, `attentionCount > 0`, or `error != null`. Keep its position **pinned consistently at the top** below the header across tabs so content never teleports top-to-bottom (`00:08`→`00:09`).
    - Upgrade the `"Saved work"` bottom sheet inside `SyncPanel` with a proper modal header (`Saved offline work` + close `X` button + drag handle) and clear status pills per queued item.
  - **Essential — Actionable Assignment Banner:** Replace plain `MaterialBanner` with a compact themed top banner (`primarySoft` / `infoSoft`) showing the message (`"New delivery #14 assigned"`) + **`Open`** button (navigates to `TripDetailScreen` or `Trips` tab and dismisses) + **`Dismiss`**.
  - **Optional:** Show an active badge dot or count on the `Trips` destination in `NavigationBar` / `NavigationRail` when a trip is `inProgress` or `loading`.

### 5.5 Home / Shift Dashboard (`HomeScreen` — `00:07`–`00:14`)

- **Problems Found:**
  1. `SyncPanel` changes position based on `isOffline`, causing layout jumps.
  2. `"Next stop"` card shows `"ORD-000002"` without indicating it belongs to a **grouped stop (`2 orders at this stop`)** or showing quick `Call` / `Directions` buttons equally.
  3. `"Assignment"` card says `"1 of 2 stops recorded"` (inconsistent with `"orders recorded"` in `TripDetailScreen`), `"truck - ABC-1234"` (lowercase), and splits `"View all trips"` below the card.
- **Redesign Solution:**
  - **Essential — Fixed Top-to-Bottom Priority Order:**
    1. **Header Row:** `"Your shift"` + driver name (`Jhon Elizer Belmonte`) on left; compact sync/GPS status pill + refresh icon on right.
    2. **Sync/Offline Attention Banner (conditional, always pinned above content — never below).**
    3. **Primary Hero Card — `Next stop` (or `Next task`):**
       - Clear top label row: `NEXT STOP` (or `SCHEDULED DEPARTURE` / `RETURN TO WAREHOUSE`) + `Grouped · 2 orders` badge if grouped + `Stop X of Y`.
       - Bold customer name (`Miguel Cunanan`), readable street address, and order badge (`ORD-000002`).
       - High-clarity **Collection Strip** (`warnSoft` when `collectNow > 0`, `successSoft` when `Fully paid`, `infoSoft` when `Net 30`): e.g. `Collect on delivery` → **`PHP 1,498.52`** (tabular bold).
       - **Action Row:** Full-width `AppButton.primary` (`Continue trip` / `Open trip` / `Start trip`), followed by a clean 2-button secondary row: **`Directions`** (`NavigationScreen`) + **`Call`** (`tel:` if phone present).
    4. **Active Return Pickup Alert Card (if `pickup != null`):** Framed `Panel` (not raw unbordered `RecordRow`) with `Return pickup` warn pill + `"Retrieve goods only — no cash or refund"`.
    5. **Current Assignment Summary Card:** Framed `Panel` with `"Delivery 1"`, `StatusPill.trip`, `Truck · ABC-1234` (sentence-cased vehicle type), `Warehouse A · Today, 8:04 PM (Manila)`, `SegmentedProgress` bar (reusing the existing `SegmentedProgress` widget!) with unified progress wording (`"1 of 2 stops"` or `"1 of 2 orders"` consistently), and inline `"All trips →"` header action.
    6. **Live GPS Sharing Footer Strip:** Compact `TrackingBadge` integrated cleanly at bottom (or combined into header/status drawer without pushing cards).

### 5.6 Trips List (`TripsScreen` — verified in `trips-390-light.png`)

- **Problems Found:**
  1. Trip rows use unbordered sharp-cornered `RecordRow` slabs on `P.bg` with a trailing `Divider()`.
  2. Each row lacks a progress indicator bar and vehicle/time hierarchy; `SegmentedButton` (`width: 360`) can clip or look misaligned on `320px` phones.
  3. Pagination footer (`Previous` / `Page 1` / `Next`) offers no total count context.
- **Redesign Solution:**
  - **Essential:** Replace `RecordRow` + `Divider` with spaced `Panel(radius: 12)` cards (`12px` gap) matching Home! Inside each trip card:
    - Top row: `Delivery #1` + `StatusPill.trip` on left; Manila schedule (`Today, 8:04 PM`) on right.
    - Middle: `Truck · ABC-1234` · `Warehouse A`.
    - Bottom: `SegmentedProgress` bar + `1 of 2 orders recorded` (+ `1 return pickup` pill if any) + chevron.
  - **Essential:** Make `SegmentedButton` (`Current` | `Past trips`) `ConstrainedBox(maxWidth: 360)` with `width: double.infinity` on narrow phones so it fills `320px` cleanly without overflowing.
  - **Optional:** Show total trip count next to the segment switch (`3 trips`) and show `"Showing 1–20 of 45"` in pagination when `tripTotal > 20`.

### 5.7 Trip Detail & Grouped Stops (`TripDetailScreen`, `delivery_stop_groups.dart` — `00:15`–`00:33`)

- **Problems Found (Highest-Impact UX Bottleneck in the App):**
  1. **Hidden Delivery CTA (`trip_detail_screen.dart` line 609):** `Record delivery` only renders if `stop.hasProof || stop.hasLocalProof`! If proof is not uploaded yet, the driver sees **zero** completion button.
  2. **Raw UUID Headlines (`00:16`):** Grouped stop title displays `1. OG-bf9ddc112c51452e8b77`.
  3. **3-Level Deep Nested Accordions (`00:18`–`00:24`):** Expanding a group and two orders creates massive vertical scroll with ambiguous boundaries between `ORD-000001` and `ORD-000002` action buttons.
  4. **Inconsistent Completed Order State (`00:21`–`00:24`):** Delivered `ORD-000001` still highlights `Collect on delivery PHP 29.97` in large `20px` text and shows `Staff records payment receipts.` and active proof upload UI.
  5. **Technical Payment Jargon:** `Combined payment: CP-cd166275cbe84013aea7d8 / Original allocation: PHP 0.98` clutters every grouped/combined order above the customer's address.
  6. **Uneven Action Grid (`_StopActionGrid`):** `64px` 2-column grid for `View Road Routes` + `Report Failed Attempt`, then `48px` full-width `Photos / signature`, then `48px` full-width `View All Order Items`. `Report Failed Attempt` uses neutral indigo instead of danger styling.
  7. **No Tap-to-Call:** Phone button only copies to clipboard (`Icons.copy_outlined`).
  8. **Dead Legacy File:** `stop_spine.dart` (320 lines) is unreferenced in routing.
- **Redesign Solution:**
  - **Essential — Flatter, Scannable Manifest Hierarchy:**
    - **Trip Header Card:** Status pill (`In progress`), formatted vehicle (`Truck · ABC-1234`), `Warehouse A · Today, 8:04 PM (Manila)`, `SegmentedProgress` bar, and accurate metric summary: `1 of 2 orders recorded` (+ `PHP 1,498.52 remaining to collect` computed cleanly from pending stops' `collectNow`, or return pickup count). Keep `Start trip` / `Route to warehouse` clearly docked inside this summary card.
    - **Human-Friendly Grouped Stop Header:** Replace `1. OG-bf9ddc112c51452e8b77` with:
      - Primary title: **`Stop 1 · Miguel Cunanan`** (with `Grouped · 2 orders` badge).
      - Subtitle: Shared street address (`McArthur Highway, Ilang-Ilang, Guiguinto, Bulacan, 3015`) + progress (`1 of 2 orders done`). Put short group reference (`Group #bf9ddc` or expandable metadata) as muted secondary caption—never the headline.
      - Shared Stop-Level Actions (when all orders share address/contact): **`Route to stop`** + **`Call`** + **`View all items (51)`** at the group level so they aren't repeated 2–3 times inside each order!
    - **Clean Per-Order Sub-Cards Inside a Group (Max 2 Visual Levels):**
      - Use a `surfaceSubtle` inner container with `1px` border and a distinct `3px` left accent bar (`primary` for `Delivering next`, `success` for `Delivered`, `warn` for `Skipped`, `danger` for `Failed`) so drivers immediately see where one order ends and the next begins.
      - **Auto-collapse completed orders (`Delivered` / `Failed` / `Cancelled`)** by default (allowing tap-to-inspect read-only summary + `"View proofs"`), keeping only the active/next pending order expanded!
      - **Clean Completed Order Card:** For `Delivered` orders, display `Delivered · Today, 8:52 PM` and summarize payment quietly as `Order PHP 29.99 · Paid PHP 0.02 (Balance PHP 29.97 handled by staff)` instead of shouting **`Collect on delivery PHP 29.97`**.
      - **Clean Active Order Card Layout (Top-to-Bottom):**
        1. Header: `ORD-000002` + `StatusPill` (`Pending` / `Delivering next`) + optional `Skip for now` / `Deliver next` pill button.
        2. Contact & Address (omitting redundant address if identical to parent group header, or shown once cleanly): Recipient + **`Call` icon button** (`tel:` via `url_launcher`) + **Copy** icon button.
        3. **Collection Box (`warnSoft` / `infoSoft`):** `Collect on delivery` → **`PHP 1,498.52`** (`Partially paid` pill) + `Order PHP 1,499.50 · Paid PHP 0.98`. Move `"Staff records payment receipts"` + combined payment details (`Combined payment: CP-... · Allocation: PHP 0.98`) into a collapsible/compact `"Payment breakdown"` row or subtle muted footnote rather than blocking the top of the card.
        4. **Delivery Notes Callout (`16px` cardTitle, NOT `20px` SectionTitle):** Highlighted subtle `surfaceSubtle` quote strip (`Note: test 123`) when non-empty.
        5. **Clear Guided Action Stack (Consistent `48–52px` Heights):**
           - **Primary CTA (`AppButton.primary`, `52px`):** Always visible!
             - If proof already exists (`stop.hasProof || stop.hasLocalProof`): **`Complete delivery`** (opens `_OutcomeSheet` or `showDeliverySheet`).
             - If proof is missing: **`Add proof & deliver`** (with subtle helper `"Photo or signature required before confirmation"`), launching `showDeliverySheet` (`ProofSheet(requiredForDelivery: true)` → `_OutcomeSheet`)! This completely eliminates the hidden-button confusion!
           - **Secondary Row (2 equal `48px` buttons):** `Directions` (`NavigationScreen`) | `Items` (`OrderItemsScreen`).
           - **Tertiary / Exception Row (2 equal `48px` buttons):** `Proofs (0)` (`ProofSheet`) | `Report failed` (`AppButton.dangerOutline`).
  - **Optional (Cleanup):** Archive or delete unused `lib/features/trips/stop_spine.dart` after migrating `test/multiple_customer_orders_test.dart` to test `TripDetailScreen` / `_GroupedStopCard`.

### 5.8 Order Items Manifest (`OrderItemsScreen` — `00:25`–`00:28`, `00:43`–`00:44`)

- **Problems Found:**
  1. `"1 item · 1 units"` and `"Qty: 50 roll"` grammar issues.
  2. Bare variant (`"52"`) has no context label.
  3. Order headers don't display order status (`Delivered` vs `Pending`), making it impossible to tell which items still need handing over on a grouped stop.
  4. Excessive vertical whitespace per item row.
- **Redesign Solution:**
  - **Essential:**
    - Header: Show human-friendly title (`Stop items · Miguel Cunanan`, with `Grouped · 2 orders · 51 units` pill and short group ref `OG-bf9ddc...` in caption).
    - Order Section Headers: Add `StatusPill.stop(order.status)` (`Delivered` vs `Pending`) right next to `ORD-000001` / `ORD-000002`, and fix pluralization (`1 item · 1 unit`, `50 rolls`).
    - Compact Item Row (`12px` vertical padding inside a `Panel`): Product image thumbnail (or `48 × 48` muted package placeholder when `imageUrl == null`), **`Sakolin`** (`bodyStrong`), **`Variant: 52 · SKU: HY-SK52`** (`caption`), and a right-aligned prominent quantity badge **`1 roll`** / **`50 rolls`** so drivers can scan quantities down the right column at a glance.

### 5.9 Road Route & Live Map (`NavigationScreen`, `RoadRouteMap`, `RouteService` — `00:34`–`00:40`)

- **Problems Found:**
  1. `RoadRouteService` discards OSRM `distance` and `duration`, leaving the driver with zero ETA/distance info.
  2. White status pills (`Following location`, `Tap map to hide controls`, `Camera paused`) have no border or shadow, blending into OSM white map tiles (`00:35`–`00:39`).
  3. Bottom `Destination` panel sits inside `SafeArea(minimum: EdgeInsets.only(bottom: 36))`, leaving a raw `36px` transparent gap where map tiles show underneath the bottom panel (`00:35`–`00:40`).
  4. Missing external navigation handoff (`Google Maps` / `Waze`), missing `"Fit full route"` overview toggle, and missing tap-to-call from destination card.
- **Redesign Solution:**
  - **Essential:**
    - **Upgrade `RouteResult` in `route_service.dart`:** Parse `routes[0]['distance']` (meters) and `routes[0]['duration']` (seconds) from the same OSRM call (zero extra network requests!) so `NavigationScreen` displays **`4.2 km · ~12 min`** in the destination sheet!
    - **Fix Overlay Contrast:** Give top status pills (`Following location` / `Camera paused` + `Tap map to hide`) `surface` background with `1px` `line` border, `elevation: 2`, and capsule radius (`999px`) so they stay legible over bright OSM streets in both light and dark modes. Replace `"Tap map to hide controls"` stacked box with a clean dismissible/subtle icon toggle (`eyeOff` / fullscreen button) OR subtle single-line pill so it doesn't crowd `"Main Bridge"` / road names.
    - **Fix Bottom Destination Sheet Docking:** Remove `minimum: EdgeInsets.only(bottom: 36)` float gap! Dock the bottom sheet flush to the bottom edge with `16px` top rounded corners, `1px` top border, and subtle shadow, and position `RichAttributionWidget` cleanly right above the sheet's top-right corner (`bottom: sheetHeight + 8`)!
    - **Destination Card Actions:** Display Customer name + `ORD-000002`, Distance/ETA badge (`4.2 km · ~12 min`), Address, and two `48px` quick action buttons: **`Open in Maps`** (external turn-by-turn URI `geo:` / Google Maps / Waze) + **`Call`** (`tel:` if phone available).
    - **Map Controls Cluster (Bottom-Right above sheet):** `Recenter` (when paused or always accessible) + **`Fit route`** (`LatLngBounds.fromPoints(route)` camera fit) so the driver can inspect the destination pin and full route immediately.
    - **Dark Mode Map Support (Optional):** Apply subtle dark-mode color matrix filter on OSM `TileLayer` when `Theme.of(context).brightness == Brightness.dark` so night driving doesn't blind the driver with bright `#FFFFFF` map tiles.

### 5.10 Proof of Delivery & Signature (`ProofSheet`, `SignatureDialog` — `00:45`–`00:48`)

- **Problems Found:**
  1. No close (`X`) button on top-right of `ProofSheet`.
  2. Sheet does not state which order (`ORD-000002` — `Miguel Cunanan`) the driver is capturing proof for.
  3. Capture buttons wrap unevenly (2 on row 1, 1 on row 2).
  4. `"Checking saved proofs..."` has no loading spinner; saved items show raw `'photo - 2026-11-11T...'` strings instead of formatted time + thumbnail/preview indicator.
  5. `SignatureDialog` is fixed `300 × 160` inside an `AlertDialog`, cramped on fingers.
  6. Delivered/completed stops (`stop.isDone`) still show enabled capture buttons inside `ProofSheet`.
- **Redesign Solution:**
  - **Essential:**
    - Standardize modal header: Drag handle + title (`Proof of delivery` / `Proofs · ORD-000002`) + customer subtitle + top-right `X` close icon button.
    - Replace `Wrap` of 3 capture chips with an **equal 3-column action grid** (`Camera` | `Gallery` | `Sign`) using `48–56px` tall bordered tiles with centered icon + label (`Expanded` row, wrapping cleanly to stacked rows only at `textScale > 1.5` or `<340px` width).
    - **Hide/disable capture controls when `stop.isDone`** (read-only proof viewer for already completed stops!).
    - Show a compact `CircularProgressIndicator` (`16px`) beside `"Checking saved proofs..."` while `_loading` is true.
    - Format saved proof rows nicely: `Photo 1` / `Signature` + Manila formatted timestamp (`Today, 10:44 PM`) + upload status badge (`Synced` green vs `Pending upload` amber) + thumbnail/preview button.
    - Add a prominent `"Retake / Discard"` icon next to `"Save proof"` when previewing `_draft` before upload.
  - **Essential — Responsive `SignatureDialog`:** Make signature pad fill available dialog width (up to `520px` width × `220px` height) with a dashed baseline (`Sign on the line`), subtle `"Customer signature"` watermark hint that fades on first stroke, `Clear`, `Cancel`, and `Use signature`.

### 5.11 Delivery Confirmation & Failed Attempt (`delivery_sheets.dart`)

- **Problems Found:**
  1. `_OutcomeSheet` lacks a top-right `X` button and uses plain unstyled text for `"Confirm that all listed goods..."` and `"Saved actions remain pending..."`.
  2. `_OutcomeSheet` for failed attempts provides only a blank `Reason` text box with no quick-pick common driver failure reasons!
- **Redesign Solution:**
  - **Essential:**
    - Unified sheet header (`Confirm delivery` / `Report failed attempt` + top-right `X` button).
    - Order summary card showing `ORD-000002`, customer name, address, item count/list, and **payment reminder pill** (reusing `PaymentBanner` / `collectNow` reminder on Confirm Delivery so the driver double-checks COD cash before tapping Confirm!).
    - On Failed Attempt: Add **single-tap quick reason chips** (`Customer unreachable`, `Wrong / incomplete address`, `Refused delivery`, `Business closed`, `Damaged goods`) that prefill/append into the existing `Reason` `TextField` (preserving arbitrary `maxLength: 500` input and backend validation!). Use `AppButton.danger` for `"Submit failed attempt"`.

### 5.12 History & History Detail (`HistoryScreen`, `HistoryDetailSheet` — `00:51`–`00:54`)

- **Problems Found:**
  1. `SyncPanel` consumes top space.
  2. `"Filter by Manila dates"` sounds overly technical; stacked 1-column filters waste vertical space.
  3. History rows use unbordered `RecordRow` slabs and repeat status twice (`Delivered` pill + `"Delivery confirmed"`).
  4. `HistoryDetailSheet` repeats `Miguel Cunanan` as title and `Contact`, wraps `CP-cd1662...` awkwardly in `KvRow`, and uses inconsistent item formatting.
- **Redesign Solution:**
  - **Essential — Compact Horizontal Filter Bar:**
    - Put `Outcome` chip/dropdown and `Date range` button side-by-side (`Row` with `Expanded` widgets on phone, collapsing cleanly only at large text scale). Rename `"Filter by Manila dates"` → **`Date range`** (with `PHT` subtitle inside picker/chip when selected, e.g., `Nov 1 – Nov 11 (PHT)`), and show a compact `Clear` chip when active.
  - **Essential — Scannable History Cards:**
    - Use `Panel(radius: 12)` cards (`12px` spacing) showing:
      - Row 1: `Miguel Cunanan` + `ORD-000001` on left | `StatusPill` (`Delivered` / `Failed` / `Cancelled`) on right.
      - Row 2: Compact address (2-line ellipsis).
      - Row 3: `Delivery #1` · `Today, 8:52 PM` on left | `PHP 29.99` (or item count `1 item`) on right.
      - Omit redundant `"Delivery confirmed"` line when `success == true` (only show failure/cancellation reason strip when `reason != null`).
  - **Essential — Cleaner `HistoryDetailSheet`:**
    - Deduplicate `Contact` when `e.contact == e.customer` (only show `Contact` row if different from recipient/customer name).
    - Replace right-aligned `KvRow` for long `Address` with a top-down full-width block (`Address` label + left-aligned multi-line address) + `Call` / `Copy` phone row.
    - Match item list styling with `OrderItemsScreen` (product + variant + `×1`).
    - In `PaymentPanel`, move `Combined payment` + `Original allocation` into a clean expandable or secondary muted row with `SelectableText` / shortened display + copy icon so long `CP-...` IDs don't distort key-value rows.

### 5.13 Profile & Settings (`ProfileScreen` — `00:55`–`01:01`)

- **Problems Found:**
  1. Repeats `TrackingBadge` + `SyncPanel` at full height.
  2. `639482734769` is unformatted; `Vehicle: Assigned per trip` adds zero information.
  3. Three tall `ListTile`s for `Appearance` (`System` / `Light` / `Dark`) waste vertical space.
  4. `AppState.notifications` and `AppState.keepScreenOn` exist in `AppState` but have **no UI toggles** in Profile.
  5. `Sign out` button is small/outlined, and its confirmation dialog uses primary indigo instead of semantic danger styling.
- **Redesign Solution:**
  - **Essential:**
    - **Driver Identity Card:** Initials avatar (`JB`), `Jhon Elizer Belmonte`, `Driver ID #9`, formatted phone (`+63 948 273 4769`), and live shift status (`Location shared with dispatch` badge integrated directly inside the status section without duplicating `SyncPanel`).
    - **Appearance (`SegmentedButton<AppThemeMode>`):** Compact 3-segment control (`System` | `Light` | `Dark`) inside a labeled settings `Panel`—consistent with `TripsScreen`!
    - **Driver Preferences Panel:** Expose **`Assignment alerts`** (`SwitchListTile` wired to `state.notifications` / `state.toggleNotifications`) and **`Keep screen on during routes`** (`SwitchListTile` wired to `state.keepScreenOn` / `state.toggleScreenOn`, noting wakelock package as optional enhancement if native keep-awake is desired).
    - **Session Panel / Sign Out:** Full-width `AppButton.dangerOutline('Sign out')` with clear caption (`"Stops dispatch location sharing until next sign-in"`). Update sign-out `AlertDialog` primary button to `AppButton.danger` (red) so destructive confirmation is unambiguous.

---

## 6. Reusable Component Architecture (`lib/widgets/`)

Consolidate duplicated and inconsistent UI primitives into a clean, documented component library compatible with existing tests:

| New / Refactored Component | Location | Replaces / Consolidates | Key Props & Behavior |
| :--- | :--- | :--- | :--- |
| `HyOpsTheme` + `HyOpsColors` | `lib/core/theme.dart`, `lib/core/palette.dart` | Mutable `P.dark`, `FTheme` | `ThemeExtension<HyOpsColors>`, `lightTheme()`, `darkTheme()`, `AppText` styles with `tabularFigures`. Keep `P` & `T` thin compatibility shims if needed during migration. |
| `AppButton` | `lib/widgets/common.dart` | `BigButton`, `SmallAction` (`FButton`), ad-hoc `FilledButton` / `OutlinedButton` | Variants: `primary`, `secondary`, `tonal`, `danger`, `dangerOutline`, `text`. Unified `48px` / `52px` heights, `8px` radius, loading spinner support (`busy` prop). |
| `AppCard` (refactored `Panel`) | `lib/widgets/common.dart` | `Panel`, `RecordRow`, sharp list slabs | `12px` radius, `1px` `line` border, `0` elevation, optional `accentColor` left strip (`3px`) or `highlighted` (`primarySoft` border) for active stop. |
| `StatusBadge` (refactored `StatusPill`) | `lib/widgets/common.dart` | `StatusPill`, raw status strings | `6px` radius, optional leading dot/icon, `Tone` (`neutral`, `green`, `info`, `warn`, `danger`), guaranteed `>=4.5:1` contrast in light & dark. |
| `SyncStatusBanner` | `lib/widgets/sync_panel.dart` | Always-expanded `SyncPanel` | `compact` mode (header pill + single refresh button when healthy) vs `expanded` banner mode (offline/pending/error/uploading). |
| `AppBottomSheet` | `lib/widgets/common.dart` | Ad-hoc sheet headers across `ProofSheet`, `_OutcomeSheet`, `HistoryDetailSheet`, `SyncPanel` | Shared modal shell: drag handle, header title + optional subtitle + `X` close button (`tooltip: 'Close'`), `SafeArea`, keyboard inset handling, `680px` desktop max width. |
| `CallCopyPhoneRow` | `lib/widgets/common.dart` | Copy-only `TextButton.icon` / `SelectableText` | Displays formatted phone number + primary `Call` (`tel:`) action + secondary `Copy` button with toast feedback. |
| `AmountSummaryStrip` | `lib/widgets/payment.dart` | Inline `Collect on delivery` rows + `PaymentPanel` | Standardized semantic payment callout (`Collect PHP X` warn strip vs `Fully paid` green vs `Net 30` info) + collapsible/tidy combined-payment metadata. |
| `EmptyStateView` | `lib/widgets/driver_ui.dart` | `DriverEmptyState` | Centered/bounded icon tile (`48px` `surfaceSubtle`), title, helpful body text, optional primary/secondary retry CTA. |

---

## 7. Phased Implementation Roadmap & Acceptance Criteria

> **Priority Legend:** `P0` = Critical usability/bug fix (Essential) · `P1` = High-impact UX/consistency (Essential) · `P2` = Visual polish & maintainability (Essential) · `Optional` = Nice-to-have enhancement beyond core scope.

### Phase 0 — Startup Stability & Reactive Theme Foundation (`P0`, Essential)
*Goal: Eliminate the `00:07`–`00:11` startup flicker and stop `MaterialApp` from destroying navigation state on theme changes.*
1. **[P0] Atomic Cached Startup Hydration (`lib/state/app_state.dart`):**
   - In `initialize()` and `_showSaved(startup: true)`, await `restoreSync()` and load `profile`, `trips`, `currentTrips`, `history`, and `lastSynced` **before** calling `_notify()` with `loggedIn = true; initialized = true`.
   - Keep `DriverLoadingScreen` displayed until cached state + sync capability flags are populated (eliminates the false `"Offline delivery recording is not enabled"` banner and `"No saved trips"` flash at `00:07`).
2. **[P0] Reactive `ThemeData` without `MaterialApp` Key Reset (`lib/app.dart`, `lib/core/palette.dart`, `lib/core/theme.dart`):**
   - Introduce `HyOpsColors` `ThemeExtension` and provide `theme`, `darkTheme`, and `themeMode` directly on `MaterialApp`.
   - Remove `P.dark` from `MaterialApp`'s `ValueKey` so toggling Light/Dark/System in `ProfileScreen` preserves the navigation stack smoothly.
3. **[P1] Seamless Splash-to-Loader Transition (`lib/widgets/driver_ui.dart`, `flutter_native_splash.yaml`):**
   - Harmonize dark splash color (`#0F141E`) and align `DriverLoadingScreen` logo sizing (`96px`) and spacing.

*Phase 0 Acceptance Criteria:*
- Cold launch with cached session never flashes `"No saved trips"` or a false offline-writes restriction banner.
- Switching between `System`, `Light`, and `Dark` in Profile updates colors immediately without resetting scroll position or navigator state.

---

### Phase 1 — Design System Tokens, Shared Primitives & Package Cleanup (`P1`, Essential)
*Goal: Establish one consistent Material 3 component and icon system across the app.*
1. **[P1] Unify Icons (`lib/core/icons.dart`):**
   - Expand `Ic` (backed by `forui_lucide`) to cover all app icons (`camera`, `image`, `penTool`, `refreshCw`, `x`, `alertTriangle`, `copy`, `externalLink`, `phoneCall`, `mail`, `lock`, `eye`, `eyeOff`, `calendar`, `wifiOff`, `bell`, `smartphone`, `maximize2`, `checkCircle2`), eliminating mixed `Icons.*` usage across features.
2. **[P1] Consolidate Primitives (`lib/widgets/common.dart`, `lib/widgets/workspace.dart`, `lib/widgets/driver_ui.dart`):**
   - Build `AppButton`, `AppCard`, `StatusBadge`, `AppBottomSheet`, `CallCopyPhoneRow`, and `EmptyStateView`.
   - Update `RecordRow` or replace standalone usages with `AppCard` so lists never render sharp `0px` unbordered white blocks on gray backgrounds.
   - Refactor `SmallAction` to use Material `OutlinedButton.icon` instead of `forui`'s `FButton`, and remove `FTheme` from `lib/app.dart` (and `test/driver_ui_test.dart`, `test/mobile_acceptance_test.dart`).
3. **[P2] Remove Unused Dependencies (`pubspec.yaml`):**
   - Remove `shadcn_ui`, `lucide_icons_flutter`, and `forui` (keeping `forui_lucide` for `Ic` or migrating `forui_lucide` → `lucide_icons_flutter` consistently—keep `forui_lucide` since `Ic` already uses it!).
4. **[P2] Formatting Helpers (`lib/core/format.dart`):**
   - Rename `rm()` → `formatPhp()` (keeping `rm` as deprecated alias until callers migrate), add `pluralize(int count, String singular, [String? plural])`, `formatVehicle(String type, String plate)` (capitalizing `"truck"` → `"Truck"`), `formatPhoneDisplay()`, and `shortRef()` for long hash IDs.

*Phase 1 Acceptance Criteria:*
- Zero references to `shadcn_ui` or `forui` `FTheme`/`FButton` remain in `lib/`.
- All icons across Auth, Shell, Home, Trips, Trip Detail, Map, History, and Profile share one consistent stroke family (`Ic`).
- Contrast ratios for all text, buttons, and `StatusBadge` variants exceed `4.5:1` in both Light and Dark themes.

---

### Phase 2 — Navigation Shell, Global Sync Status & Auth/Gate Flows (`P1`, Essential)
*Goal: Eliminate screen-by-screen sync chrome repetition and make top-level entry points cohesive.*
1. **[P0] Refactor `SyncPanel` into Contextual Banner + Compact Header Status (`lib/widgets/sync_panel.dart`, `lib/features/*`):**
   - Remove full-height `SyncPanel` from the body of `HomeScreen`, `TripsScreen`, `HistoryScreen`, `TripDetailScreen`, and `ProfileScreen`.
   - Render `SyncStatusBanner` **pinned consistently at the top** only when offline, syncing, pending sync, or error exists; show a subtle, compact `"Synced 22:43"` + refresh button in the page header/app bar when healthy.
   - Apply `AppBottomSheet` styling to the `"Saved work"` inspector sheet.
2. **[P1] Actionable Assignment Notice (`lib/app.dart`, `lib/services/assignment_socket.dart`):**
   - Replace raw `MaterialBanner` with a styled in-app notification banner containing **`Open`** (navigates to `Trips` / `TripDetailScreen`) and **`Dismiss`**.
3. **[P1] Polish `LoginScreen` & `LocationGate` (`lib/features/auth/login_screen.dart`, `lib/features/location/location_gate.dart`):**
   - Unify `LoginScreen` errors into one `FeedbackStrip`; add `"Required for offline delivery recording"` helper subtitle under `"Keep me signed in"`.
   - Restyle `_LocationOffPage` with `AppButton` and clearer status feedback.

*Phase 2 Acceptance Criteria:*
- `HomeScreen` never shifts cards top-to-bottom when transitioning from cached startup to live connection.
- Healthy online screens regain ~80–100px of vertical above-the-fold space previously occupied by duplicate `SyncPanel` blocks.

---

### Phase 3 — Core Driver Workflow: Home, Trips, Trip Detail & Order Items (`P0`–`P1`, Essential)
*Goal: Make the active stop, grouped orders, cash collection, and delivery completion immediately obvious and one-handed.*
1. **[P0] Surface Guided Delivery CTA on `TripDetailScreen` (`lib/features/trips/trip_detail_screen.dart`):**
   - Always render the primary button for actionable in-progress orders: **`Complete delivery`** (when proof exists) or **`Add proof & deliver`** (when proof is not yet uploaded, opening `showDeliverySheet` so proof capture flows directly into confirmation).
   - Give `Report failed` semantic `dangerOutline` styling, standardize all secondary action heights to `48px`, and normalize button labels to clean sentence case (`Road route`, `Order items`, `Photos & signature`, `Report failed`).
2. **[P0] Flatten Grouped Stops & Humanize IDs (`lib/features/trips/trip_detail_screen.dart`):**
   - Replace raw `OG-...` title with **`Stop X · Customer Name`** (`Grouped · N orders` pill + short ref in muted caption).
   - Lift shared stop address, group contact call/copy, and `Order items` access to the parent group header; auto-collapse completed (`isDone`) orders; style completed order financials cleanly without shouting `"Collect on delivery"`.
   - Tuck `CP-...` combined payment allocation into a compact expandable `"Payment details"` row inside `AmountSummaryStrip`.
   - Demote `"Delivery notes"` from `20px` `SectionTitle` to a clean `13–15px` callout strip.
3. **[P1] Redesign `HomeScreen` & `TripsScreen` (`lib/features/home/home_screen.dart`, `lib/features/trips/trips_screen.dart`):**
   - Upgrade `HomeScreen` `Next stop` card with grouped-order badge, high-clarity COD highlight, and side-by-side `Directions` + `Call` secondary actions; embed `SegmentedProgress` in the Assignment summary card.
   - Replace `RecordRow` + `Divider` in `TripsScreen` with `AppCard` items containing `SegmentedProgress` and Manila timestamps; make `SegmentedButton` responsive at `320px`.
4. **[P1] Polish `OrderItemsScreen` (`lib/features/trips/order_items_screen.dart`):**
   - Add `StatusPill.stop(order.status)` per order section, fix `"1 units"` / `"50 roll"` pluralization, label variants (`Variant: 52`), and format compact rows with right-aligned quantity pills.
5. **[P2] Legacy Cleanup (`lib/features/trips/stop_spine.dart`):**
   - Retire or delete unused `StopSpine` after updating `test/multiple_customer_orders_test.dart` to verify `TripDetailScreen` grouped/multi-order rendering.

*Phase 3 Acceptance Criteria:*
- A driver opening an active pending order immediately sees a prominent primary CTA (`Add proof & deliver` or `Complete delivery`) without needing to guess that proof unlocks delivery.
- Raw `20+` character `OG-...` / `CP-...` hashes never appear as primary titles.
- Completed orders collapse cleanly and no longer present `"Collect on delivery"` as an active action.

---

### Phase 4 — Field Execution: POD, Outcome Confirmation & Road Map (`P0`–`P1`, Essential)
*Goal: Improve speed, error clarity, and usability on-site at the customer's door and on the road.*
1. **[P0] Fix `RoadRouteMap` & `NavigationScreen` (`lib/features/navigation/navigation_screen.dart`, `road_route_map.dart`, `route_service.dart`):**
   - Extend `RoadRouteService` to return `RouteResult(points, distanceMeters, durationSeconds)` from existing OSRM response.
   - Add border + `elevation: 2` to map overlay pills (`Following location` / `Camera paused`), remove the `36px` bottom `SafeArea` float gap beneath the docked destination sheet, and place OSM attribution above the sheet cleanly.
   - Add **`Fit route`** overview control and **`Open in Maps`** external navigation handoff (`url_launcher`, `Optional` package dependency—strongly recommended for turn-by-turn voice nav).
2. **[P1] Upgrade `ProofSheet` & `SignatureDialog` (`lib/features/trips/proof_sheet.dart`):**
   - Adopt `AppBottomSheet` (title + order/customer context + `X` close button), balanced 3-column capture grid, loading spinner while fetching proofs, formatted timestamps, discard draft button, and read-only lock when `stop.isDone`.
   - Enlarge `SignatureDialog` canvas responsively (`width <= 520`, `height: 220`) with a baseline guide.
3. **[P1] Upgrade Outcome Confirmation (`lib/features/trips/delivery_sheets.dart`):**
   - Add `AppBottomSheet` header, `PaymentBanner` COD verification reminder on `Confirm delivery`, and one-tap quick failure reason chips (`Customer unreachable`, `Address not found`, `Refused delivery`, `Closed`, `Damaged`) on `Report failed attempt`.

*Phase 4 Acceptance Criteria:*
- Map status pills remain legible across street tiles; bottom destination panel docks cleanly with zero transparent map bleed beneath it; distance and ETA display on load.
- `ProofSheet` always identifies the target order and displays loading/status states clearly; `Required` flow still strictly enforces `pod_delivery_flow_test.dart` rules.

---

### Phase 5 — History, Profile, Optional Enhancements & Verification (`P1`–`Optional`)
1. **[P1] Compact `HistoryScreen` & `HistoryDetailSheet` (`lib/features/history/history_screen.dart`, `history_detail_sheet.dart`):**
   - Place `Outcome` filter and `Date range` side-by-side; rename `"Filter by Manila dates"` → **`Date range`** (with `PHT` chip label); switch list rows to `AppCard`; deduplicate `"Delivered"` / `"Delivery confirmed"` and `customer` / `contact`; left-align multi-line address in detail sheet.
2. **[P1] Streamlined `ProfileScreen` (`lib/features/profile/profile_screen.dart`):**
   - Add initials avatar + formatted phone; replace 3 `ListTile`s with `SegmentedButton<AppThemeMode>`; expose `Assignment alerts` (`state.notifications`) toggle; elevate `Sign out` to full-width `dangerOutline` button with semantic `danger` confirmation dialog.
3. **[Optional Enhancements — Require Explicit Scope / New Packages]:**
   - **One-Tap Phone Calling & External Map Launch (`url_launcher`):** Enable `tel:` dialing from `CallCopyPhoneRow` and external Google Maps / Waze launch from `NavigationScreen`.
   - **Native Screen Wakelock (`wakelock_plus`):** Connect `AppState.keepScreenOn` toggle in `ProfileScreen` to keep screen awake during `NavigationScreen` / active delivery shifts.
   - **History Search Input:** Client-side or query-backed search by customer name or order number (`ORD-...`) on `HistoryScreen`.
   - **Dark Map Tile Filter:** Color-filtered dark OSM presentation in `RoadRouteMap` when dark theme is active.

*Phase 5 & Final Verification Checklist:*
- Run `flutter analyze --no-fatal-infos` (0 errors, 0 warnings).
- Run full `flutter test` suite (update widget/golden/UI tests only for changed button labels/primitives while keeping all business-logic assertions intact).
- Capture and visually inspect rendered screenshots at:
  - `320 × 568` at `1.6x` text scaling (Light & Dark)
  - `390 × 844` standard phone (Light & Dark)
  - `800 × 700` tablet rail (Light & Dark)
  - `1280 × 800` wide desktop rail + 2-column workspace (Light & Dark)
- Verify offline-first flows (offline read-only vs offline write queued, pending sync drawer, proof required gate, grouped skip/resume, return pickup confirmation) and check TalkBack/Semantics focus order across every modal sheet and screen.

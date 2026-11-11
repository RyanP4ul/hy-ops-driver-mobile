# HYOps Driver UI/UX redesign

## Audit and scope

The Flutter driver client uses a Material navigator, AppScope/AppState and repositories for driver API reads and writes, secure session storage, cached read-only offline data, assignment sockets and GPS. The adjacent operations frontend is outside this app. Drivers sign in with staff-issued credentials. Location availability gates the online app. Assignments can be scheduled, started, delivered or reported failed, and returned to the warehouse. Proof requires existing upload/validation before delivery confirmation. Return pickup collection is a separate confirmation. Staff records payments and warehouse receipt.

The shell repeats a one-column phone layout on wide devices. Home places greeting and connectivity before the next task. Trips and History use individually framed cards, with filters and paging separated from the records. Trip detail puts a dense stop action stack after item and payment details. Proof, outcome and history surfaces use different framing, error treatment and hierarchy. Profile mixes account, appearance, tracking and session actions.

## Direction and specifications

Design for a driver checking the app between stops. Answer, in order: what should I do next, which trip am I on, and is the information current? Use the current assignment as the dashboard anchor. Display only operational metrics already supplied by the app. Show recorded stops against total and use Manila time for schedules and date filters. Surface stale/offline status and provide a refresh action. Use the existing brand asset, platform sans typography (28 page, 20 section, 15 content, 13 supporting), 4/8/12/16/24/32 spacing, 8px control corners and mostly flat surfaces. Use indigo for actions, slate for structure, and semantic text paired with success, warning or error color. Provide light and dark palettes, visible focus, wrapping labels and 48px interactive targets.

## Page and component inventory

| Surface | Redesign |
| --- | --- |
| Session loading, sign-in and saved-session retry | Bounded credential form, inline validation and contextual session feedback. Preserve remembered account and autofill. |
| Location gate | Centered explanation and clear settings/recheck actions. |
| Shell and assignment notice | Four stable destinations. Bottom bar on phones, rail on tablets, labeled rail on laptops/desktops. Keep assignment notice actionable. |
| Home, sync panel and tracking badge | Next task beside assignment context on wide screens; stacked by priority on phones. Group connection and GPS feedback. |
| Trips | Current/past switch, grouped scan-friendly assignment rows, progress and paging. |
| Trip detail, stop expander, return pickups | Route manifest with distinct assignment summary, stops and return tasks. Keep contact, items, collection amount, proof and outcome available. |
| Road navigation and road map | Preserve map controls and live route behavior. Put destination and route status beside the map where room permits. |
| Delivery proof, camera/gallery, signature dialog | Group capture methods, upload status and saved proofs. Keep required proof gating. |
| Delivery confirmation, failed attempt and collection confirmation | Identify the order before confirmation. Keep reason validation and busy protection. |
| History, filters, date picker, pagination | Group filters, show result count, and use consistent outcome labels and list rows. |
| History details and payment widgets | Separate delivery metadata, items and payment. Preserve combined payment allocation. |
| Profile | Separate identity, appearance, tracking and sign out. Confirm sign out. |
| Shared primitives | Standardize buttons, panels, statuses, empty states, banners, sheets and focus. Legacy StopSpine has no active route and shares these primitives. |

## Responsive and quality requirements

Use compact 16px gutters on phones and 24–32px elsewhere. Constrain reading widths, keep the map flexible, and switch to two columns only when each has enough room. Bound sheets on desktop and keep keyboard insets and scrolling on mobile. Verify light/dark, long labels, large text, narrow widths, touch and keyboard access. Cover cached/offline states, refresh, assignment navigation, delivery proof and failure flows, return pickups, history filters and profile. Record actual verification and gaps below.

The shell switches to a rail at 720 logical pixels and expands the rail at 1080. Content columns use the available width after navigation and gutters, and fall back to one column at enlarged text sizes. Trip details use a wider summary alongside the stop manifest where possible. The road route places destination details beside the map at 900 logical pixels and below it on smaller screens.

## Progress

- [x] Audit route tree, shared UI, state and workflow entry points.
- [x] Establish page strategies and responsive design system before editing.
- [x] Implement shared system, navigation and account entry points.
- [x] Implement dashboard, assignment list, history and profile.
- [x] Implement trip details, map and proof/outcome surfaces.
- [x] Run final static and regression checks and record verification.

## Verification

- `flutter test --no-pub` passed all 62 tests. `flutter analyze --no-pub --no-fatal-infos` completed with no errors or warnings and 73 informational lints.
- Reviewed Flutter fixture renders at 390 × 844 and 1280 × 800 in light and dark themes. The review led to narrower trip filters, horizontally grouped trip records, a clearer stop action order and fewer controls on single-page history results.
- Expanded the existing UI checks to cover the phone bar, tablet rail and desktop rail, 320 × 568 at 160% text, 390 × 844, 800 × 700 and 1280 × 800 in both themes. Also covered password keyboard submission with missing fields and opening and closing a populated history record.
- Calculated contrast for the primary button text, secondary text on its base surface, and text on the success, info, warning and error status backgrounds in both themes. These tested pairs meet 4.5:1.
- Fixture tests cover assignment refresh and state, offline data, return pickup confirmation, proof validation, delivery outcomes, history filtering and map camera interactions.
- Physical-device camera/GPS, screen-reader behavior and live-backend acceptance remain unverified in this workspace. The Android device query was blocked when ADB tried to write its configuration outside the workspace.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter (Android-only for now) app for ordering a made-to-measure Sudanese jalabiya. Customers save body sizes for
themselves and family, design the robe on a 3D figure, pick a tailor and send the order; tailors confirm with a price and
date (or ask for a change / decline) and move it through cutting → sewing → ready → delivered. Backend is Supabase
(Postgres + Auth + Realtime), with all business rules enforced server-side. UI is Arabic (RTL) by default, English
optional; lengths in cm or inches. Admins review shops and manage accounts and orders from a separate web page,
`admin/index.html` (plain JS, no build step).

The workspace is **not a git repository**, so there is no history to diff against or revert from. Don't reformat files
you aren't otherwise changing.

## Commands

```bash
# run / build (Supabase keys come from env.json via dart-define; without them the app shows "Supabase keys missing")
flutter run --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json

flutter analyze                      # must stay at "No issues found!"
flutter test                         # all Dart tests
flutter test test/models_test.dart   # one file
flutter test test/models_test.dart --plain-name "an offer needs the customer"   # one test by name

# Node checks that need no Flutter (Node 18+), run from tool/tests
cd tool/tests && npm install
node db_test.mjs        # runs supabase/*.sql on PGlite and acts as real users and an admin (108 checks)
node admin_test.mjs     # drives admin/index.html in jsdom with a stand-in Supabase client (64 checks)
node engine_test.js     # drives the 3D page through the same bridge Flutter uses
npm test                # all four chained with && (stops at the first failing script)

# formatting: the code is hand-formatted at ~120 columns. Only format files you touched, never a whole folder:
dart format --page-width 120 lib/path/to/file.dart

# one-off setup after `flutter create --org sd.jalabiya --project-name jalabiya_app --platforms android .`
dart run tool/setup_android.dart     # INTERNET permission, <queries> for call/WhatsApp, app name
python tool/make_icons.py            # all launcher icons from assets/icon/logo.png (needs Pillow)
```

`env.json` (git-ignored) holds `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Adding a package with native code
(e.g. connectivity_plus) needs a full restart, not hot reload.

## Known issues (not caused by recent work)

- `engine_test.js`: "cloth colour applied" and "thread colour applied" fail (14/16). They exercise
  `assets/engine/fitting_room.html` directly, independent of Dart.
- `tool/check_dart.mjs` crashes on Windows paths with spaces (URL-encoded path → ENOENT), so `npm test` never reaches it
  on this machine. `flutter analyze` plus the Arabic/English key-parity test in `test/models_test.dart` cover the same ground.
- `tool/make_icons.ps1` and `assets/icon/icon.html` are the **old** icon generator. Running them would overwrite the
  current logo-based icons. Use `tool/make_icons.py`.

## Architecture

### Start-up and the gate
`main.dart` initialises Supabase, then provides `Repository`, `NetworkMonitor`, `Session` and `OrderAlerts` through
`provider`. `app.dart`'s `AppGate` picks the screen: splash → `WelcomeScreen` (signed out) → `BlockedScreen` if an admin
blocked the account → `ProfileSetupScreen(asGate: true)` until the profile is complete → `CustomerHome` or `TailorHome`
by role. `Session` (`state/session.dart`) holds the user, `Profile`, the tailor's `TailorShop` (followed live over
Realtime, so an admin's decision shows at once), the `AccountBlock` if any, plus locale and unit, which are kept in
SharedPreferences.
"Profile complete" (`Profile.checklist`, plus a shop for tailors) mirrors `profile_is_complete()` in SQL.

### Data layer: the server is the authority
- Every Supabase call lives in `lib/data/repository.dart`. Screens never build queries.
- **Orders are never written directly.** The app calls the RPCs `submit_order`, `update_order` (customer edits before
  confirmation) and `advance_order` (every status change, both sides). They validate, freeze copies of measurements, design
  and delivery address into the order, and log each step in `order_events`, which is the timeline on both order pages.
  RLS lets customers see only their own data, tailors only their orders' customers, and everyone only approved shops.
  Admins (accounts in `app_admins`) read everything except saved sizes, and approve shops in the admin dashboard.
- SQL lives in five files, applied **in this order**, each safe to re-run:
  1. `schema.sql`: base tables, RLS, the RPCs.
  2. `security_fixes.sql`: hardening, see SECURITY_REPORT.md.
  3. `shop_options.sql`: per-shop colours; redefines `valid_design`, `submit_order`, `update_order`.
  4. `price_offers.sql`: adds the `price_offered` status, `orders.estimate`, and redefines `advance_order`.
  5. `admin.sql`: `app_admins`, `tailor_shops.review_status/review_note`, `account_blocks`, `shop_events`,
     `admin_actions`, the `admin_*` RPCs and admin read policies; redefines `protect_shop`.

  Later files `create or replace` functions from earlier ones, so **re-running `schema.sql` reverts them**: always re-run
  the later files afterwards. Put new server logic in a new file that runs after these (and list it in the README's setup
  steps), add it to the load list at the top of `tool/tests/db_test.mjs`, and add checks there. Conventions in these files:
  `security definer set search_path = public`, `revoke execute … from public, anon` for helpers, plpgsql locals prefixed
  `v_` (a local named like a column, e.g. `design`, makes queries ambiguous), errors raised as bare codes
  (`raise exception 'OPTION_UNAVAILABLE'`).

### Rules that exist twice (server + Dart): change both together
| Rule | Server | Dart mirror |
|---|---|---|
| Status transitions | `advance_order` (price_offers.sql) | `nextTailorStep`, `customerCanEdit`, `needsTailor`, `needsCustomer`, `statusPath` in `models/order.dart` |
| When a confirm becomes a price offer (price ≠ saved estimate, or due date later than today + shop lead time) | `advance_order` | `offerNeedsApproval()` in `models/order.dart`, used by the tailor's confirm sheet |
| The estimate = (base + cloth extra + thread extra if embroidered) × qty | `order_estimate()` + `orders_estimate` trigger | `JalabiyaDesign.extrasPrice`, composer `_EstimateBar` |
| Which colours a shop offers (its list, or the standard palette when empty) | `shop_option()` / `default_options()` | `TailorShop.offeredCloths/offeredThreads`, `JalabiyaDesign.cloths/threads` (same ids and colours) |
| Profile completeness | `profile_is_complete()` | `Profile.checklist` |
| Measurement ranges | `valid_measurements()` and table checks | `Measurements.specs` |
| A tailor's save sends the shop back for review (rejected: any save; approved: name/city/neighbourhood/address change) | `protect_shop()` (admin.sql) | `TailorShop.saveSendsForReview()` |

Adding an order status touches: the SQL enum (`alter type … add value`), `_dbNames` in `order.dart`, the helpers above,
`statusColor`/`statusBackground` in `widgets/common.dart`, `progressStep()` in `widgets/order_parts.dart`, and the strings
`status.*`, `event.*`, `detail.now.*` (and `step.*` if it is on the progress path).

### Design, colours and order snapshots
`JalabiyaDesign.cloth`/`.thread` are `Swatch` objects (`id`, `color` 0xRRGGBB, optional `name`, `price`). The app sends
**only ids** (`toJson`). The server's `order_design()` looks them up in the shop's list and stores `cloth_option`/`thread_option`
snapshots in `orders.design`, so later edits to the shop's list never change placed orders. `JalabiyaDesign.fromJson` prefers
the snapshot and falls back to the standard palette for old orders. Standard swatches have no `name` and are translated via
`cloth.<id>` / `thread.<id>`. Use `swatchName()` (in `widgets/common.dart`) rather than reading `name` directly. A tailor's
lists live in `tailor_shops.cloth_options/thread_options` (jsonb, validated by `valid_options`), edited in
`screens/tailor/shop_options_screen.dart`. `ProfileSetupScreen` must carry them through when it saves the shop.

The order flow (`screens/customer/order_composer_screen.dart`) runs person → body → **tailor → design** → review. The tailor
comes before the design so the colour pickers show that shop's options. `_fitDesignToShop()` swaps in valid options when the
shop changes (and flags it for reorders and edits).

### 3D fitting room and the cutting list
`assets/engine/fitting_room.html` is a bundled three.js (r128) page built by `tool/build_engine.py` from the web prototype.
It is shown in a WebView by `widgets/fitting_room.dart`. `FittingRoomController` (`show(m, d)`, `setView`, `focus`, `setUnit`,
`setLabels`, `setPaused`) calls `window.engine.*`. The page reports back through `JalabiyaBridge` (`ready`, `error: webgl`).
The page's state comes from `engineState()` in `models/garment_spec.dart`. The **cutting list is computed in Dart**
(`GarmentSpec.compute`) using constants that must match the engine's drawing. `test/garment_spec_test.dart` pins them to the
prototype's numbers.

### Live data, notifications, connectivity
- `widgets/live.dart`: `LiveData<T>(load, changes, builder, skeleton?, frame?)` is the pattern for every live screen. It
  does the first load (with a skeleton), reloads on each Realtime change, and keeps old data with a typed "stale" bar if a
  refresh fails. When `NetworkMonitor` reports the connection is back, it re-subscribes and reloads.
- `state/order_alerts.dart` (`OrderAlerts`) listens to the signed-in user's orders over Realtime and raises local
  notifications through flutter_local_notifications. Tailors get channel `new_orders` (new or edited orders) and
  `order_updates` (cancelled / rejected offer / accepted offer, worked out by `customerAnswer()` from the latest
  `order_events` row). Customers get `price_offers`. Both get `support` (app support cancelled an order; for tailors,
  an admin's decision on their shop). It also keeps the tailor's `awaiting` badge count.
  **There is no push (FCM)**: alerts only fire while the app is open or backgrounded.
- `state/network.dart` (`NetworkMonitor`): connectivity_plus for interface changes, plus a probe of
  `<SUPABASE_URL>/auth/v1/health` to tell `offline` / `noInternet` (connected but unreachable) / `serverDown` / `online`.
  It re-probes on a backoff while not online and on app resume. Widgets look it up as `Provider.of<NetworkMonitor?>` so they
  work in tests without one. `debugSetStatus()` exists for tests.

### Admin: shop review, blocks, the dashboard
- **Shop review** (`admin.sql`): `review_status` is `pending | approved | rejected | suspended`, with `review_note`
  (the reason the tailor sees). `approved` is still the "customers can see it" flag every policy and RPC uses; the
  `protect_shop` trigger keeps it equal to `review_status = 'approved'` and the owner not blocked. Flipping
  `approved` in the table editor still works and updates the review to match. Each review step is logged in
  `shop_events`. In the app, `TailorShop.review/reviewNote` drive `ShopStatusBanner` (`widgets/common.dart`) on the
  tailor's home and account tab; `OrderAlerts` notifies the tailor of a decision on channel `support`.
- **Blocks**: a row in `account_blocks` with `lifted_at` null makes the `orders_blocked` trigger and `protect_shop`
  raise `ACCOUNT_BLOCKED` for that user's writes, and hides a blocked tailor's shop. An unblock sets `lifted_at`
  and **never deletes the row**: Realtime can't filter or RLS-check delete events (they reach every listener), so
  blocks only ever change by insert/update. `Session` watches its own row (`Repository.watchMyBlock`), re-checks on
  app resume, and `showError` re-checks when the server answers `ACCOUNT_BLOCKED`; `AppGate` then shows
  `BlockedScreen` with the reason, and returns to the home screen when the block is lifted.
- **Admin writes** go only through the `admin_*` RPCs. Each calls `begin_admin()` (checks `is_admin()`, then sets
  the transaction-local `jalabiya.admin_acting` flag so the triggers let it through) and `log_admin()` (a row in
  `admin_actions`). `admin_cancel_order` logs an `order_events` row with `kind = 'admin'`: the timeline shows it as
  app support (`event.admin`, `event.bySupport`) and `cancelledBySupport()` notifies both sides.
- **The dashboard** (`admin/`): `index.html` loads supabase-js 2.117.3 from jsDelivr with an SRI hash (bumping the
  version means recomputing the sha384 of that exact file), optional `config.js` (URL + anon key,
  else a connect form saved in localStorage), `i18n.js` (ar/en, identical keys) and `app.js`. Hash routes
  `#/overview|shops|orders|users|activity[/<id>][?filters]`; an id opens the detail panel. Every value from the
  database is inserted as text (`h()` / `textContent`), never HTML. Lists refresh live over Realtime
  (`tailor_shops`, `orders`). `tool/tests/admin_test.mjs` checks it; when you add a string, add it to both languages.
  Server error codes the dashboard explains are in `SERVER_CODES` + `err.<CODE>` in `i18n.js`.
- **Admin sessions** (the "admin's session" section of `app.js`): signed out after `IDLE_MS` (30 min) without
  input, warned `WARN_MS` before, and `MAX_MS` (12 h) after sign-in. These are enforced in the page, not by the
  server. The sign-in time and last activity live in localStorage (`jalabiya.admin.signedInAt` / `.activity`), so
  tabs share one session: a `storage` event on `signedInAt` signs other tabs out (or in), and activity in one tab
  keeps the others open. A session found at load with no `signedInAt` counts as expired. `signOut(reason)` always
  uses `{ scope: 'local' }`, so the same account stays signed in on the phone app. `is_admin()` is re-checked every
  `ADMIN_CHECK_MS` and when the tab becomes visible, and `lostAdmin()` signs out on any `NOT_AN_ADMIN` from the
  server. Tests drive this with a fixed `Date.now` and `JalabiyaAdmin.tick()`.

### Errors (use these, don't hand-roll messages)
- `data/errors.dart`: `errorKindOf(error, net:)` sorts any exception (Socket/Timeout/ClientException,
  `AuthException` and subclasses, `PostgrestException` codes, HTTP 5xx, the server's raised codes) into an `ErrorKind`.
  `describeError(context, e)` gives an `ErrorInfo` (title, message, icon, `canRetry`). `friendlyError()` is the message only.
- In `widgets/common.dart`:
  - `showError(context, e, onRetry: …)`: the error snack bar.
  - `ErrorView(error: e, onRetry: …)`: the full-screen error. It shows the live connection pill and retries by itself
    when the connection returns, and offers "Sign in again" for session errors.
  - `requireOnline(context)`: put it as the first line inside the `try` of every server action:
    `if (!await requireOnline(context) || !mounted) return;`. It stops the action up front with "Nothing was sent…" while offline.
- A new server error code needs: the code in `_serverCodes` (and in `errorKindOf` if it isn't a plain "invalid"), plus
  `err.<CODE>` strings in both languages.

### Localisation
All UI text is in `lib/l10n/strings.dart`, in two maps (`'ar'`, `'en'`) that **must have identical keys**
(`test/models_test.dart` enforces this). Read it with `context.tr('key', {'name': value})`, which fills `{name}` placeholders.
Outside the widget tree (notifications) use `L10n.lookup(lang, key, args)`. Write layouts for RTL: `EdgeInsetsDirectional`,
`AlignmentDirectional`, `PositionedDirectional`. Arabic numerals in input are accepted via `parseLooseNumber` / `digitsOnly`.

### UI kit and design language
- **Palette and type** (`theme/theme.dart`):
  - Colours: `Palette` (ink navy, damur cream, nile green for actions, gold/goldInk for measurements, henna for problems).
  - Type: `displayStyle()` (Reem Kufi), `monoStyle()` (IBM Plex Mono for numbers), body IBM Plex Sans Arabic.
  - Text fields use `field(...)`.
- **Shared widgets** (`widgets/common.dart`): `Panel` (lifted white card; tinted ones sit flat), `SectionTitle`, `InfoRow`,
  `NoticeBanner`, `BottomActions` + `BusyButton`, `ChoiceRow`, `SwatchRow`/`SwatchStrip`, `StatusChip`, `confirmAction`,
  `askForText`, `showSnack`.
- **Motion and loading** (`widgets/motion.dart`): `InkHeader` (navy header with the diamond lattice), `EntranceFade`
  (staggered entrance), `Pressable` (press scale), `Shimmer` + `SkeletonBox`, `AnimatedCount`, `SuccessCheck` /
  `showSuccess`, `Haptics`. All motion checks `reduceMotion(context)`.
- **Order visuals** (`widgets/order_parts.dart`): `ClothTile` (with hero tag `cloth-<orderId>` from list to order page),
  `MiniProgress`, `OrderProgress`, `OrderTimeline`, `DesignPanel`, `CuttingListPanel`.
- **Size input** (`widgets/measure_field.dart`): `MeasureField` validates typed sizes (not a number / too small / too large,
  inch↔cm mix-up with a one-tap fix, undo). Screens collect `onValidChanged` and block Next/Save while any field is invalid.

### Tests
`test/` holds the Dart tests. Widget tests that render `displayStyle`/`monoStyle` set
`GoogleFonts.config.allowRuntimeFetching = false` in `setUpAll`, and wrap in a `MaterialApp` with the ar/en locales and
`Global*Localizations` delegates (see `test/widget_test.dart`). Database behaviour is tested only in `tool/tests/db_test.mjs`.

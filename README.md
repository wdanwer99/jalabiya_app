# Jalabiya — made-to-measure ordering app (Android, Flutter)

Customers save exact body sizes for themselves and their family, design a
Sudanese jalabiya on a 3D figure built from those sizes, and send it to a
tailor. Tailors see the customer's full profile, the 3D figure, and a cutting
list with ease already added, then confirm with a price and date, ask for a
change, or decline, and move the order through cutting → sewing → ready →
delivered. Both sides see every change live.

Arabic (right-to-left) by default, English in Settings. Centimetres or inches.

## What's in the folder

```
lib/
  main.dart, app.dart          start-up, the sign-in → profile → home gate
  config.dart                  Supabase keys (passed at build time)
  data/repository.dart         every Supabase call
  models/                      sizes, design, cutting list maths, orders
  screens/auth/                welcome, sign in, sign up (customer or tailor)
  screens/profile/             profile + shop setup (required), account tab
  screens/customer/            orders, family sizes, order flow, order page
  screens/tailor/              order inbox, order page with actions
  widgets/fitting_room.dart    the 3D view (WebView) and its Flutter bridge
  l10n/strings.dart            Arabic and English text
assets/engine/fitting_room.html  the three.js figure, bundled, works offline
admin/                         the admin dashboard: a web page, no build step
supabase/schema.sql            tables, security rules, order functions
supabase/admin.sql             admins, shop review, blocking, the dashboard's functions
tool/setup_android.dart        patches the generated Android manifest
tool/build_engine.py           rebuilds the 3D asset from the web prototype
tool/tests/                    database, 3D and Dart checks that run without Flutter
test/                          unit tests for sizes, cutting list, parsing
```

## Setup

### 1. Supabase (about 5 minutes)

1. Create a project at supabase.com.
2. **SQL Editor** → paste all of `supabase/schema.sql` → **Run**, then
   `supabase/security_fixes.sql`, then `supabase/shop_options.sql`, then
   `supabase/price_offers.sql`, then `supabase/admin.sql`, in that order.
   Each is safe to run again later; if you re-run `schema.sql`, run the other
   four again after it.
3. **Authentication → Sign In / Providers → Email**: keep it on. While testing,
   switch off **Confirm email** so new accounts can sign in straight away. Turn
   it back on before launch.
4. **Project Settings → API**: copy the **Project URL** and the **anon public**
   key.

### 2. The app

Needs Flutter 3.24 or newer.

```bash
cd jalabiya_app
flutter create --org sd.jalabiya --project-name jalabiya_app --platforms android .
dart run tool/setup_android.dart
flutter pub get
```

`flutter create .` only adds the missing `android/` folder; it does not touch
`lib/`. The setup script adds the internet permission (release builds fail
without it), the links for the Call and WhatsApp buttons, and the app name.

Create `env.json` next to `pubspec.yaml` (it's in `.gitignore`):

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR-ANON-KEY"
}
```

Run on a phone or emulator:

```bash
flutter run --dart-define-from-file=env.json
```

Build an APK to share:

```bash
flutter build apk --release --dart-define-from-file=env.json
# → build/app/outputs/flutter-apk/app-release.apk
```

### 3. The admin dashboard

`admin/index.html` is the dashboard: a plain web page (Arabic or English) for
reviewing shops, seeing every order and account, and stepping in.

1. Make your account an admin. Sign up once (in the app, or Supabase →
   **Authentication → Add user**), then in the SQL Editor:
   ```sql
   insert into public.app_admins (user_id)
   select id from auth.users where email = 'you@example.com';
   ```
2. Open the page: double-click `admin/index.html`, or serve the folder
   (`npx serve admin`) or put it on any static host. It asks once for the
   project URL and anon key (the same as `env.json`); to skip that, copy
   `admin/config.example.js` to `admin/config.js` and fill it in.
3. Sign in with the admin account.

What it does:

- **Overview**: shops waiting for review, orders stuck for over 3 days,
  customers, tailors, orders per day and new accounts per day.
- **Shops**: approve a new shop, or send it back with a reason the tailor sees
  in the app; suspend a listed shop (hidden, open orders carry on) and
  reinstate it; fix its details. An approved shop goes back for review by
  itself when its tailor changes the name, city, neighbourhood or address.
- **Orders**: every order with its full history; cancel an open one with a
  reason both sides see.
- **Accounts**: everyone with their email and last sign-in; block an account
  (it can't send or move orders, and a tailor's shop is hidden) and unblock it.
  A signed-in app switches to the "account suspended" screen the moment you
  block it, and back when you unblock.
- **Admin log**: every admin action, by whom, with what changed.

The page holds no secrets: everything it reads and changes goes through
`supabase/admin.sql`, which checks that the signed-in account is in
`app_admins`. Anyone else who opens it sees nothing.

Admin sessions: signed out after 30 minutes without activity (with a
one-minute warning), and asked to sign in again every 12 hours. All tabs share
one session: working in one keeps the others open, and signing out in one
signs out all. Sign out ends the session in this browser only; the same
account stays signed in on the phone app. Removing someone from
`app_admins` signs them out of the dashboard within a minute, or as soon as
the server refuses them.

### 4. Try both sides

1. Sign up as **Tailor**, fill in the shop. It shows "under review".
2. Approve it in the admin dashboard (**Shops → Waiting for review**). Setting
   `approved` to `true` in **Table Editor → tailor_shops** still works too.
3. On another phone (or after signing out) sign up as **Customer**, finish the
   profile, add a person, design, pick the tailor, send.
4. Back on the tailor: the order appears under **New** without refreshing.

## How the pieces fit

**Profile gate.** Nobody reaches their home screen until name, phone, city,
neighbourhood and address directions are filled (tailors also need a shop).
The server enforces the same rule in `profile_is_complete()`, so an old app
version can't skip it.

**Orders are written only through three functions** in `schema.sql`:
`submit_order`, `update_order` (customer edits before confirmation) and
`advance_order` (every status change, for both sides). Direct inserts and
updates to `orders` are refused. Each step is logged in `order_events`, which
is the history shown on both order pages.

**Frozen copies.** An order stores its own copy of the measurements, design and
delivery address. Editing or deleting a saved person never changes an order a
tailor already confirmed.

**Each shop's colours.** A tailor lists the cloth and embroidery-thread
colours they have, each with an extra price (Account → Cloth and thread
colours). The customer picks the tailor before designing and sees only that
shop's colours; a shop with none listed offers the standard palette at no
extra. The server checks the choice against the shop and stores the colour's
name and price in the order (`supabase/shop_options.sql`).

**Price offers.** Each order keeps the estimate the customer saw. If the
tailor confirms at a different price, or with a delivery date later than the
shop's usual sewing time, the order waits as "price offered": the customer
gets a notification and accepts (confirmed) or rejects (cancelled). Same
price and usual time confirm straight away (`supabase/price_offers.sql`).

**Who sees what.** Customers see only their own orders and sizes. A tailor
sees a customer's profile only if that customer ordered from them. Customers
see only approved shops. Tailors cannot approve themselves or change their
role. Admins read every shop, order and profile (not saved sizes), and change
things only through the `admin_*` functions, each logged in `admin_actions`.

**Shop review.** A shop is pending, approved, sent back for changes
(rejected) or suspended (`supabase/admin.sql`). Customers see it only when it
is approved and its owner isn't blocked. The tailor sees the reviewer's reason
in the app, and gets a notification when the decision comes in while the app
is open. Saving a rejected shop sends it back for review; so does changing an
approved shop's name, city, neighbourhood or address (the app asks first).

**3D.** The figure is the tested three.js engine from the web prototype,
running in a WebView from a bundled file, so it needs no internet. Flutter
sends sizes and design choices to it; it never computes the cutting list. The
cutting list is computed in Dart (`models/garment_spec.dart`) with the same
constants the engine uses to draw the robe. If a phone has no WebGL the app
shows a note and everything else keeps working.

## Tests

```bash
flutter test
```

Covers the cutting-list maths (matched to the web prototype's numbers),
size parsing including Arabic digits, clamping of bad data, order parsing,
status rules, phone links, and that Arabic and English have the same keys.

Checks that don't need Flutter (Node.js 18+):

```bash
cd tool/tests && npm install && npm test
```

- `db_test.mjs` runs the five SQL files on a real Postgres engine (PGlite) and acts
  as customers, tailors and an admin: 108 checks covering sign-up, the profile gate,
  shop approval, privacy between accounts, every allowed and refused status
  change, frozen order copies, each shop's own colours and prices, price offers,
  shop review and re-review, blocking, support cancellations and the admin log.
- `admin_test.mjs` loads the admin dashboard in jsdom with a stand-in for
  Supabase and uses every section: 64 checks covering sign-in, each action's
  arguments, the session rules (idle, 12 hours, removed admin, other tabs),
  both languages having every word, and shop names never being run as HTML.
- `engine_test.js` drives the 3D page through the same bridge the app uses,
  on the real three.js r128: 16 checks, including that a 132 cm chest sent
  from Flutter measures 132.00 cm on the mesh.
- `check_dart.mjs` parses every Dart file, resolves imports, and makes sure
  every text key exists in Arabic and English with no duplicates.

## Not in this version

- Payments (price is agreed in the app, paid to the tailor directly)
- Push notifications when the app is closed (updates are live while it's open)
- Photos of the finished jalabiya, ratings
- iOS build (the code is cross-platform; run `flutter create --platforms ios .`
  on a Mac to add it)
#   j a l a b i y a _ a p p  
 
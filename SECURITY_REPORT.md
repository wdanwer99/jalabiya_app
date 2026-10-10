# Jalabiya app — security report

**Scope:** Supabase database (`supabase/schema.sql`: tables, RLS, functions, grants), the Flutter app (`lib/`), Android configuration, secrets handling, and the 3D WebView bridge.
**Date:** 2026-10-08
**Method:** code review, plus live attack tests. The real `schema.sql` was loaded into a real Postgres engine (PGlite, the same harness as `tool/tests/db_test.mjs`). Each finding was exploited as an anonymous visitor, a signed-in customer and a tailor, then re-tested with the fixes applied.

## Summary

| Severity | Count | Status |
|---|---|---|
| High | 2 | Fix written and tested (`supabase/security_fixes.sql`) |
| Medium | 5 | 3 fixed in the SQL file, 2 need app or build changes |
| Low / info | 8 | Recommendations |

The core design is sound. RLS is on for every table, orders are only written through validated server functions, tailors cannot approve themselves, roles cannot be changed, and secrets are kept out of the source. The serious problems are in what the database exposes **around** those rules. The worst is that anyone with the app's public key can read any user's home address without signing in.

**Most urgent action:** run `supabase/security_fixes.sql` in the Supabase SQL Editor. With it applied, every database attack in this report is blocked, and the project's own 46 database tests still pass.

---

## High

### H-1 · Anyone, even without signing in, can read any user's name, phone and home address

`delivery_snapshot(uid)` is a `SECURITY DEFINER` function, so it runs as the database owner and skips RLS. It returns a user's name, phone, WhatsApp and full address. Postgres lets everyone execute new functions by default, and Supabase publishes every `public` function at `POST /rest/v1/rpc/<name>`. The schema only revoked access on `submit_order`, `update_order` and `advance_order`.

The anon key is inside every copy of the app and is meant to be public, so any attacker has it.

**Proof (live test):**
```
ANON (no login) calls delivery_snapshot(victim)
→ {"name":"Victim Customer","phone":"0912345678","city":"khartoum",
   "neighbourhood":"Riyadh","address_details":"House 12, street 15, behind the mosque"}
```
Seven internal definer functions were callable anonymously: `delivery_snapshot`, `profile_is_complete`, `my_role`, `is_my_customer`, `is_my_tailor`, `can_see_order`, `handle_new_user`. `profile_is_complete(uid)` also tells an anonymous caller whether an account exists and has an address on file.

**What limits it today:** the attacker needs the victim's user ID (a UUID). UUIDs can't be guessed, but they are not secret either: they show up in order data, logs, support screenshots and the tailor's view of their customers. Access control must not depend on them staying hidden.

**Fix (in `security_fixes.sql`):** revoke `EXECUTE` from `public`/`anon` on all internal helpers. Also revoke it from signed-in users on `delivery_snapshot`, `profile_is_complete` and `handle_new_user`, which are only ever called from inside other functions. Finally, `alter default privileges … revoke execute on functions from public, anon` makes every function you add later start private.
**After the fix:** `permission denied for function delivery_snapshot`.

### H-2 · Every signed-in user can read every tailor's private profile, including unapproved ones

The `profiles_read` policy lets any signed-in user see all columns of any profile with `role = 'tailor'`. Anyone can pick that role at sign-up, so this exposes the phone and **personal home address** (`profiles.address_details`) of every tailor account, including people who registered minutes ago and were never approved.

**Proof:** a customer listed 3 tailor profiles, including the unapproved one's `"Private home: house 7, Abu Roof"`.

**Fix:** only approved tailors are listed (`is_listed_tailor()`), plus the tailor of one of your own orders, so a customer keeps their tailor's contact.
**After the fix:** the unapproved tailor is no longer visible.

---

## Medium

### M-1 · A tailor keeps live access to a customer's profile forever, even after declining
`is_my_customer()` was true if the two had **ever** shared an order. A tailor who declined one order could keep reading the customer's live profile indefinitely, including a new address after the customer moved.
**Proof:** a declined order, then the customer moves, and the tailor reads `"NEW HOME after moving"`.
**Fix:** live access lasts while an order is open, and for 30 days after delivery. The tailor screen already falls back to the address frozen inside each order (`tailor_order_screen.dart`), so nothing breaks.

### M-2 · No size limits on any free text
Names, addresses, shop bios, order notes and tailor notes had no maximum length. A 1 MB note, name and bio were all accepted, which allows storage and bandwidth abuse and breaks layouts on the other side's phone.
**Fix:** check constraints well above what the app's forms allow: name 100, address 500, bio 500, notes 1000. Currency must be a 3-letter code, and prices are capped. They are added `NOT VALID`, so existing rows are untouched and every new write is checked.

### M-3 · No rate limits: one account can flood a tailor
One customer submitted **300 orders × 20 pieces in under a second** to a single tailor, and created 300 saved people.
**Fix:** at most 10 orders per hour, 5 open orders per tailor, and 30 saved people per account, enforced by triggers.
**After the fix:** 5/300 orders and 30/300 people accepted.
**App follow-up:** add `TOO_MANY_ORDERS` and `TOO_MANY_PEOPLE` to `_serverCodes` in `lib/data/errors.dart`, with messages in `strings.dart`. Until then users see the generic error.

### M-4 · The login session can be copied out through Android backup *(app change)*
`AndroidManifest.xml` doesn't set `android:allowBackup`, so Android's default (on) applies. `supabase_flutter` stores the session, including the long-lived refresh token, in `SharedPreferences`, which Auto Backup copies to the user's Google Drive and which `adb backup` can extract.
**Fix:** add `android:allowBackup="false"` (and `android:fullBackupContent="false"`) to `<application>`. For stronger protection, give `Supabase.initialize` an `authOptions` local storage backed by `flutter_secure_storage` (Android Keystore).

### M-5 · Release builds are signed with the debug key *(build change)*
`android/app/build.gradle.kts` signs `release` with `signingConfigs.getByName("debug")`, and the `applicationId` is still `com.example.jalabiya_app`. Google Play rejects both, and a debug key is not a key you can keep safe. If it's lost or leaked, you can't publish trusted updates.
**Fix:** create an upload keystore, load it from `android/key.properties` (already gitignored, along with `*.jks`), and set a real `applicationId` such as `sd.jalabiya.app`.

---

## Low / informational

| ID | Finding | Suggestion |
|---|---|---|
| L-1 | `measurement_sets.relation` accepted any text (e.g. `<script>`). Flutter renders it safely, but it's unvalidated input. | **Fixed:** limited to `self/son/father/brother/other`. |
| L-2 | 9 helper and trigger functions have no fixed `search_path` (Supabase's linter flags this). | **Fixed:** `alter function … set search_path = public`. |
| L-3 | Approved tailors' `profiles.address_details` (a personal address, separate from the shop address) is still readable by all signed-in users. | Expose tailors through a view with only `full_name, phone, whatsapp`, or move contact details into `tailor_shops`. |
| L-4 | Server-side auth settings aren't enforced by code. The app requires 8-character passwords, but the API accepts Supabase's default of 6. | In the Supabase dashboard → Auth: minimum length 8, **leaked-password protection** on, email confirmation on, **CAPTCHA** on sign-up and password reset. |
| L-5 | Anyone can register as a tailor (`role` comes from sign-up metadata). This is by design: the approval gate held in testing (self-approval blocked), and after H-2 unapproved tailors aren't visible. | Keep approvals manual, and review shop details before approving. |
| L-6 | The 3D WebView runs JavaScript with a JS bridge and no navigation guard. It only loads a bundled local file, and all data passed in is JSON-encoded and HTML-escaped, so there's no injection path today. | As defence in depth, add a `NavigationDelegate` that blocks anything that isn't the local asset. |
| L-7 | Unrecognised auth errors show the server's raw message (`errors.dart`, `return error.message`). | Fall back to `err.generic`. |
| L-8 | Dart code isn't obfuscated, and 27 dependencies are behind their latest versions. I didn't check them against vulnerability databases (Dart has no built-in audit tool). | Build releases with `--obfuscate --split-debug-info=build/symbols`, and run `flutter pub outdated` and upgrade regularly (especially `supabase_flutter` and `webview_flutter_android`). The anon key can be extracted from any app; RLS is the real protection, which is why H-1 matters. |

---

## What is already done well (verified)

- **RLS on every table.** A stranger sees 0 of other people's orders, events and profiles.
- **No direct writes to orders.** Every change goes through server functions that check who's acting, validate sizes and design, freeze a copy of the address, and log an event. A direct `update orders` was blocked.
- **Order state machine enforced on the server.** A stranger cannot cancel someone else's order, and tailors and customers can only make their allowed transitions.
- **Role and approval protection.** A customer can't promote themselves to tailor, and a tailor can't approve their own shop (tested on insert and update).
- **Secrets handled correctly.** `env.json` is gitignored and holds only the public anon key; no service-role key is anywhere in the project. Keystores and `key.properties` are gitignored too.
- **HTTPS only.** No cleartext traffic is allowed. Phone and WhatsApp links are built from digits only.
- **No PII in logs.** There are no `print`/`debugPrint` calls of user data.

---

## How to apply

1. Supabase dashboard → SQL Editor → paste and run `supabase/security_fixes.sql` (it's safe to run more than once). **This fixes H-1, H-2, M-1, M-2, M-3, L-1 and L-2.**
2. App changes: M-3 error messages, M-4 backup flag, L-6 navigation guard, L-7 error fallback.
3. Before publishing: M-5 signing and application ID, L-8 obfuscation.
4. Dashboard settings: L-4.
5. Optionally, fold `security_fixes.sql` into `schema.sql` so a fresh install is secure from the start.

**Test results with the fixes applied:** the project's DB suite passed 46/46, and the attack probes found 14 vulnerable before and 1 after. The one remaining is L-5, which is by design.

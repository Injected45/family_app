# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter app on Supabase for a Libyan family association (جمعية العائلة): member
directory, monthly subscription receivables, FIFO payment collection, a treasury
ledger, and an append-only audit trail. **Arabic, right-to-left, forced locale.**
The Flutter project lives in `app/`; the database lives in `supabase/`.

`index.html` at the repo root is the original single-file React/localStorage
prototype. It is unmodified and kept **as the behavioural parity oracle** — the
twelve business rules were transcribed from it and are verified against it. When a
rule's intent is unclear, `index.html` is the source of truth.

## The one architectural fact everything follows from

**There is no server.** The app talks to Supabase directly. The anon/publishable
key ships inside the APK and the web bundle — it is public by design, not a secret,
and cannot be made one. Therefore **every business rule, role check, and money
invariant is enforced inside PostgreSQL** (RLS policies, CHECK constraints,
triggers, generated columns, `SECURITY DEFINER` functions). Validation in Dart is
UX convenience and counts for nothing.

This dictates the data-access shape — do not deviate from it:

- **Reads** → direct PostgREST against `v_*` views (or `api_*` functions), gated by
  RLS on the caller's role. Never read a base table.
- **Writes** → only through the eight `SECURITY DEFINER` RPC functions below. The
  `authenticated` role holds no INSERT/UPDATE/DELETE on any table and no table has a
  write policy, because a payment is not one row — registering it inserts a payment,
  N allocations, N receivable updates, and a cash movement, all-or-nothing. A
  function body is one transaction; a PostgREST call is not.

  The eight RPCs (in `supabase/migrations/…_rpc.sql`): `register_payment`,
  `cancel_payment`, `generate_period`, `auto_close_periods`, `save_family`,
  `update_settings`, `set_user_access`, `purge_financial_data`. (`write_audit`
  exists but is called by triggers, never the client.)

  `purge_financial_data` is the odd one out and the only way to hard-delete
  anything: admin-only, refuses without the phrase in `PurgeWire.confirmPhrase`,
  and TRUNCATEs the six financial tables — receivables, receivable_lines,
  payments, payment_allocations, cash_movements **and audit_log** — with
  `RESTART IDENTITY`, leaving families, members, settings and profiles alone.
  TRUNCATE rather than DELETE because it fires no `BEFORE DELETE` trigger, so
  the rule-9 guards never have to be disarmed. It is a deliberate hole in rules
  9 and 12: after it runs, nothing in the database records that it ran. Settings
  → منطقة الخطر is the only caller. Probed by `supabase/tests/70_purge.sql`,
  which runs last because it erases the fixture.

- **Money is text end to end.** Postgres serialises `numeric` as a bare JSON number
  and `dart:convert` decodes that to `double`. Every view casts amounts to text, and
  every RPC amount is sent from Dart as a `String` (not a number). Putting a treasury
  on binary floating point is the bug this prevents.

## Two custom lints enforce the invariants the Dart analyzer can't

Run both from `app/`; they exit non-zero on violation and are part of the build gate.

- **`dart run tool/supabase_lint.dart`** — fails if Dart reads a base table (money
  would come back as `double`) or writes through PostgREST (`.insert/.update/.delete`
  instead of an RPC). The base-table list and the RPC-that-replaces-each-write map
  live at the top of the tool.
- **`dart run tool/rtl_lint.dart`** — fails on physical left/right layout
  (`EdgeInsets.only(left:)`, `Alignment.centerLeft`, `TextAlign.left`, etc. — use the
  `Directional`/`start`/`end` variants) and on Arabic string literals in widget code.

**Arabic strings have exactly two homes.** User-facing text → `app/lib/l10n/app_ar.arb`
(the ARB template; `en` is the translation). Arabic *wire values* the DB stores
(statuses, payment methods, relations) → `app/lib/core/domain/wire_values.dart`, the
only file exempt from the Arabic-literal lint. Never inline an Arabic literal
elsewhere.

## Code layout (app/lib)

Feature-first. Each feature under `features/<name>/` has `data/` (repository),
`domain/` (models), `presentation/` (screens + Riverpod providers).

- `features/auth` — Google + dev email/password sign-in, role/approval state.
- `features/directory` — families, members, receivables, statements, officials.
- `features/finance` — payments, cash/treasury. `finance_repository.dart` is the
  canonical example of the read-via-view / write-via-RPC pattern.
- `features/oversight` — dashboard, alerts, reports, audit, settings, users.
- `core/supabase` — client init, secure session storage (refresh token → keystore),
  error mapping (`SupabaseFailures.guard`).
- `core/router` — `go_router` with a single `redirect` guard re-run on every
  navigation, so a demotion/sign-out is applied immediately. `destinations.dart`
  defines routes + per-route `minimumRole`.

**State/routing:** `flutter_riverpod` (screens branch on `AsyncValue.when`) +
`go_router`. **Roles** form a hierarchy `admin ⊇ financeManager ⊇ treasurer ⊇ viewer`
(`features/auth/domain/app_user.dart`); unknown roles fall back to `viewer`. Hiding a
button is presentation — the same check is always re-enforced server-side.

## Commands (run from `app/` unless noted)

```bash
# Run — scripts carry the public URL + anon key (repo root)
run_emulator.bat                 # Android emulator; --list | --release
cd app && bash run_supabase.sh   # web (chrome); pass a device id as arg 1

# Flutter checks
flutter test                     # widget/unit tests
flutter test test/rtl_test.dart  # a single test file
flutter analyze
dart run tool/rtl_lint.dart
dart run tool/supabase_lint.dart

# Database / SQL verification (from repo root)
bash supabase/tests/local_pg.sh start   # provision a local PostgreSQL
bash supabase/tests/probe.sh            # runs every business rule with a PASS and a FAIL case
python supabase/tests/verify_live.py <db-password>   # PostgREST/GoTrue/JSON layer over HTTPS
```

## Testing model — two layers, both required

- **`supabase/tests/probe.sh`** proves the SQL against a real PostgreSQL. Each of the
  twelve rules runs with a passing case *and a failing case* (the failing case is what
  proves the rule bites). It also races two psql sessions on one balance to prove FIFO
  allocation can't double-spend, and injects a mid-transaction failure to prove
  rollback.
- **`supabase/tests/verify_live.py`** proves the layer the local suite can't reach:
  PostgREST status codes, GoTrue JWTs, actual JSON encoding. A privilege-escalation
  bug once passed every local check and was caught only here.
- **`app/test/supabase_contract_test.dart`** parses real wire JSON captured by
  `supabase/tests/extract_fixtures.sh` into `app/test/fixtures/`. Rename a view column
  and the models stop parsing here, before the app runs.

Local suite proves the SQL; only the live run proves the platform. Don't treat one as
covering the other.

## Database is applied as one transaction

`supabase/migrations/` holds the schema in order; `supabase/APPLY_TO_SUPABASE.sql`
bundles all of it into one self-verifying transaction for a fresh project. The first
admin needs a deliberate manual step (`supabase/bootstrap_first_admin.sql`) because
every profile is created `viewer`/`pending` and the first person has nobody to approve
them. See `docs/SUPABASE_SETUP.md`.

## Security notes (deliberately committed)

- `run_emulator.bat` and `app/run_supabase.sh` contain the Supabase URL + anon key —
  public by design.
- `run_emulator.bat` also contains a dev-login password for an **approved admin** on
  the live project. The repo is public: treat that password as compromised, rotate it,
  and do not rely on removing the line (it's in git history).
- The `service_role` key and DB password are **not** in the repo and must never be —
  `service_role` bypasses RLS entirely.

# League membership reads (milestone 3B1)

Milestone 3B1 is complete based on user-reported development verification on 2026-11-10:

- Read migration applied to `playoff-fantasy-dev`.
- `league_membership_reads_verification = PASS` and updated `foundation_verification = PASS`.
- Development bootstrap executed successfully.
- Commissioner can view the development league and scoring.
- A separate confirmed account sees no leagues and cannot access the commissioner's league through its direct URL.

The verification script retains the parenthesized CASE comparison fix. All repository bootstrap/test account inputs remain placeholders; private UUID substitutions belong only in private execution copies. No database operations were rerun during this documentation finalization.

## Read model

[20261110000000_league_membership_reads.sql](../supabase/migrations/20261110000000_league_membership_reads.sql) leaves the applied foundation migration unchanged. It adds authenticated SELECT policies on three tables:

| Table | Readable columns | Row scope |
| --- | --- | --- |
| `leagues` | `id`, `name`, `season_year`, `manager_count`, `draft_rounds` | Caller has an active (`departed_at IS NULL`) membership linked to `auth.uid()`. |
| `league_memberships` | `id`, `league_id`, `display_name`, `role`, `departed_at` | Caller actively belongs to the league; its roster may include departed and unclaimed memberships. |
| `league_scoring_versions` | League ID, version, ruleset, all 19 integer-hundredths weights | Caller actively belongs to the league. |

No table-level SELECT is granted: explicit column grants also protect future invitation/email columns. `user_id`, other account UUIDs, and membership timestamps are not selectable, filterable, or orderable by clients. `select=*` on these tables is intentionally unsupported; app queries use safe projections. Anonymous users have no access. No client writes or role/claim operations are granted, including to commissioners. The other eleven tables remain closed.

The private `app_private.has_active_league_membership(uuid)` helper accepts a target league, never an actor. It derives identity from `auth.uid()` and returns only whether that caller actively belongs. It is postgres-owned `SECURITY DEFINER`, with `search_path = ''` and qualified object references. Its owner's membership lookup bypasses RLS, avoiding self-recursion. The function is not a privileged data-returning RPC: it returns no rows, UUIDs, names, or roles. PUBLIC/anon execution is revoked; authenticated receives only schema USAGE and helper EXECUTE, no CREATE. Do not add `app_private` to exposed Data API schemas. Migration creation fails on a schema/function collision rather than replacing unrelated objects. See [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [column privileges](https://supabase.com/docs/guides/database/postgres/column-level-security), and [PostgreSQL definer safety](https://www.postgresql.org/docs/17/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY).

## Application

`/account` links to `/leagues`. Both league routes verify the user's confirmed Auth identity with server `getUser`, then query with the same cookie-bound Supabase client. List rows come entirely from RLS, without a privileged key or client-supplied actor. `/leagues/[leagueId]` validates UUID shape and fetches the league before its roster/scoring. Missing/nonmember leagues have generic not-found content and generic metadata. List query failure shows unavailable, not a false empty state. A genuinely empty successful list says no active membership exists.

Pages are dynamic, Supabase fetches use `cache: no-store`, and the refresh proxy plus response headers cover `/leagues/:path*`. The overview shows explicit NFL/playoff years, configured manager count/rounds, the safe manager roster, and all stored scoring versions in exact two-decimal points. It does not select an active draft/scoring version or infer that all configured manager slots are occupied. No draft, invitation, creation, or import UI is included.

## Development setup reference (already performed)

The read migration is already applied. For future separately authorized pending migrations, confirm the link targets **playoff-fantasy-dev** before using these commands:

```sh
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
# Only after separate authorization and development-target review:
supabase db push --linked --skip-vault
```

Do not run the foundation migration manually again. Check that `app_private` is absent from hosted API exposed schemas; the checked-in config exposes only `public`/`graphql_public`. No hosted setting was inspected or changed here.

To bootstrap your actual development league, open [development-league.sql](../supabase/setup/development-league.sql) in the development SQL Editor as `postgres`. Replace `REPLACE_WITH_YOUR_CONFIRMED_AUTH_USER_UUID` **only in your private editor copy**, using your existing confirmed account's UUID from Authentication → Users. Do not commit account IDs/emails or save filled scripts in the repository. The script validates account existence and confirmation without changing Auth records.

Run the entire `BEGIN ... COMMIT` script deliberately: unlike tests, this script **persists** one development league. It serializes reruns, derives a stable league ID for this account/setup, inserts the 2026 season if missing, and creates `DEVELOPMENT — 2026 Playoff Fantasy` with 10 manager slots, 8 rounds, exact scoring version 1, and only your commissioner membership (`Development commissioner`). It creates no draft, teams, players, or nine placeholder managers.

A rerun validates the same league/configuration, scoring, and your active commissioner role. It never promotes/reactivates a membership, repairs conflicting data, or modifies another user's league. A conflicting name/identity/configuration aborts. Existing managers added later are untouched. On any error, run `ROLLBACK;` before other SQL in that session. Success emits `Development league ready`; then sign in and open `/leagues`.

## Rollback-only database verification (user-reported PASS; rerun reference)

1. After the read migration, run the **updated** [foundation-verification.sql](../supabase/tests/foundation-verification.sql) as `postgres`. It retains all original storage assertions and now requires the read migration. It denies all table-level privileges for normal clients, checks the exact column SELECT allowlists on the three read tables, and still denies all table/column reads and writes on the other eleven. It must return `foundation_verification = PASS` and roll back. The 2026-11-03 PASS was for the original foundation-only version, not this update.
2. Provision three distinct confirmed test Auth accounts A/B/C via the supported dashboard/admin workflow in [AUTH_SETUP.md](AUTH_SETUP.md#provision-one-approved-confirmed-test-account). Do not manually insert `auth.users`, reuse real users without consent, or place administrative keys in the app. This task created no accounts.
3. Privately fill the three UUID placeholders in [league-membership-reads.sql](../supabase/tests/league-membership-reads.sql). Run the whole file as `postgres`. It inserts generated application fixtures, then sets local `authenticated` role/JWT contexts for A/B/C; it does not fake authentication in the app or alter Auth rows.
4. Require `league_membership_reads_verification = PASS` and final `ROLLBACK`. **After any unexpected failure, execute `ROLLBACK;` before any other SQL in that session.** Do not accept inspection-only SELECT output or partially run selections as passing evidence.

Assertions cover A-only-A/B-only-B, safe full rosters, hidden `user_id` (including SELECT/filter/order/wildcard attempts), C nonmembership, anonymous denial, departure revocation, write/role/scoring denial, helper ownership/search path/ACL, and nonrecursive policy evaluation. Fixtures are filtered by generated league IDs, so preexisting memberships on the provisioned accounts do not affect expected counts. No persistent test fixtures, schemas, functions, grants, or users are created. PostgreSQL permission tests catch only `insufficient_privilege`; an invalid operation succeeding fails outside that handler, and recursion/other errors abort.

These SQL role-context tests target the database privileges PostgREST/Data API uses. Their reported PASS is database-role evidence, not a standalone direct Data API HTTP test: after migration/bootstrap, use two isolated signed-in browser profiles to verify league list/guessed-ID isolation. For a direct Data API check, a trusted local client using the existing user's access token and the public publishable key must see its own safe projection but fail `league_memberships?select=user_id`, `select=*`, and filters/order on `user_id` (a 4xx response, not leaked data). Also verify anonymous and nonmember requests. Never print/paste access tokens, cookie/session objects, authorization headers, or copy credential-bearing curl commands into documentation. The commissioner and separate-account browser checks passed as reported above; no separate direct Data API HTTP probe is claimed.

## Verification limits and next slice

The reported database PASS results and commissioner/nonmember browser checks complete 3B1. They do not establish unreported HTTP probes, account-deletion behavior, physical cross-device use, or refresh after access-token expiry. Mocked/pure TypeScript tests validate ID handling, safe projections, and presentation; they do not validate RLS or recursion. On SQL test failure always execute `ROLLBACK;` before other SQL in that session.

Invitations, membership claiming, and commissioner invitation controls remain unimplemented in milestone 3B2. No application mutation privileges or elevated app keys are introduced by this completion status.

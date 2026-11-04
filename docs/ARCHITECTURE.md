# Architecture

Status: system design proposal; milestone 2A pure logic and tests are implemented, with results in [PLAN.md](PLAN.md). Foundation migration 20261028000000 is applied to development (user-reported). Its rollback-only storage verification returned PASS on 2026-11-03; milestone acceptance remains pending review, and RPC/integration behavior is unverified. Product rules in [SPEC.md](SPEC.md) are confirmed; table shapes, state names, and mechanisms below are recommendations pending implementation review.

## Confirmed direction

- Next.js App Router, TypeScript, Tailwind, npm; Supabase PostgreSQL, Auth, and Realtime. GitHub for source and Vercel for eventual hosting.
- Supabase CLI 2.122.0 is installed and the repository is linked to `playoff-fantasy-dev` (user-reported development target). Initialized local config targets PostgreSQL 17; Docker is not installed. Hosted schema and credentials were not inspected. The purchased Spaceship domain is hardikbhardwaj.com; eventual app host is playoffs.hardikbhardwaj.com. Personal homepage is a separate future project.
- SQL migrations version schema changes. Keep required secrets server-side and out of Git. Prevent local/preview writes to production. Plan protected, recoverable data exports.
- Minimal infrastructure; no microservices, Redis, or queues without demonstrated need.

## Proposed application boundaries

Use one Next.js application and one PostgreSQL database. Server entry points authenticate and validate requests; database policies and authorized transaction functions enforce access and invariants. Keep pure snake-order and scoring functions independent of UI, network, and ingestion adapters.

Realtime carries change notifications, not authoritative picks or scores. After notifications, fetch state; after reconnect, fetch a full snapshot. Reject older versions and periodically refresh while the draft room is open. Keep a request ID through retries and show pending/uncertain outcomes until reconciled.

## Applied foundation migration

[20261028000000_league_draft_foundation.sql](../supabase/migrations/20261028000000_league_draft_foundation.sql) creates 14 public tables in one transaction, without data, policies, RPCs, triggers, or extensions. The user reports this migration applied on `playoff-fantasy-dev`; the storage assertions below have passed there. Future schema choices remain proposals until accepted. No sample managers, emails, or NFL records are inserted.

| Tables | Stored foundation / constraints |
| --- | --- |
| `nfl_seasons` | Explicit NFL season year and following playoff-end year; no historical import workflow. |
| `nfl_teams`, `nfl_players` | Stable UUID identities; names are not identity keys. |
| `nfl_season_teams` | Season-specific team name/abbreviation and playoff eligibility; unique season/team. |
| `nfl_season_players` | One team/position per player/season; QB/RB/WR/TE/K only. Composite FK requires a playoff-eligible season/team. Individual kicker identity must be reviewed before pool finalization. |
| `leagues` | Season, independent positive manager count and rounds, safe-integer total-pick limit. No coupling to 10×8 or 12×7. |
| `league_memberships` | Durable UUID, league, display name, member/commissioner role, optional account link and departure time. One nonnull account per league; multiple unclaimed memberships allowed. |
| `league_scoring_versions` | Keyed by league/version; ruleset label and all 19 weights in integer hundredths. Defaults and CHECKs fix each weight to SPEC and the pure scorer. No arbitrary custom scoring or bonus fields. |
| `drafts` | One draft per league (proposal), same league season/scoring version via composite FKs; copied manager count/rounds, status, next pick, safe-integer version, order/pool finalization, freeze/start/completion/cutoff timestamps. Completion requires the end sentinel. |
| `draft_order` | Unique position per draft and membership per league/draft; membership FK includes league. Positions are original saved-order slots, not chronological positions within reversed rounds. |
| `draft_player_pool` | Unique draft/player; league/draft/season FK and season/player/team/position/eligible FK. Copies season-specific eligible team/position into the pool. |
| `draft_requests` | Unique `(draft_id, actor_user_id, request_key)`; operation plus complete JSON-object payload/result and before/after versions. Stores successful committed outcomes only, including after undo. |
| `draft_picks` | Owner FK must reference that draft's saved order; player must reference that draft's pool. Request and reversal references must belong to the same league/draft. One pick per original request, including reversed history. |
| `draft_audit_events` | Same-league/draft optional request/pick links; actor UUID/membership, event type, draft version, JSON details and timestamp. Storage for rerandomizations and draft changes; logging operations are deferred. |

Partial unique indexes on active picks (`reversed_at IS NULL`) enforce player per draft and overall pick per draft. Reversal requires a timestamp and distinct reversal-request reference; reversing a pick frees both uniqueness slots without deleting history. New intent uses a new request key.

All history-bearing foreign keys use `ON DELETE RESTRICT ON UPDATE RESTRICT`, except `league_memberships.user_id → auth.users.id ON DELETE SET NULL`. Account deletion therefore detaches the account while durable memberships, order, picks, requests, and audit remain. Departure marks `departed_at`, not deletion. Future scores must reference durable memberships/picks, never cascade from accounts. No Supabase-managed table is altered.

Request/audit actor UUIDs are deliberately immutable identity snapshots without live `auth.users` FKs. This retains the original retry namespace after account deletion. Future RPCs must capture the actor from verified authentication, bind it to the recorded membership, and compare operation plus full normalized payload for conflicting key reuse. Stored result objects must contain the original successful response, not be reconstructed from a now-reversed pick. Object-shape CHECKs do not validate response semantics or enforce append-only history; future RPCs/grants must do that.

The restrictive pool FK prevents changing a referenced season's eligibility/team/position in place; it favors historical integrity over easy corrections. Future correction/versioning needs review. Pool rows and scoring versions still need freeze/immutability enforcement; copied columns and timestamps alone do not freeze data. `created_at` defaults exist throughout; mutable league/membership/draft records also have `updated_at` with ordering checks. Future mutation functions must maintain `updated_at` explicitly for every affected row that has that column; insert defaults and ordering checks do not refresh it on update (no timestamp trigger is included).

Playoff eligibility records qualification for the season and inclusion in the draft pool; it is distinct from subsequent elimination. Elimination must never change `nfl_season_teams.playoff_eligible`, `nfl_season_players.team_playoff_eligible`/`eligible`, or the eligibility keys referenced by frozen player pools. Later game/team-status storage must track elimination separately. Eliminated players retain their picks and earned points; only the players-remaining count changes.

## Access defaults and deferred transaction invariants

Every new table explicitly enables RLS and revokes all table privileges from `PUBLIC`, `anon`, and `authenticated`. No permissive policies, client grants, RPCs, or realtime-publication changes are added. Ordinary clients cannot read even their own league yet; narrowly scoped member reads and authorized RPCs come later. Owners and privileged service roles can bypass RLS; this is not an implemented application authorization system. The migration changes no schema-wide defaults or unrelated tables. See [Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security).

Future authorized, locked transactions must enforce:

- Start: active membership count equals manager count; contiguous complete saved order; finalized pool/kickers; copied league settings agree; frozen scoring, membership, rounds, pool and order cannot subsequently change. Server randomization must save/log pre-start rerandomizations.
- Pick: authenticated actor/membership and commissioner-on-behalf checks; running state; expected version/pick; correct snake turn, round, in-round position and draft bounds; season-wide cutoff; atomic request/pick/audit/state advancement and final completion.
- Retry: same actor/key/operation/payload returns its original result; different payload fails. Insert the successful request, pick, audit and version change in the same transaction, never in separate HTTP writes.
- Pause/resume/undo: same draft lock; paused/latest-pick/pregame checks; final-pick undo support; restore turn/availability; immutable successful request results; append-only audit. Reversal FK does not itself prove the referenced operation is an authorized undo.
- Cutoff: trusted kickoff/started-game evidence, blocked unfinished draft and explicit administrative resolution. No wall-clock CHECK is used as a substitute for transaction-time checks.

Row-local checks and composite FKs enforce storage relationships; they cannot establish the cross-row temporal rules above. Foreign keys and unique constraints are designed using [PostgreSQL constraint semantics](https://www.postgresql.org/docs/17/ddl-constraints.html), and are covered by the limited storage verification below; future transaction invariants remain unimplemented.

## Deferred relationships and decisions

Later migrations will connect games to season/team identities; player/game normalized stats to season-player identity; scored contributions to game, player and frozen league scoring version; and derived rosters/totals to active picks and durable memberships. Import jobs/provenance/corrections will reference games and source snapshots. Provider ID mappings/search aliases, invitations/verified-email claims, and application-admin grants are also deferred; membership rows alone do not grant invitation-based entry.

Projections will reference player/game/scoring configuration independently of actuals. Finalized-result snapshots and import leases remain proposals; no tables for either are included. Unusual recovery TDs, blocked kicks, ranking sources, cutoff authority/resolution, correction policy, email normalization, and audit/actor retention remain unresolved decisions. Recommend retaining actor UUID snapshots for history, with a reviewed retention policy before launch. One draft per league and one team/position per player/season are simplifying proposals; revisit explicitly if approved requirements change.

## Review and development application commands

The user reports migration 20261028000000 applied to **playoff-fantasy-dev**, and a dashboard query confirmed RLS on all 14 tables with no `anon`/`authenticated` SELECT. On 2026-11-03, after the user authorized direct query execution, `supabase db query --linked --file supabase/tests/foundation-verification.sql` returned `foundation_verification: PASS` and exit status 0. No migration/schema changes or auth-user fixture changes were made. Verification acceptance remains pending user review; milestone 2B is not marked complete.

The initialized config is unchanged local-development config, not evidence of hosted Auth security. Its generated signup/seed defaults need review in later setup work; no seed file/data is added here. `.temp/`, `.branches/`, `.env*`, and locally generated `signing_keys.json` are ignored; `config.toml`, `.gitignore`, and migrations remain versionable. Previously documented migration commands remain available for separately authorized future migrations; do not reapply the foundation SQL manually:

```sh
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
# Apply pending migrations only when separately authorized, after verifying DEVELOPMENT:
supabase db push --linked --skip-vault
```

CLI 2.122.0 help confirms these flags. `--skip-vault` avoids config-driven Vault updates; no seed/role flags, plaintext credential arguments, or debug output are needed. [Supabase CLI reference](https://supabase.com/docs/reference/cli/supabase-db-push).

## Running the foundation verification

Open [foundation-verification.sql](../supabase/tests/foundation-verification.sql) in the **playoff-fantasy-dev** Supabase SQL Editor, select the privileged `postgres` role, and run the **entire file**. It uses `BEGIN`, an anonymous assertion block, a PASS result, and a final `ROLLBACK`. No tables/functions are created. Fixtures use generated UUIDs, NULL membership account links, and an unused synthetic season; no real user data or `auth.users` records are read or changed.

Success requires no errors, `foundation_verification = PASS`, and completion of the final `ROLLBACK`; a notice before rollback also reports assertions passed when the editor displays notices. Running only a selection or seeing only the notice is insufficient. **If any test fails, execute `ROLLBACK;` before running other SQL in the same session**, even if the editor may already have rolled back. Expected constraint errors are handled internally; unexpected error types, wrong constraints, and invalid writes that succeed fail explicitly.

Coverage: all 14 tables exist and enable RLS; `PUBLIC` has no table ACL privileges and `anon`/`authenticated` have no effective table privileges (including inherited rights). Same-league records and independent cross-league player selection succeed. Cross-league order/member references, non-order owners, cross-draft pool/request references, duplicate active players/pick slots, duplicate request identity, invalid positions, and each of the 19 incorrect scoring weights fail at the expected constraints. Soft reversal permits player/slot reuse with a new request, and the original successful request remains unchanged when compared as a complete JSONB row snapshot.

The account-link FK is catalog-checked for nullable `ON DELETE SET NULL / ON UPDATE RESTRICT`, without touching accounts. Account-deletion behavior remains deferred until authentication fixtures are authorized. This validates **storage constraints**, not RPC authorization, turn enforcement, concurrency, or retry implementation. Direct privileged fixture inserts do not model authenticated gameplay or prove freeze/immutability. Further development-database verification and user review are required before completing milestone 2B. Exception patterns follow [PostgreSQL PL/pgSQL error handling](https://www.postgresql.org/docs/17/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING).

## Proposed authorization

- Scope all league data through memberships and database row-level security; verify access in server handlers too. A user belonging to league A cannot read/write league B by guessing identifiers.
- Invitation claim is a server transaction bound to the verified authenticated email and assigned unclaimed membership. Do not trust a submitted email or membership ID. Decide normalization/token-expiry details with the email implementation; do not invent provider-specific address aliases.
- Members may read their league and observe the draft at any time. Only submitting a draft pick is restricted to the current manager, except a commissioner explicitly acting on that manager's behalf. Commissioners manage approved league operations. Application administrators alone correct shared stats manually.
- Permit authenticated shared NFL/stat reads as needed; do not grant client writes to canonical stats, picks, frozen settings, role grants, or audit records.
- Prefer an authorized PostgreSQL RPC for mutations. If elevated function rights are required, restrict execution grants, fix the search path, fully qualify objects, and check the authenticated actor inside the function. Server-only service credentials must never bypass actor checks implicitly.
- Avoid exposing invitation addresses or source snapshots in general league reads. Keep snapshots, audit data, and exports protected; use separate nonproduction credentials/data for local and preview environments. Define backup/export access, retention, and a restore drill before deployment.

## Proposed atomic draft protocol

Use one PostgreSQL function/RPC per operation, not a sequence of independent HTTP writes.

1. Receive actor context, draft ID, unique request ID, expected version/overall pick, and player (plus explicit on-behalf intent where applicable).
2. Lock the draft row. Verify actor access; look up request identity scoped to draft/actor. For an identical successful retry, return its recorded result even if the draft has since advanced. Reject reuse with a different payload. Enforce request-identity uniqueness in the database.
3. Check running status, frozen membership, current turn, expected version/pick, server-side first-game cutoff, player eligibility, and active availability. A commissioner override changes who acts, never whose turn it is.
4. Insert the active pick and audit/request result; advance turn and version. On the final pick, mark complete. Commit all changes together or roll back all of them.
5. Notify clients after commit; clients fetch authoritative state.

Start, pause, resume, undo, and rerandomization acquire the same draft lock, enforce actor permissions, and increment version. Start validates and freezes complete configuration and order. Log/display pre-start order changes. Resume cannot bypass cutoff. Undo requires paused state and no playoff game started; reverse only the latest active pick, restore its slot/turn and player availability, and retain audit history. To undo a final pick, allow the commissioner to pause a completed draft before the cutoff, then undo to a paused unfinished state. This state-transition mechanism is proposed; the ability to undo under the confirmed rules is required.

Use trusted season-wide first-playoff-game timing and authoritative started-game information; do not rely on browser time. At or beyond cutoff, all pick transactions fail even if status still says running. Expose a blocked state requiring explicit administrative resolution; do not provide an unspecified cutoff bypass. Review how kickoff corrections and delayed games affect the trusted cutoff before launch.

Concurrency acceptance: simultaneous pick/pause/undo operations serialize; only one competing pick succeeds; retries cannot duplicate work; reversed slots/players are reusable; unauthorized actors and stale versions cannot mutate state.

## Proposed import and scoring publication

1. Authorize the commissioner trigger under the pending cross-league policy. Create a durable import run and mark fixtures clearly synthetic. A provider adapter supplies raw data; a separate normalizer maps it to internal game/player IDs and scoring categories.
2. Proposal, deferred to milestone 7: use a per-game database claim with a monotonically increasing run generation: claim before fetching, permit one active importer, and use an expiring recovery lease. Fetch outside a long database transaction. A reclaimed/older worker must fail generation validation at publish time. This adds recovery bookkeeping but avoids holding locks during network I/O and prevents stale responses from winning.
3. Validate game identity and completion, mappings, category completeness, duplicates, units, and classifications. Missing values remain unknown, not zero. Block publication on unresolved required mappings/categories; retain diagnostic run records and existing published scores.
4. In one publication transaction, lock the game, verify the run generation, upsert/replace its normalized player stats, remove obsolete records from that game's prior snapshot as appropriate, compute exact points under every affected frozen scoring version, and update score revisions and provenance. Roll back the whole publication on failure; record failure separately.
5. Reimporting identical data changes no totals. Corrections replace the previous contribution rather than accumulating it. Standings sum eligible game contributions for active picks and show included games, freshness, and unknown/awaiting states.

Shared admin corrections use the same serialization/publication rules with before/after audit data. Finalized-league behavior remains an open decision in SPEC. Provider capability research, actual integration, and live data are later work; no API availability or website scraping is assumed.

## Decisions still required

See the decision table in [SPEC.md](SPEC.md) for product tradeoffs/defaults. Additional implementation review points: schema/function grants and RLS policies (milestones 2B–3), authoritative cutoff source and transaction transitions (4–5), import serialization design (including the proposed recovery lease) and retention/export policy (7–8). Import leases, finalized-result snapshots, ranking sources, and unresolved provider classifications are proposals or deferred decisions, not prerequisites for pure-logic milestone 2A. These proposals do not establish new product rules or imply configured infrastructure.

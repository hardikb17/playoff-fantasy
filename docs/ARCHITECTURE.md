# Architecture

Status: design proposal, not implemented. Product rules in [SPEC.md](SPEC.md) are confirmed; table shapes, state names, and mechanisms below are recommendations pending implementation review.

## Confirmed direction

- Next.js App Router, TypeScript, Tailwind, npm; Supabase PostgreSQL, Auth, and Realtime. GitHub for source and Vercel for eventual hosting.
- No external service accounts/connections are configured for this repo. The purchased Spaceship domain is hardikbhardwaj.com; eventual app host is playoffs.hardikbhardwaj.com. Personal homepage is a separate future project.
- SQL migrations version schema changes. Keep required secrets server-side and out of Git. Prevent local/preview writes to production. Plan protected, recoverable data exports.
- Minimal infrastructure; no microservices, Redis, or queues without demonstrated need.

## Proposed application boundaries

Use one Next.js application and one PostgreSQL database. Server entry points authenticate and validate requests; database policies and authorized transaction functions enforce access and invariants. Keep pure snake-order and scoring functions independent of UI, network, and ingestion adapters.

Realtime carries change notifications, not authoritative picks or scores. After notifications, fetch state; after reconnect, fetch a full snapshot. Reject older versions and periodically refresh while the draft room is open. Keep a request ID through retries and show pending/uncertain outcomes until reconciled.

## Proposed data model

Names are illustrative; milestone 2B will refine keys and migrations and validate them against an actual development database. Milestone 2A covers only pure logic and tests.

| Scope | Records and invariants |
| --- | --- |
| Shared NFL data | `seasons`, `teams`, `players`, `player_seasons` (season/team/position), `provider_player_ids`, search aliases, `games`, team playoff status. Stable internal player IDs; provider mapping must be unambiguous within its provider namespace. |
| Shared actuals | `player_game_stats` keyed by player/game; normalized separate scoring categories, explicit completeness, provenance/revision. `import_runs` and source snapshots retain requester, timestamps, provider, status, mappings, changes. Audited manual corrections use the same publication path. |
| League access | `leagues` with explicit NFL season and independent manager/round settings; durable `memberships`, email invitations, account links, league roles; separate application-admin grants. Detach deleted accounts from durable memberships rather than cascading picks/scores. |
| Draft configuration | `drafts` with status, next pick, version, cutoff and frozen configuration; ordered membership slots, eligible player snapshot with season/team/position, immutable scoring version. Unique order position per draft and one order slot per membership. |
| Draft history | `picks` with draft, overall slot, round, owner membership, player, acting account, on-behalf marker, reversal metadata; append-only operation/audit records and request results. Active picks uniquely constrain draft/player and draft/overall slot. |
| Derived results | Player/game/scoring-version points and league score publication revisions; rosters derived from active picks. Optional result snapshots support finalization/reopening if that open policy is accepted. |

Prefer soft reversal (`reversed_at`) plus partial unique indexes on active picks over deleting history. A full event-replay model offers richer reconstruction but adds complexity; soft reversal with immutable operation logs is the recommended starting choice. Preserve request results even when their pick is later reversed: retrying that request returns its original outcome, never creates a new pick. New intent requires a new request ID.

Store scoring categories separately: pass/rush/receive yards and TDs, receptions, individual return TDs, each conversion category, interceptions thrown, fumbles lost, field goals by made-distance band, extra points made, and each missed-kick type. Keep raw source data for review. Validate normalized categories as disjoint where necessary; conversion plays must not also contribute ordinary play stats. Recommend integer hundredths of a point (yard weights 4/10/10; reception 100, etc.); validate provider units before conversion and never use binary floating-point for totals.

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

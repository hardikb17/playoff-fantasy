# Delivery plan

Build one milestone at a time. [SPEC.md](SPEC.md) contains confirmed rules and open decisions; [ARCHITECTURE.md](ARCHITECTURE.md) proposes implementation. A proposal is not an approved product change.

## Current status

Milestone 1 is complete for this documentation task: the documents capture the supplied rules, distinguish proposals/open choices, preserve the generated Next.js instructions, and bound the next task. Milestone 2A is also complete: pure draft-order and scoring modules plus automated tests are implemented. Milestone 2A performed no database, authentication, UI, realtime, external API, or deployment work. The user reports the foundation migration applied to development. The rollback-only storage script returned PASS on 2026-11-03; acceptance remains pending review and milestone 2B is not complete.

Verified on 2026-10-27: existing App Router starter under `src/app/`; Next.js 16.4.3, TypeScript, Tailwind, npm, ESLint; `npm run lint` and `npx tsc --noEmit` pass. Starter loading was reported in the brief, not independently browser-verified here. No production build, deployment, or multiplayer behavior is claimed.

Existing scripts: `npm run dev`, `npm run build`, `npm run start`, `npm run lint`, `npm test`. Tests use Node’s built-in runner with `tsx` (the only added development dependency) to execute TypeScript directly. `npx tsc --noEmit` uses the installed TypeScript compiler. Read relevant installed framework docs in `node_modules/next/dist/docs/` before writing code.

## Milestones and exit checks

| # | Scope | Meaningful verification | Status |
| --- | --- | --- | --- |
| 1 | Repository documentation and starter verification | Requirements/proposals/questions separated; framework guidance preserved; lint/typecheck pass; next task explicit. Runtime evidence qualified above. | Complete |
| 2A | Pure snake-draft order and exact-scoring logic with meaningful tests | Test both 10×8 and 12×7 plus independent settings, round reversals, exact scoring and negative yardage. No database integration, authentication, UI, external services, imports, or deployment. | Complete |
| 2B | Database schema, migrations, constraints, and access-policy design | Review keys, frozen configuration, active-pick/request uniqueness, durable ownership and RLS boundaries; then apply migrations and validate constraints and designed policies against an actual development database. SQL review alone does not complete this milestone. | In progress: applied; storage script PASS; acceptance pending |
| 3 | Supabase, policies, invitations, email links | Decide delivery and identity-claim details. Test invited-email claim, wrong-email denial, role restrictions, cross-league reads/writes and direct database policy enforcement; account removal preserves history. | Not started |
| 4 | Eligible pool and configuration | Validate season/team/position and individual kickers; verify no duplicate identities, finalized pool/order, logged rerandomizations, independent league settings, and configuration freeze. Review rank source and cutoff authority. | Not started |
| 5 | Authorized atomic draft operations | Real database concurrency tests: competing picks, stale versions, successful-request retry, payload conflict, commissioner on-behalf permission, pause/resume races, undo/reuse, final-pick undo, cutoff blocking, and durable recovery. Agree cutoff resolution policy before launch. | Not started |
| 6 | Draft UI and synchronization | Multi-user/mobile checks, refresh/restart/reconnect snapshots, stale notification rejection, periodic refresh fallback, pending/uncertain requests, informational presence. No simulated security/persistence/multiplayer presented as complete. | Not started |
| 7 | Synthetic scoring, imports, rosters, standings | Labeled fixture imports; exact category scoring, safe identical/corrected reimports, failed/incomplete/stale imports preserving scores, shared effects across frozen league scoring, audited admin corrections. Check bye/elimination, tie ranks, freshness/data states, provisional → reconciled → finalized and logged reopening. Resolve mapping/import/finalization policy questions first. | Not started |
| 8 | Deployment and multi-user acceptance | Configure services only in authorized follow-up work. Verify preview/local isolation, secrets, domain/hosting, policy and end-to-end multi-user behavior, protected export and successful restore. | Not started |
| 9 | Actual stats provider research/integration | Compare availability, licensing/access, IDs, category completeness, corrections and provenance. Select explicitly; verify real completed-game imports and safe reimports against fixtures. No assumed API or scraping. | Deferred |
| 10 | Current-matchup projections | Research/select model/source; verify bye/eliminated/pending states, saved model/scoring provenance, and separation from actual scores and overall draft ranks. | Deferred; outside MVP |

Milestone 8 demonstrates a fixture-backed application; real-data readiness additionally requires milestone 9. Live stats remain a long-term goal with no implementation milestone yet.

## Milestone 2A verification

On 2026-10-27, `npm test` passes all 37 tests; `npm run lint` and `npx tsc --noEmit` pass. Tests cover 10×8, 12×7, and 10×7 drafts; odd/even rounds and consecutive boundary turns; first/last picks and one manager; invalid inputs and input immutability. Scoring tests cover each category, a synthetic hand-calculated 68.98-point line, exact passing yards, negative yardage/totals, separate turnovers, complete-zero versus missing stats, no bonuses, safe integer arithmetic, and two-decimal formatting.

Public interfaces:

- `getSnakeDraftTurn(managerIds, rounds, overallPick): DraftTurn` and `generateSnakeDraftOrder(managerIds, rounds): DraftTurn[]` in `src/lib/draft-order.ts`. IDs are already ordered and unique; numbering is one-based. `positionInRound` is chronological within the round. Neither function randomizes or mutates inputs.
- `scoreFantasyStats(stats: Readonly<NormalizedStats>): FantasyScore` in `src/lib/scoring.ts` requires all 19 categories and returns category breakdown plus total in integer hundredths. Negative integer yardage is valid; counts must be nonnegative safe integers. Unsafe products or intermediate totals are rejected.
- `formatFantasyPoints(hundredths): string` renders exactly two decimals, including negatives, without floating-point rounding.

Field-goal band assignment (under 40, 40–49, 50+) belongs to normalization; no raw-distance classifier is implemented. Normalizers must keep TD categories disjoint, exclude conversion plays from ordinary stats, and deduplicate source plays. Tests consume normalized synthetic data; they do not detect duplicate provider plays or establish database concurrency, persistence, or authorization correctness. Blocked-kick and unusual recovery-TD classifications remain unresolved.

## Milestone 2B foundation slice

Prepared on 2026-10-28: [20261028000000_league_draft_foundation.sql](../supabase/migrations/20261028000000_league_draft_foundation.sql), with 14 tables for NFL identities/season eligibility, leagues/memberships, exact versioned scoring, draft state/order/pool, soft-reversed picks, successful idempotent requests, and audit history. Composite FKs bind league/draft/season references; partial indexes protect active picks. All new tables enable RLS and revoke ordinary-client privileges, without policies or RPCs. See [ARCHITECTURE.md](ARCHITECTURE.md) for table/constraint details, deferred invariants, deletion behavior, and exact review/apply commands.

Supabase CLI 2.122.0 version/help inspected. Initialized config and generated ignores reviewed; signing-key JSON exclusion added. User reports the repository linked to `playoff-fantasy-dev`; Docker is absent. No hosted schema/credential inspection or migration/database command was run. Config is versionable and unchanged; local link/cache state and secrets remain ignored. No dependencies, UI, authentication flows, commits, or pushes were added.

Verification on 2026-10-28: `npm test` (37 tests), `npm run lint`, `npx tsc --noEmit`, and `git diff --check` pass. Static review checks scoring-column parity, table-by-table RLS/revocations, FK targets, and ignore behavior. At that point the SQL was **unexecuted**, not database-tested; the later execution evidence is recorded below. Pure tests establish no database authorization/concurrency guarantees.

## Milestone 2B storage verification

On 2026-11-03 the user reported migration 20261028000000 applied to `playoff-fantasy-dev`, with dashboard-confirmed RLS on all 14 tables and no `anon`/`authenticated` SELECT privilege. After authorizing direct query execution, the linked CLI query of [foundation-verification.sql](../supabase/tests/foundation-verification.sql) returned `foundation_verification: PASS`, exit status 0. The whole script runs inside `BEGIN ... ROLLBACK`, with generated synthetic fixture UUIDs and no schema or `auth.users` changes.

The script explicitly asserts table/RLS/access defaults, valid storage inserts, cross-league/draft FK rejection, active-pick uniqueness, reversal/reuse, duplicate request rejection, all scoring weights, invalid positions, and original-request preservation. Account detachment is catalog-checked only; behavior testing awaits authorized authentication fixtures. This is storage-constraint evidence, not RPC authorization, turn-order enforcement, concurrency, or retry-implementation evidence. Verification acceptance remains pending user review; do not mark milestone 2B complete.

To rerun in the development SQL Editor, use the entire file as `postgres`, require `foundation_verification = PASS` with no errors and final rollback completion. **After any test failure, run `ROLLBACK;` before other SQL in that session.** Detailed run instructions and limits are in [ARCHITECTURE.md](ARCHITECTURE.md#running-the-foundation-verification).

Existing checks on 2026-11-03: `npm test` (37 tests), `npm run lint`, `npx tsc --noEmit`, and `git diff --check` pass. No dependencies, migrations, commits, or pushes were added/applied during this verification task.

## Next bounded task

Review the script and captured PASS result with the user, then agree the remaining development-database verification needed before accepting milestone 2B. Account-deletion behavior still requires separately authorized authentication fixtures. No new schema, permissive reads, authentication flows, UI, or draft RPCs are authorized by this plan.

Freeze, cutoff, role/turn checks, request semantics, and pause/undo synchronization need future authorized transactions (milestone 5); narrow access policies and invitation/auth flows are later work. Games, actual stats/import jobs, projections, and finalized-result snapshots are excluded from the foundation migration. Import leases/snapshots remain proposals; ranking sources and provider classifications remain deferred decisions.

## Working boundaries

- Explain focused changes and verification; update documents when accepted decisions change.
- Keep synthetic/demo data visibly separate from production behavior.
- Keep credentials out of Git; use SQL migrations and minimal infrastructure.
- Do not install third-party skills or execute their scripts without review.
- Future tasks are governed by their explicitly authorized scope; milestone descriptions do not authorize external setup or dependency installation by themselves.

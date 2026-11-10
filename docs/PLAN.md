# Delivery plan

Build one milestone at a time. [SPEC.md](SPEC.md) contains confirmed rules and open decisions; [ARCHITECTURE.md](ARCHITECTURE.md) proposes implementation. A proposal is not an approved product change.

## Current status

Milestone 1 is complete for this documentation task: the documents capture the supplied rules, distinguish proposals/open choices, preserve the generated Next.js instructions, and bound the next task. Milestone 2A is also complete: pure draft-order and scoring modules plus automated tests are implemented. Milestone 2A performed no database, authentication, UI, realtime, external API, or deployment work. The user reports the foundation migration applied to development. The rollback-only storage script returned PASS on 2026-11-03; The user accepted this storage verification on 2026-11-04; milestone 2B is complete within the verification limits below. Milestone 3A was accepted on 2026-11-06 based on user-reported real delivery/confirmation, persistence across refresh/browser restart, sign-out protection, and Safari-to-Chrome verification; physical cross-device and access-token-expiry refresh checks remain unverified.

Verified on 2026-10-27: existing App Router starter under `src/app/`; Next.js 16.4.3, TypeScript, Tailwind, npm, ESLint; `npm run lint` and `npx tsc --noEmit` pass. Starter loading was reported in the brief, not independently browser-verified here. No production build, deployment, or multiplayer behavior is claimed.

Existing scripts: `npm run dev`, `npm run build`, `npm run start`, `npm run lint`, `npm test`. Tests use Node’s built-in runner with `tsx` (the only added development dependency) to execute TypeScript directly. `npx tsc --noEmit` uses the installed TypeScript compiler. Read relevant installed framework docs in `node_modules/next/dist/docs/` before writing code.

## Milestones and exit checks

| # | Scope | Meaningful verification | Status |
| --- | --- | --- | --- |
| 1 | Repository documentation and starter verification | Requirements/proposals/questions separated; framework guidance preserved; lint/typecheck pass; next task explicit. Runtime evidence qualified above. | Complete |
| 2A | Pure snake-draft order and exact-scoring logic with meaningful tests | Test both 10×8 and 12×7 plus independent settings, round reversals, exact scoring and negative yardage. No database integration, authentication, UI, external services, imports, or deployment. | Complete |
| 2B | Database schema, migrations, constraints, and access-policy design | Foundation applied to development; storage constraints and deny-by-default table access verified by the rollback-only script. RPC and account-deletion behavior remain outside this verification. | Complete (accepted 2026-11-04) |
| 3A | Supabase email sign-in and server sessions | Token-hash email confirmation by explicit POST, server-verified account and sign-out, persistent-session and cross-browser manual checks. | Complete (accepted 2026-11-06; limits below) |
| 3B1 | Active-league reads and league overview | Member-scoped column grants/RLS, own-session pages, safe bootstrap, authenticated/JWT-context isolation tests. | Complete (user-verified 2026-11-10) |
| 3B2 | Commissioner invitations and membership claiming | Test invited-email claim, wrong-email denial, mutation role restrictions, and account-history preservation. | Deferred next slice |
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

The script explicitly asserts table/RLS/access defaults, valid storage inserts, cross-league/draft FK rejection, active-pick uniqueness, reversal/reuse, duplicate request rejection, all scoring weights, invalid positions, and original-request preservation. Account detachment is catalog-checked only; behavior testing awaits authorized authentication fixtures. This is storage-constraint evidence, not RPC authorization, turn-order enforcement, concurrency, or retry-implementation evidence. The user accepted the successful development run on 2026-11-04, completing milestone 2B. RPC authorization, turn enforcement, concurrency, retry behavior, and account-deletion behavior are not yet tested.

To rerun in the development SQL Editor, use the entire file as `postgres`, require `foundation_verification = PASS` with no errors and final rollback completion. **After any test failure, run `ROLLBACK;` before other SQL in that session.** Detailed run instructions and limits are in [ARCHITECTURE.md](ARCHITECTURE.md#running-the-foundation-verification).

Existing checks on 2026-11-03: `npm test` (37 tests), `npm run lint`, `npx tsc --noEmit`, and `git diff --check` pass. No dependencies, migrations, commits, or pushes were added/applied during this verification task.

## Milestone 3A implementation and verification

Implemented on 2026-11-05: browser/server Supabase utilities, Next.js 16 session-refresh proxy, `/login` with an email-only local preference, sessionless email-link request action (`shouldCreateUser: false`), token-hash GET/POST confirmation, protected `/account`, and server-action sign-out. Only the configured application origin and `/account` post-login destination are used. No service key, league-table policies, or membership claims are added. Hosted settings, users, SMTP, migrations, and deployments were not changed; no real emails were sent.

[AUTH_SETUP.md](AUTH_SETUP.md) contains exact environment/hosted URL settings, the required custom Magic Link HTML, supported confirmed test-account provisioning, signup disabling, the user-reported Resend SMTP setup, and manual verification steps. The default template is incompatible with this explicit-POST confirmation flow. GET has no third-party assets, uses origin-only `strict-origin` referrer policy, and does not consume the token; POST uses `verifyOtp` without a requesting-browser verifier cookie. Server identity uses `getClaims`/`getUser`; authentication remains separate from membership.

Checks: `npm test` passes 49 tests (37 existing pure tests plus 12 auth tests). New tests use mocked sender/verifier callbacks and synthetic in-memory storage, not real Supabase Auth or browser cookies. `npm run lint`, `npx tsc --noEmit`, and `git diff --check` pass. `npm run build` was attempted: the sandbox could not fetch the scaffold's Google Fonts; a network-enabled retry failed in Turbopack CSS processing because a local process/port bind was denied (`EPERM`). A subsequent production build during confirmation-POST debugging passed in this environment; those initial failures are historical. The production dependency audit reported no vulnerabilities; npm's full installation audit reported moderate development-tool findings, which were not automatically upgraded.

Confirmation POST follow-up: an isolated Chrome fixture reproduced `Origin: null` for a native form under `no-referrer`, and a matching Origin with no referrer path/query under `strict-origin`. Confirmation header/meta/config now agree on `strict-origin`; exact-Origin validation and rejection of null/missing origins remain. Development-only origin/Fetch Metadata/rejection diagnostics and regression tests were added. The full suite now passes 60 tests; lint, typecheck, production build, and diff checks pass. This reproduction used synthetic local forms, not real Auth tokens. The user subsequently confirmed the real manual results below.

User-reported manual verification accepted on 2026-11-06:

- Real email delivery and successful confirmation.
- Session survives page refresh and browser restart.
- Sign-out makes `/account` require sign-in again.
- A link requested in Safari successfully verifies in Chrome.

Milestone 3A is complete with limits: physical cross-device testing and session refresh after access-token expiry remain unverified. One-time/expired-link edge cases and other checklist items are not implied by these reported results. Sanitized diagnostics remain enabled only in development; browser messaging stays generic. Scanner protection reduces accidental consumption but cannot stop scanners that submit forms. Localhost works across browsers on the same computer; physical cross-device testing waits for an authorized deployed HTTPS origin.

## Milestone 3B1 implementation (2026-11-10)

Added [20261110000000_league_membership_reads.sql](../supabase/migrations/20261110000000_league_membership_reads.sql) with column-scoped authenticated SELECT on leagues, safe membership roster fields, and scoring versions. A non-exposed, postgres-owned helper derives identity from `auth.uid()` and checks active membership without recursive RLS. No user UUID/email column or mutation privilege is granted; eleven other tables stay closed. The applied foundation migration is unchanged.

Added server-rendered `/leagues` and `/leagues/[leagueId]` with the existing verified user's client/session, account navigation, generic nonmember not-found, genuine empty state, unavailable states, explicit season/configuration/roster/scoring presentation, and no-store/proxy coverage. No elevated keys, invitations, drafts, creation UI, or imports are used.

Prepared a separate atomic, rerunnable [development bootstrap](../supabase/setup/development-league.sql) with a private confirmed-user UUID placeholder, one named 2026 league (10 slots × 8 rounds), exact scoring, and only that account as commissioner. Prepared [authenticated/JWT-context verification](../supabase/tests/league-membership-reads.sql) requiring three separately provisioned confirmed test accounts. Updated foundation verification checks exact column grants while retaining all storage/closed-table assertions. [LEAGUE_ACCESS.md](LEAGUE_ACCESS.md) explains setup, grants/helper safety, scripts, expected results, and HTTP/browser checks.

Checks on 2026-11-10: `npm test` passes 63 tests; `npm run lint`, `npx tsc --noEmit`, `npm run build`, and `git diff --check` pass. The three new pure tests cover league UUID validation, safe projections, and season/scoring presentation.

User-reported acceptance on 2026-11-10: the read migration was applied to `playoff-fantasy-dev`; `league_membership_reads_verification` and the updated `foundation_verification` both returned PASS; the development bootstrap executed successfully. The commissioner can view the development league and scoring. A separate confirmed account sees no leagues and cannot access the commissioner's league by direct URL. Milestone 3B1 is complete on this evidence. The parenthesized CASE comparison fix is saved in the repository verification script; repository test/bootstrap files retain UUID placeholders.

Database PASS results and browser checks are user-reported, not inferred from mocked tests or rerun during documentation finalization. A separate direct Data API HTTP probe is not claimed. Physical cross-device use, access-token-expiry refresh, and account-deletion behavior remain outside this acceptance. Invitations, membership claiming, and commissioner invitation controls are unimplemented.

## Next bounded task

Begin a bounded milestone 3B2 design for commissioner invitations, verified-email membership claiming, and commissioner invitation controls. These remain unimplemented; invitation templates/types need their own supported token handling and explicit authorization before hosted changes or sending.

Freeze, cutoff, turn/role checks, retry semantics, and pause/undo synchronization need future authorized transactions (milestone 5). The plan does not itself authorize hosted changes, account creation, email sending, schema application, deployment, commits, or pushes.

## Working boundaries

- Explain focused changes and verification; update documents when accepted decisions change.
- Keep synthetic/demo data visibly separate from production behavior.
- Keep credentials out of Git; use SQL migrations and minimal infrastructure.
- Do not install third-party skills or execute their scripts without review.
- Future tasks are governed by their explicitly authorized scope; milestone descriptions do not authorize external setup or dependency installation by themselves.

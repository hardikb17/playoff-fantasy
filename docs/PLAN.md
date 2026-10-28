# Delivery plan

Build one milestone at a time. [SPEC.md](SPEC.md) contains confirmed rules and open decisions; [ARCHITECTURE.md](ARCHITECTURE.md) proposes implementation. A proposal is not an approved product change.

## Current status

Milestone 1 is complete for this documentation task: the documents capture the supplied rules, distinguish proposals/open choices, preserve the generated Next.js instructions, and bound the next task. No application features or external services have been implemented/configured.

Verified on 2026-10-27: existing App Router starter under `src/app/`; Next.js 16.4.3, TypeScript, Tailwind, npm, ESLint; `npm run lint` and `npx tsc --noEmit` pass. Starter loading was reported in the brief, not independently browser-verified here. No production build, deployment, or multiplayer behavior is claimed.

Existing scripts: `npm run dev`, `npm run build`, `npm run start`, `npm run lint`. There is no test script. `npx tsc --noEmit` uses the installed TypeScript compiler. Read relevant installed framework docs in `node_modules/next/dist/docs/` before writing code.

## Milestones and exit checks

| # | Scope | Meaningful verification | Status |
| --- | --- | --- | --- |
| 1 | Repository documentation and starter verification | Requirements/proposals/questions separated; framework guidance preserved; lint/typecheck pass; next task explicit. Runtime evidence qualified above. | Complete |
| 2A | Pure snake-draft order and exact-scoring logic with meaningful tests | Test both 10×8 and 12×7 plus independent settings, round reversals, exact scoring and negative yardage. No database integration, authentication, UI, external services, imports, or deployment. | Next |
| 2B | Database schema, migrations, constraints, and access-policy design | Review keys, frozen configuration, active-pick/request uniqueness, durable ownership and RLS boundaries; then apply migrations and validate constraints and designed policies against an actual development database. SQL review alone does not complete this milestone. | Not started |
| 3 | Supabase, policies, invitations, email links | Decide delivery and identity-claim details. Test invited-email claim, wrong-email denial, role restrictions, cross-league reads/writes and direct database policy enforcement; account removal preserves history. | Not started |
| 4 | Eligible pool and configuration | Validate season/team/position and individual kickers; verify no duplicate identities, finalized pool/order, logged rerandomizations, independent league settings, and configuration freeze. Review rank source and cutoff authority. | Not started |
| 5 | Authorized atomic draft operations | Real database concurrency tests: competing picks, stale versions, successful-request retry, payload conflict, commissioner on-behalf permission, pause/resume races, undo/reuse, final-pick undo, cutoff blocking, and durable recovery. Agree cutoff resolution policy before launch. | Not started |
| 6 | Draft UI and synchronization | Multi-user/mobile checks, refresh/restart/reconnect snapshots, stale notification rejection, periodic refresh fallback, pending/uncertain requests, informational presence. No simulated security/persistence/multiplayer presented as complete. | Not started |
| 7 | Synthetic scoring, imports, rosters, standings | Labeled fixture imports; exact category scoring, safe identical/corrected reimports, failed/incomplete/stale imports preserving scores, shared effects across frozen league scoring, audited admin corrections. Check bye/elimination, tie ranks, freshness/data states, provisional → reconciled → finalized and logged reopening. Resolve mapping/import/finalization policy questions first. | Not started |
| 8 | Deployment and multi-user acceptance | Configure services only in authorized follow-up work. Verify preview/local isolation, secrets, domain/hosting, policy and end-to-end multi-user behavior, protected export and successful restore. | Not started |
| 9 | Actual stats provider research/integration | Compare availability, licensing/access, IDs, category completeness, corrections and provenance. Select explicitly; verify real completed-game imports and safe reimports against fixtures. No assumed API or scraping. | Deferred |
| 10 | Current-matchup projections | Research/select model/source; verify bye/eliminated/pending states, saved model/scoring provenance, and separation from actual scores and overall draft ranks. | Deferred; outside MVP |

Milestone 8 demonstrates a fixture-backed application; real-data readiness additionally requires milestone 9. Live stats remain a long-term goal with no implementation milestone yet.

## Next bounded task

Implement milestone 2A only: pure snake-draft order and exact-scoring functions with meaningful tests. Review the test runner before adding dependencies; no test command currently exists. This bounded task excludes database schema work and integration, authentication, UI, external services, imports, and deployment.

Acceptance: both reference configurations and independent settings produce the correct turns across round boundaries; scoring exercises every confirmed rule, distance boundaries (39/40/49/50), negative yards, separate turnovers, normalized conversion/TD categories without double-counting, no bonuses, and exact two-decimal presentation. Use normalized synthetic inputs; do not invent provider classifications. Pure tests do not establish authorization, persistence, or concurrency correctness.

Milestone 2B follows separately: design schema, migrations, constraints, and access policies, then validate against an actual development database. Its review must account for undo reuse, request uniqueness, durable membership ownership, and policy enforcement. Full draft transaction/concurrency tests remain in milestone 5.

Import leases and finalized-result snapshots remain implementation proposals for later review. Ranking sources and unusual recovery-TD/blocked-kick provider classifications remain deferred decisions. None blocks milestone 2A.

## Working boundaries

- Explain focused changes and verification; update documents when accepted decisions change.
- Keep synthetic/demo data visibly separate from production behavior.
- Keep credentials out of Git; use SQL migrations and minimal infrastructure.
- Do not install third-party skills or execute their scripts without review.
- Future tasks are governed by their explicitly authorized scope; milestone descriptions do not authorize external setup or dependency installation by themselves.

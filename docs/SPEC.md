# Product specification

Status: confirmed requirements from the project brief. Implementation proposals are in [ARCHITECTURE.md](ARCHITECTURE.md); unapproved choices are listed below. Delivery status and verification are in [PLAN.md](PLAN.md).

## Season and competition

- Private, isolated leagues for the **2026 NFL season (playoffs conclude in 2027)**. Current season only; no historical league imports.
- Initial configuration: 10 managers × 8 rounds = 80 picks. Second configuration: 12 × 7 = 84. Manager count and rounds are independent settings.
- NFL identities, games, and actual stats are shared across leagues. A player can be drafted once in each league, independently of other leagues.
- All eligible playoff points from every drafted player count. No benches, weekly lineups, trades, pickups, replacements, or substitutions.
- Highest cumulative actual points after the Super Bowl wins. Equal totals share rank; no automatic competition tiebreaker. The group resolves ties separately.

## Access

- Commissioner-approved email invitations grant league membership; email sign-in links verify account identity. An invited email can claim only its assigned membership. No open league registration.
- Roles: member, league commissioner, application administrator. Authorize league and membership reads/writes on the server and through database access policies.
- Account deletion or departure must preserve picks and scores.
- Email delivery provider and implementation are unselected.

## Eligible players

- Only that season's playoff teams; QB, RB, WR, TE, and individual K. No position limits, team-kicker slots, team defense, or individual defensive players.
- Finalize eligibility and kicker identities before drafting. Injury information may be shown but never automatically removes eligibility.
- Use stable internal identities and provider ID mappings; aliases serve search only. Preserve season-specific team and position.

## Draft

- Snake order is randomized on the server, persisted, and finalized before starting. Log and display every pre-start rerandomization.
- At start, freeze membership, rounds, order, player pool, and scoring. No timer, autopick, or skipped turns.
- Only the current manager may pick, except a commissioner explicitly acting on that manager's behalf.
- Commissioner may start, pause, resume, and undo the latest pick. Undo requires a paused draft and no playoff game having started; it restores the previous turn and availability.
- The final pick automatically completes the draft and establishes final rosters. An accidental final pick is undoable under the same paused/pregame rule; completion must not make that path inaccessible.
- All drafting must finish before the first playoff game starts. At the cutoff, block further picks in unfinished drafts and require explicit administrative resolution. The resolution policy is unresolved; no automatic completion or exception is approved.
- Persist progress across refreshes, disconnects, and server restarts. Presence is informational.

### Correctness acceptance criteria

- PostgreSQL is authoritative. A single pick transaction locks state, verifies actor/membership, running status, expected pick/version, turn, eligibility, and availability; writes the pick; advances turn/version; and completes the draft if appropriate.
- Every request has a unique identity. A retry of a successful request returns the existing result. Enforce uniqueness for player per draft, overall pick per draft, draft-order position, and request identity.
- Reversed picks do not prevent reuse of player or pick slot. Pause, resume, and undo use compatible locking.
- Disabled buttons and realtime delivery are never correctness controls. Notifications trigger authoritative fetches; reconnect fetches a full snapshot. Versions reject stale state, and periodic refresh provides a fallback while the room is open.
- UI clearly shows pending requests and uncertain connection outcomes.

## Exact actual scoring

Do not substitute a provider's generic PPR rules.

| Stat | Points |
| --- | ---: |
| Passing yard | 0.04 |
| Rushing yard / receiving yard | 0.10 each |
| Reception | 1 |
| Passing touchdown | 4 |
| Rushing touchdown / receiving touchdown | 6 each |
| Individual return touchdown, for a drafted scorer | 6 |
| Passing / rushing / receiving two-point conversion | 2 each |
| Interception thrown | -2 |
| Fumble lost | -2 |
| Field goal made under 40 yards | 3 |
| Field goal made 40–49 yards | 4 |
| Field goal made 50+ yards | 5 |
| Extra point made | 1 |
| Missed field goal / missed extra point | -1 each |

- Other fumbles have no penalty. No long-play bonuses, yardage bonuses, or return-yardage points.
- Store interceptions and fumbles lost separately, and keep relevant stat categories separate. Do not double-count touchdowns or conversion plays.
- Use exact decimal or integer arithmetic; display two decimal places. Legitimate negative yardage is valid.
- Unusual recovery touchdowns and blocked-kick classifications require explicit mapping decisions; do not infer scoring rules.

## Postgame data and results

- Initial delivery: commissioner-triggered backend import after a game ends. Live stats are a long-term goal. Start development with visibly synthetic fixtures.
- Provider research is deferred. No provider is chosen; do not assume Football Reference has an API or scrape a website.
- Ingestion is provider-independent and separate from scoring. Validate game identity/completion, player mappings, and completeness; record provenance; atomically publish game/player stats and affected scores.
- Reimports replace/update the same game records without duplicate points. Failure preserves published scores. Serialize conflicting imports or prevent older responses from overwriting newer successful imports.
- Unknown/missing stats are not confirmed zeros. Shared stats update every relevant league under its frozen scoring rules.
- Record requester, timestamps, provider, status, source snapshot, unresolved mappings, and changes. Only application administrators may make shared manual stat corrections; audit them.
- Standings show included games and freshness; distinguish zero, awaiting import, and unavailable data.
- Derive rosters from valid picks, without an editable roster system. Show player, NFL team, position, draft pick, round scores, total, matchup, and team playoff status.
- Eliminated players retain earned points. Players remaining counts players whose teams are not eliminated, regardless of injury. Bye players remain alive and earn no points that round.
- After the Super Bowl import: provisional results → reconciliation → commissioner finalization. Reopening is explicit and logged.

## Later: projections (outside MVP)

- Current scheduled matchup only; never hypothetical remaining playoffs. Keep projections separate from actual scoring.
- Bye: “Bye,” no numeric projection. Eliminated: 0 plus “Eliminated.” Unknown matchup or missing projection: Pending/Unavailable, never zero.
- Save model/source version, generation time, player/game identity, and scoring configuration.
- Current-matchup projections must not be the default overall draft ranking. Reviewed draft rank with search/team/position filters is proposed, not approved; its source is unresolved. Model research and implementation are deferred.

## Open decisions (recommendations are not approval)

| Decision | Tradeoff | Recommended default |
| --- | --- | --- |
| Unfinished draft at cutoff | Exceptions could change competition fairness; automatic picks would violate the rules. | Keep blocked pending an application-admin documented resolution; agree permitted resolutions before draft launch. |
| Recovery TDs / blocked kicks | Provider categories may not match intended scoring. | Flag unresolved mappings and retain prior published scores until explicitly resolved. |
| Email delivery / invitation mechanics | Managed delivery reduces operations; provider and identity-normalization behavior need validation. | Use Supabase Auth email links with a reviewed transactional email provider; decide before milestone 3. |
| Draft ranking data | Reviewed ranks aid drafting but require a trustworthy source and maintenance. | Review a season-specific rank list before draft launch; do not replace it with matchup projections. |
| Import trigger across isolated leagues | A commissioner starts an import, but canonical stats affect other leagues. | Permit only completed games relevant to that commissioner's league; audit the global effect and agree policy before imports ship. |
| Finalization and later corrections | Shared corrections can change totals after a league finalizes. | Preserve a finalized result snapshot and require explicit logged reopening before republishing changed results; confirm before milestone 7. |

Import leases and finalized-result snapshots remain implementation proposals; ranking sources and unresolved provider classifications remain deferred decisions. None is a prerequisite for pure-logic milestone 2A in [PLAN.md](PLAN.md).

No contradictions were identified in the brief. In particular, independent manager/round settings, post-completion undo, and shared stats with league isolation must all be preserved together.

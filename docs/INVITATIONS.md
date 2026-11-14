# Commissioner invitations and membership claiming (3B2)

Status: **database slice implemented locally (2026-11-11), migration unapplied and SQL unverified**. Email integration and UI remain proposals, not implemented/configured. The development defaults below were authorized for this database slice. [SPEC.md](SPEC.md) remains the product specification; [PLAN.md](PLAN.md) bounds implementation. Existing 3A sign-in and 3B1 league reads remain unchanged.

## Confirmed requirements

An active commissioner invites a display name and email into their league, always as **member**. New and existing Auth accounts are supported; one account may join multiple leagues. Public signup stays disabled. Authentication proves identity; a separate explicit claim POST grants the assigned membership. A verified email mismatch must fail even with a valid invitation ID. Ordinary members/nonmembers cannot manage or inspect invitations; the intended recipient may read only their own claim details. Invitation addresses never enter the general roster.

Active memberships plus valid reservations cannot exceed `manager_count` (initially 10, including the commissioner). Duplicate invitations share one reservation; resend has a server cooldown. Expiry/revocation releases a slot. Issuance, resend, and claim stop once the draft starts. Claimed memberships are never overwritten, and departed memberships are never automatically restored. GET requests neither send email nor verify tokens nor claim membership.

## Recommended flow — pending review

Use the existing Supabase SMTP for first-time Auth invitations, a small server-only Resend notification call for confirmed existing accounts, and database-authorized membership claiming. No queue, worker, global account directory, or general account-management UI.

1. Commissioner submits an explicit same-origin POST. Verify their session with server `getUser`; reserve a slot through an actor-authorized database transaction. Commit before external calls.
2. Recheck active commissioner authority and reservation validity immediately before dispatch. Call server-only `auth.admin.inviteUserByEmail(email)`. This provisions/invites a new account or reinvites an unconfirmed account. It does **not** grant league membership. Supabase rejects confirmed existing accounts; only the specific structured `email_exists` response selects the existing-account branch. A timeout, rate limit, SMTP failure, or unfamiliar error must not select that branch. Confirm the hosted error contract in integration tests, failing closed if it differs. See [Supabase invite API](https://supabase.com/docs/reference/javascript/auth-admin-inviteuserbyemail), [Auth users](https://supabase.com/docs/guides/auth/users), and the [official invite implementation](https://github.com/supabase/auth/blob/master/internal/api/invite.go) inspected on 2026-11-10; upstream source is not proof of the hosted version.
3. For a confirmed existing account, reauthorize dispatch and send a plain application invitation notification through [Resend's email API](https://resend.com/docs/api-reference/emails/send-email). Link to the configured origin's `/account`, with no Auth token. The recipient uses their current session or the existing `/login` flow. Do not request a new OTP merely because someone invited them: this preserves outstanding sign-in links and sessions. Both branches show the commissioner the same account-neutral delivery status, never whether the address has an account or belongs to another league.
4. A new recipient opens the Supabase invitation in any browser, sees Continue, and explicitly POSTs to verify `type=invite`. This establishes a confirmed Auth identity and browser session; it does not claim a slot. Redirect to clean `/account`, which will show that verified email's pending invitations and a separate Claim button. A signed-in existing recipient reaches the same claim step without another Auth exchange.
5. Claim POST uses the user's session and an atomic, email-bound database operation. Return the existing outcome on a successful retry. After claim, existing 3B1 reads expose the league naturally through the new membership.

**Why two delivery branches:** `inviteUserByEmail` alone does not support confirmed existing users. Falling back to `signInWithOtp` would be smaller, but can replace an outstanding login token. The selected recommendation adds one server-only Resend sending credential to meet the requirement to preserve existing sign-in links. Existing hosted SMTP credentials are not an application API key. This additional credential/integration is a proposal requiring review, not permission to provision it. `generateLink` plus custom delivery is another supported option, but makes the app handle Auth bearer links and still generates authentication tokens; it offers no needed simplification here. See [generateLink](https://supabase.com/docs/reference/javascript/auth-admin-generatelink).

## Identity, templates, and confirmation protection

Keep the current Magic Link template and `/auth/confirm` (`type=email`) intact. Add a separate `/auth/invite/confirm` accepting only `type=invite`; do not broadly accept all OTP types. The proposed **Invite User** template is:

```html
<!doctype html>
<html lang="en"><body>
<h2>You have been invited to Playoff Fantasy</h2>
<p>Confirm your email, then review and claim your league invitation.</p>
<p><a href="{{ .SiteURL }}/auth/invite/confirm?token_hash={{ .TokenHash }}&amp;type=invite">Continue</a></p>
<p>If you did not expect this invitation, ignore this email.</p>
</body></html>
```

Configure this only in separately authorized implementation/setup work. Use the configured Site URL, never arbitrary Host headers or client return URLs. Supabase supports template token hashes and `verifyOtp`; verification of the invite token, not commissioner input or user metadata, establishes email ownership. Do not auto-confirm accounts via `createUser({email_confirm:true})`. Token-hash verification needs no requesting-browser PKCE cookie. See [email templates](https://supabase.com/docs/guides/auth/auth-email-templates) and [verifyOtp](https://supabase.com/docs/reference/javascript/auth-verifyotp).

Copy the existing confirmation safeguards: standalone GET HTML, no third-party assets, `private, no-store`, restrictive CSP with `form-action 'self'`, and **`strict-origin` in both header and meta**. The confirmed Chrome `no-referrer` / `Origin:null` failure must not return. POST requires the exact configured Origin and same-origin Fetch Metadata when present; never generally allow null/missing Origin. Verify only on explicit POST, set session cookies, then 303 to a token-free internal URL. Missing/invalid/expired/used Auth links get a safe error with recovery, never provider details. A scanner that submits forms remains a known limitation.

The application invitation ID is a locator, not a bearer credential; no application secret is needed in this proposal. Claim always requires independently verified matching identity. Supabase email authentication links **are bearer credentials**: a person who obtains one may authenticate as its recipient. Separate claim POSTs cannot protect a compromised mailbox or forwarded Auth credential; do not describe the Auth URL itself as harmless. If an application secret is later introduced, store only its cryptographic hash and retain the identity check.

Auth link expiry and league reservation expiry are independent. A confirmed account can request a fresh normal Magic Link without creating another reservation. An unconfirmed account with an expired Invite User token asks the commissioner to resend the **same** reservation; do not assume ordinary OTP signup behavior works with signup disabled. Retry unknown delivery first with the attempt rules below. Revocation/expiry blocks claim even if an Auth token still verifies. Do not delete an Auth account to revoke a league invitation. On invitation POST, if a session already exists, offer the current account's pending invitations or explicit POST sign-out before token verification; do not silently replace it or try to infer an unverified token's identity.

## Storage and authorized operations

[20261111000000_league_invitations.sql](../supabase/migrations/20261111000000_league_invitations.sql) implements private storage and six authenticated RPCs locally. Applied migrations and existing read grants are unchanged. No delivery dispatch/completion operation is included. Storage boundaries:

| Record | Essential data and constraints |
| --- | --- |
| Private league invitation | UUID, league FK, normalized email, display name, reserved future membership UUID, issuer membership, pending/claimed/revoked/expired state, expiry, claim identity/membership, timestamps. Unique pending `(league_id, normalized_email)`; unique reserved membership UUID. Composite FKs keep issuer/claimed membership in the same league. |
| Private operation request | Actor UUID snapshot, league, request key, operation, canonical payload and outcome; unique league/actor/key. Reject conflicting key reuse; retain original successful outcomes. Do not expose private payloads in member reads. |
| Private delivery attempt | Invitation/league FK, generation, unique request association, prepared/superseded/cancelled state and preparation/update times. One prepared generation per invitation. Dispatch, provider fields, in-flight recovery, and sending/accepted/failed/unknown states require the email slice. No tokens or URLs. |
| Private invitation audit | League/invitation, actor durable membership and UUID snapshot, action/time, request/attempt IDs and state change. Audit issuance, resend, revoke, expiry, claim; no raw email in ordinary draft audit events. |

Keep these records in non-exposed `app_private`, revoke client table access, explicitly enable RLS, and expose only narrow RPC results. Do not add email columns/grants to the roster. Public callable RPCs must revoke PUBLIC/anon execution, grant only intended authenticated execution, use a fixed empty search path with fully qualified objects, and derive actor identity from `auth.uid()`. Security-definer functions must perform their own role/recipient checks, without recursive membership policies. Use restricted internal functions for delivery completion; no caller may fabricate accepted delivery or choose an arbitrary recipient. Retain history with restrictive application FKs; Auth account deletion must not cascade away invites/audit or alter request identity. Future mutation functions maintain `updated_at`.

Implemented RPC boundaries (internal dispatch remains deferred):

- `issue_invitation`, `prepare_invitation_resend`, `revoke_invitation`: active commissioner in that league only; server-owned role always member. Issue returns `already_member` only for membership in this league, not global account existence. Duplicate issue returns the current reservation; it does not silently send again or edit its name/email. Editing a mistaken unclaimed invitation means revoke and issue anew.
- `list_commissioner_invitations`: recheck active commissioner, return only their league's management projection. No member/nonmember list access.
- `list_my_invitations`: only pending claim information matching the caller's **current confirmed Auth email**, with minimal league/display-name/expiry details; never a general pre-membership league read grant.
- `claim_invitation`: derive UID and current email confirmation from trusted Auth state, not a submitted email, JWT user metadata, or stale embedded session user. A scoped definer lookup of `auth.users` may read identity; never directly write Auth tables. Server `getUser` also verifies identity. Serialize that identity read against concurrent email changes (a read lock after the application locks). Check invitation, expiry, matching normalized email, draft gate and membership uniqueness under lock; insert the reserved membership UUID with member role and update claim/request/audit atomically.
- Internal dispatch admission/completion: server verifies the caller independently, invokes an actor-bound authorization check, and dispatches only the stored reservation payload. No service credential is accepted as proof of commissioner authority. A delivery completion checks attempt/generation and cannot create membership or revive a revoked invite.

Use a cookie-bound client for user RPCs and subsequent league reads. A separate server-only Supabase admin client is necessary for `inviteUserByEmail`; disable persistence/refresh/URL detection and never attach it to browser cookies. A separate server-only Resend key is needed for notifications. Neither key uses `NEXT_PUBLIC_`. No global Auth user listing is needed. Restrict privileged clients to these explicit delivery operations; every dispatch/retry needs a fresh independently verified commissioner, not a service-only endpoint.

## Capacity, state transitions, and locking

Every capacity-changing operation locks **the league row first**, then the existing draft row if any, then invitation/attempt/membership rows in a documented fixed order. The league lock exists even before a draft is created. Future draft creation/start, manager-count changes, and membership departure/restoration must use this same protocol. Never hold database locks across email/Auth network calls.

Count all memberships with `departed_at IS NULL`, including account-detached historical memberships, plus pending invitations with expiry after the database clock. Do not count a reservation twice when it becomes a membership. Reserve a future membership UUID at issuance; insert the membership only at claim, so unclaimed invites do not appear as active managers in 3B1's roster. New operations also touch the locked league's `updated_at`, so older REPEATABLE READ snapshots must retry with SQLSTATE 40001 instead of counting stale reservations. Exact request retries return before that update. Legacy unclaimed/detached rows are not overwritten or reused by this flow.

After acquiring locks, expire overdue pending records using `clock_timestamp()` sampled after lock acquisition, then count/check capacity and deadlines. A transaction-start timestamp can be stale after waiting for a lock. A partial unique index on pending state cannot depend on `now()`; materialize expiry during mutations and exclude logically expired records in reads/counts. No periodic job is required to release capacity. Manager-count reductions cannot put occupancy above capacity.

| From | Explicit operation / condition | Result |
| --- | --- | --- |
| None | Issue, capacity available, draft not started | Pending reservation; separate delivery attempt |
| Pending | Duplicate issue | Same reservation; no extra slot/send |
| Pending | Resend after cooldown, still valid/pre-start | Same reservation; new prepared attempt; unchanged expiry |
| Pending | Revoke or expiry | Terminal revoked/expired; slot released |
| Pending | Correct confirmed email claims pre-start | Claimed + durable active member, in one transaction |
| Claimed | Same account repeats claim | Original outcome; no new membership or role change |
| Terminal | Stale send completion or claim by another account | No reactivation or overwrite |

Reject new invites/resends/claims if draft start/freeze has ever occurred, including paused/completed states; do not rely only on `status = running`. Future start takes the league lock before the draft lock, requires a complete actual member roster with no outstanding valid reservations, then freezes membership. Thus either claim wins before start or start prevents claim. Read-only retrieval of a prior successful claim remains possible after start. If an account is already active in this league, return a clear already-member result without another slot; retire any now-redundant matching pending reservation atomically without changing that membership. If it has a departed membership, require separate explicit resolution, never automatic restoration. Preserve durable memberships and original request outcomes after departure/account deletion.

## Delivery failures and safe retries

Reservation lifecycle and delivery status are separate. A committed pending reservation can have failed/unknown delivery and still occupy a slot until claim/revoke/expiry. Commissioner can see delivery uncertainty, retry after cooldown, or revoke; no automatic deletion of a partially provisioned Auth account.

- Store request identity and a prepared attempt before dispatch. Duplicate POSTs with the same key return that operation's recorded status; they never dispatch concurrently. A different payload using the same key fails.
- Admit one in-flight attempt per invitation and enforce cooldown in the database, including failed/unknown attempts. A bounded attempt deadline converts an abandoned sending attempt to unknown; generation checks prevent a late completion overwriting a newer outcome. This is small request recovery bookkeeping, not a background queue.
- Accepted means the provider accepted the request, not inbox delivery. A definitive failure records a sanitized classification. Timeout/crash after dispatch is **unknown**, not proof that no account/email exists. Never fall back to another provider branch on ambiguity.
- For the Resend branch, retry identical persisted content with the same attempt idempotency key within its documented 24-hour window. After that, require an explicit new resend; no exactly-once promise. [Resend idempotency documentation](https://resend.com/docs/dashboard/emails/idempotency-keys).
- Supabase invitation sending has no assumed application idempotency guarantee. After an ambiguous Auth outcome, show uncertainty; an explicit cooldown-governed resend can generate another email/token but never another reservation. A confirmed-account result on a later authorized attempt may select the notification branch. Old invitation Auth links may be replaced on resend; existing normal sign-in links/sessions for confirmed accounts are untouched by invitation notifications.
- Recheck commissioner authority before each privileged call, including the fallback notification. If authority is revoked before admission, deny it. Revocation after admission cannot unsend an in-flight network request; completion records reality but cannot revive a revoked reservation. Concurrent revoke/start still makes claim fail. Document this unavoidable external-call boundary rather than claiming database/network atomicity.

Only sanitized development diagnostics may contain status, error name/code and redacted message. Never log tokens, invitation URLs, credentials, session/cookies, raw request bodies, or addresses. Private invitation data is for authorized commissioner/recipient results only; no account-existence branch details reach the UI.

## Development defaults and remaining choices

Authorized for this database slice: seven-day expiry without resend extension, database cooldown of at least 60 seconds, trim/lowercase without dot/plus rewriting, reservations retained through delivery failure/uncertainty, and continued claimability after issuer demotion. The delivery integration and retention recommendations remain **unapproved**:

| Choice | Tradeoff | Recommended default |
| --- | --- | --- |
| Reservation expiry | Longer holds simplify coordination but block unused slots. | Implemented: 168 hours from issuance; resend does not extend. Expired/revoked invitations require a new issue/capacity check. |
| Resend cooldown | Fast recovery versus duplicate mail/abuse. | Implemented: 60 seconds, server-enforced; respect stricter provider limits too. |
| Email normalization | Lowercasing is practical but technically folds case-sensitive local parts. | Implemented DB normalization: trim outer ASCII whitespace and lowercase in storage/Auth comparisons; future app code must match; no Gmail dot/plus rewriting. Reject unsupported/ambiguous formats rather than invent transformations. |
| Delivery integration | One extra sending key versus invalidating existing login tokens. | Hybrid Supabase Invite User + Resend existing-account notification described above. Review key scope/setup before implementation. |
| Failed/unknown delivery | Holding a slot needs manual attention; releasing could overbook late recipients. | Reservation lifecycle is independent of delivery preparation; hold until claim/revoke/expiry. Actual failed/unknown delivery recording and UI remain deferred. |
| Issuer loses commissioner role | Invalidating every old invite may surprise recipients. | Block further sends/management; already issued invites remain claimable unless revoked/expired/start-blocked. Account-wide session revocation is outside this slice. |
| Departed/claimed slot recovery | Automatic repair risks changing durable competition identity. | Clear already-member or needs-resolution result; no restore/reassignment UI in 3B2. |
| Private invitation retention | Audit value versus stored email exposure. | Keep for this development slice, commissioner-only; settle production retention/redaction before deployment. |

## Bounded implementation sequence

1. **Storage and authorized operations (implemented locally; development verification pending):** new migration for private reservations/requests/attempts/audit and narrow RPCs; league-first locking, capacity/expiry/cooldown, role/email checks, atomic claim and idempotency. Add rollback-only role-context tests and a real concurrent-session test procedure. Update foundation expectations for new private objects without weakening the existing 14-table/3B1 checks. No email integration, UI, hosted changes, or migration application in this first implementation task.
2. **Identity/email integration:** separate server-only privileged clients; dispatch admission/completion, supported error branching, Invite User template and dedicated protected confirmation, expired-link recovery. Keep the existing Magic Link route/template unchanged. Unit tests mock external calls and must be labeled as such. Real accounts/email/settings require separate authorization.
3. **Commissioner/recipient UI:** small league-scoped issue/resend/revoke controls; pending invites on account page and explicit claim POST; capacity, cooldown, already-member and unavailable states. No generic account administration. Maintain exact-Origin validation, uncached responses and private projections.
4. **Real database/browser verification:** separately authorized migration/setup, supported Admin/dashboard Auth fixtures (no direct `auth.users` writes), JWT-context isolation and concurrent transactions, then actual new/existing-account emails and browser sessions. Keep fixture UUIDs/credentials out of committed scripts. After a SQL failure, `ROLLBACK;` before other statements. No completion claim from mocks alone.

## Acceptance cases (not yet executed)

| Case | Required result |
| --- | --- |
| New account, signup disabled | Commissioner-only provisioning; Invite User Continue POST verifies email across browsers; separate claim inserts member only. GET/scanner visits make no mutation. |
| Confirmed existing account / multiple leagues | Notification does not issue an Auth token; existing login link/session still works. Account can claim another league without altering its other memberships. |
| Wrong email / guessed invitation ID | Verified wrong account denied without invite email/details; URL/ID alone cannot claim. Nonrecipient gets generic unavailable. |
| Expired Auth token, live reservation | Existing account normal login or unconfirmed account commissioner resend recovers identity without a second slot. |
| Expired/revoked league invitation | Claim fails even with valid authentication; slot becomes available. Late email/completion cannot restore it. |
| Repeated claim / lost response | Same actor receives original success, including after draft start; no duplicate row/role change. Conflicting request-key payload rejected. |
| Duplicate invitation / resend clicks | Canonical email has one reservation; double-click dispatches once; cooldown enforced in SQL. Dot/plus-distinct emails are not merged. |
| Two commissioners, concurrent last slot | League lock permits exactly one new reservation; active+valid reserved count never exceeds capacity. Include expiry/claim/manager-count races. |
| Revoked/departed commissioner | Cannot issue/resend/revoke/list private invites or start privileged dispatch. Test role change between page load, reservation and dispatch; in-flight boundary behaves as documented. |
| Cross-league access / ordinary member / anonymous | Cannot manage/inspect another league's invites or mutate roles; recipient sees only their own minimal offer. Existing roster/Data API never exposes emails or auth UUIDs. No recursive RLS. |
| Already active / departed / detached account | Clear same-league already-member result; no overwrite, automatic restoration, or detached-history reuse. |
| Draft-start races | Start and invitation mutations share league-first locking even without an existing draft row. No post-start issuance/claim; paused/completed do not reopen access. |
| Provider failure / timeout / crash | Reservation preserved, uncertainty honest, cooldown/retry/generation controls work; no fallback on generic errors or duplicate capacity. Test Resend idempotency window and Auth ambiguity separately. |
| Confirmation and account regression | Real Chrome strict-origin POST works; null/missing/cross-origin denied; no token leaks/cache/third-party loads. Existing Magic Links, sign-out, protected account/league reads continue working. Physical devices require a reachable HTTPS app, not localhost. |

The prepared SQL scripts have not been executed. Existing application checks do not validate invitation authorization, constraints, or concurrency. No invitation email delivery or browser behavior is claimed. Existing 3A physical cross-device and access-token-expiry refresh limitations remain.


## Database interfaces and verification

All four mutation RPCs are VOLATILE (POST through the Data API), use `auth.uid()`, and return JSON objects. Request keys are caller-generated UUIDs scoped to league/actor; operation and canonical payload must match on reuse. Wrong role/email returns SQLSTATE 42501 with safe wording; invalid input/conflicting keys returns 22023. Record business outcomes rather than throwing for capacity/cooldown/unavailable/start, allowing expiry cleanup to commit. Retrying a business rejection returns that original result; use a **new** key for a later attempt.

| RPC | Parameters / result |
| --- | --- |
| `issue_invitation` | `p_league_id`, `p_request_key`, `p_display_name`, `p_email`; prepared (invitation/attempt IDs, generation, expiry, cooldown time), existing_reservation (no new attempt), already_member, departed_member, capacity_full, draft_started. |
| `prepare_invitation_resend` | `p_league_id`, `p_invitation_id`, `p_request_key`; prepared, cooldown, unavailable, draft_started. Supersedes an older prepared attempt; never extends expiry. |
| `revoke_invitation` | Same IDs/key as resend; revoked or unavailable. Allowed after start to retire an unusable reservation. |
| `claim_invitation` | Same IDs/key as resend; claimed (membership/league/invitation IDs), already_member, departed_member, capacity_full, unavailable, draft_started. No submitted actor/email/role. Successful same-account retries retain the original result after start or departure, without restoring access. |
| `list_commissioner_invitations` | `p_league_id`; JSON array of commissioner-only name/email/state/expiry and current prepared attempt information. Rechecks active commissioner on every call. |
| `list_my_invitations` | No parameters; JSON array of unexpired, pre-start offers matching current confirmed Auth email: invitation/league IDs, league/display name and expiry. No other addresses or delivery details. |

A recorded `prepared` result is **not permission to send an email**. A later integration must add fresh commissioner dispatch admission, verify the current invitation/generation/start gate, and add restricted completion/recovery functions. Superseded, cancelled, expired, revoked, claimed, or post-start attempts cannot be dispatched simply by replaying an old request result. This slice never marks delivery accepted. Request/audit snapshots have no live Auth FK; restrictive application FKs preserve history. No application invitation secret exists.

After separately authorized development migration application:

1. Rerun the unchanged [foundation verification](../supabase/tests/foundation-verification.sql) and [3B1 verification](../supabase/tests/league-membership-reads.sql). Their existing public-table/column/RLS assertions remain required.
2. Provision four dedicated Auth fixtures using supported Admin/dashboard operations in [AUTH_SETUP.md](AUTH_SETUP.md#provision-one-approved-confirmed-test-account): three distinct confirmed email accounts A/B/C; a fourth D via Admin `createUser` with `email_confirm: false` and no password. Do not alter Auth tables directly, send invitations just to make fixtures, or use real users without consent. No accounts were provisioned by this task.
3. Privately substitute only their UUIDs in [league-invitations.sql](../supabase/tests/league-invitations.sql); never save filled copies to Git. Run the entire file as `postgres`. It reads fixture emails privately, creates generated synthetic application rows, switches authenticated/anon JWT contexts, and rolls everything back. It tests table/column/function ACLs, safe function ownership/search paths, roles/privacy, forged JWT email, unconfirmed/wrong email, TTL/cooldown/duplicates/conflicting keys, capacity/revocation/expiry, member-role atomic claim, multiple leagues, former commissioner, departure preservation, post-start gating/retries, audit and cross-league history FKs. Require `league_invitations_verification = PASS` **and final ROLLBACK**. No mocked result establishes SQL correctness.
4. Run [session A](../supabase/tests/invitation-last-slot-session-a.sql) and [session B](../supabase/tests/invitation-last-slot-session-b.sql) in two independent development SQL connections, B during A's 30-second hold. Privately supply the same existing pre-start development league and confirmed active commissioner UUID. The league must have no live pending invitations. A transactionally sets capacity to active members plus one, reserves the last slot, asserts another request is full, and holds the league lock; B must catch exactly lock timeout 55P03 instead of bypassing it. Require both PASS markers and both rollbacks. This changes no persistent fixture/configuration and sends no emails. It proves blocking plus last-slot rejection if passed; because A rolls back, it does **not** prove a loser observes a committed winner or test a real draft-start RPC. Commit-visible contention, serialization retries and future start integration still need separately authorized development tests. Existing data is restored on rollback; use dedicated test leagues/accounts.

On **any** SQL failure issue `ROLLBACK;` in the affected connection (both for the two-session test) before running other SQL. An aborted/partial script or a PASS without rollback completion is not acceptance. Migration application, Auth fixtures, all SQL execution, real contention, and future email/UI/browser tests remain pending. No Docker or local PostgreSQL installation is assumed.

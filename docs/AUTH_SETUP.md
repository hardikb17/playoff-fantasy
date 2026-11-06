# Email sign-in setup (milestone 3A)

Milestone 3A is complete as of 2026-11-06 based on the user-reported manual results below. Physical cross-device testing and session refresh after access-token expiry remain unverified. No hosted settings were changed, accounts created, or emails sent during implementation. Authentication verifies identity; it grants no league membership. All application-table grants/policies remain unchanged.

## Development environment

Use **playoff-fantasy-dev**, never a production project. In its dashboard, use **Connect** (or Project Settings → API/Data API) to obtain the project URL, and **Settings → API Keys → Publishable key** to obtain the `sb_publishable_…` key. Do not use a secret/service-role key or an SMTP credential in the app. The publishable key is public configuration, not an authorization bypass.

Copy `.env.example` to `.env.local` and replace its placeholders locally:

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_DEVELOPMENT_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_DEVELOPMENT_PUBLISHABLE_KEY
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Restart `npm run dev` after changing environment variables. `.env.example` is versioned; `.env.local` and other `.env*` files remain ignored. Never paste actual credentials, cookies, tokens, or whole sign-in URLs into logs/issues. Public environment values are compiled into browser bundles; deployment must supply the correct environment before building. No service credential belongs in `.env.local` for this slice.

In hosted **Authentication → URL Configuration**, configure exactly:

| Setting | Value |
| --- | --- |
| Site URL | `http://localhost:3000` |
| Redirect URLs | `http://localhost:3000/auth/confirm` |

Use `localhost` consistently, not a mixture with `127.0.0.1`. No wildcard or external `next` destination is needed. The request action sends the configured origin plus `/auth/confirm`; the custom template below uses Site URL directly. These two origins **must match**. Only `/account` is approved after sign-in; unknown redirect inputs fall back there. Request/forwarded Host headers are never used to construct destinations.

`supabase/config.toml` is for a local CLI stack; it does not update hosted settings. Docker is unnecessary when using hosted development Auth. Configure URLs explicitly for any future deployed environment; do not mix preview/local with production.

## Required Magic Link template

In hosted **Authentication → Email Templates → Magic Link**, set the subject to `Sign in to Playoff Fantasy` and replace the HTML with this exact template (copy only the HTML, without the Markdown fences or surrounding instructions):

```html
<!doctype html>
<html lang="en">
  <body>
    <h2>Sign in to Playoff Fantasy</h2>
    <p>Use this single-use link to continue signing in:</p>
    <p><a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&amp;type=email">Continue to sign in</a></p>
    <p>If you did not request this email, ignore it.</p>
  </body>
</html>
```

Do **not** use the default `{{ .ConfirmationURL }}` template for this implementation. It can verify the token before reaching the app. Here, GET `/auth/confirm` only displays a Continue button; POST verifies `{ token_hash, type: 'email' }` with `verifyOtp`, writes the session cookies, and returns a 303 to the configured `/account` URL without a token. The sender is sessionless and sets `shouldCreateUser: false`. This flow does not require the requesting browser's verifier cookie. See [Supabase passwordless token-hash flow](https://supabase.com/docs/guides/auth/auth-email-passwordless) and [email template variables](https://supabase.com/docs/guides/auth/auth-email-templates).

The confirmation response is plain HTML with no scripts, images, fonts, or other third-party assets. It has `private, no-store`, `Referrer-Policy: strict-origin` (origin only, never path/query), and restrictive CSP. Invalid/missing GET links show an error without verification. Invalid, expired, and already-used POST links share one clear message because those provider outcomes cannot reliably be distinguished. Provider/network failures show a generic unavailable message. POST requires an Origin matching the configured application origin to prevent login CSRF.

GET does not consume the link, reducing scanner-triggered consumption; scanners that submit forms may still consume it. Disable email click tracking/link rewriting for Auth emails where supported. Framework development request/action logging is disabled to avoid logging inputs/token-bearing URLs. The email-request action emits only the development-only sanitized diagnostic described below. Before deployment, ensure hosting/CDN/access logs redact confirmation query strings and request bodies; the app cannot control upstream logs. Do not add analytics or remote resources to the confirmation route.

## Provision one approved confirmed test account

Keep email sign-in enabled. In hosted **Authentication → Sign In / Providers**, disable **Allow new users to sign up** and anonymous sign-ins. Save and verify the hosted settings; code's `shouldCreateUser: false` alone does not disable direct public signup APIs. See [Supabase general Auth configuration](https://supabase.com/docs/guides/auth/general-configuration).

Use Supabase's supported administrator workflow to create **your own** approved test email with email confirmed. If the dashboard **Authentication → Users → Add user → Create new user** offers an auto-confirm option without a password, use that. Otherwise use `auth.admin.createUser` from a **separate trusted administrative environment** with an administrator client, not this application. The supported call is:

```ts
// One-time administrative task, not an application route or committed script.
// Obtain `admin` securely in a separate trusted environment; never expose its key.
// `approvedTestEmail` is your own approved email supplied privately at runtime.
const { error } = await admin.auth.admin.createUser({
  email: approvedTestEmail,
  email_confirm: true,
});
if (error) throw new Error('Test-account provisioning failed');
```

No password is required by this supported admin call, and it does not send an invitation email. Do not insert/update `auth.users` directly, use public signup, add an admin key to the app, or use the Invite User workflow for this slice. Provisioning is a separate manual administrative action, not performed by this task. [Supabase createUser documentation](https://supabase.com/docs/reference/javascript/auth-admin-createuser).

## Existing email delivery

User-reported hosted setup: Resend domain `auth.hardikbhardwaj.com` verified; custom SMTP saved in development Supabase; sender **Playoff Fantasy <noreply@auth.hardikbhardwaj.com>**. SMTP secrets remain exclusively in hosted settings. No SMTP or Resend key is needed in the application. Domain verification and saved settings do not establish actual delivery success. Check delivery logs privately during manual testing without copying sign-in links or tokens.

## Manual verification status

The user confirmed these successful checks on 2026-11-06:

- Real email delivery and confirmation.
- Session survives refresh and browser restart.
- Sign-out protects `/account` again.
- A link requested in Safari successfully verifies in Chrome.

These results complete milestone 3A within its limits. They do not verify physical cross-device use or refresh after access-token expiry. Other checklist scenarios below remain regression guidance, not claims of completed manual testing.

## Manual regression checklist

Run `npm run dev`, open `/login`, and perform these checks after completing hosted setup:

| Check | Expected result |
| --- | --- |
| Visit `/account` without a session | Server redirects to configured `/login`; no email/account content is disclosed. |
| Request a link for your confirmed test account | Generic status message; email arrives from the configured sender using the exact custom template. |
| Request with an unknown email, or repeat within the rate limit | Same generic status; no account is created, no account-existence/provider details disclosed. Wait before retrying. |
| Open a fresh email link in a **different browser profile** with no cookies from the requesting browser | GET shows Continue, not a signed-in account; no token verification occurs yet. |
| Reload the confirmation GET before Continue | Still usable; the GET itself has not consumed the token. |
| Click Continue | Explicit POST establishes cookies; 303 leads to `/account`, which shows the server-verified email; address bar contains no token. |
| Open the consumed link again | Continue fails with invalid/expired/already-used guidance; the existing session remains usable by visiting `/account`. |
| Missing, altered, expired link, or invitation-type link | Clear safe error; no token/provider details appear. Request a new Magic Link. |
| Reload `/account` and restart the same browser | Session persists; confirmed by the user. |
| Revisit after access-token expiry | Session refreshes under the hosted session policy; still unverified. |
| Remember email, submit, revisit `/login` | Email prefills in the same browser; localStorage preference holds only the email. Uncheck or Clear removes it. Storage-disabled browsers can still sign in. |
| Sign out | Server action clears the current browser session; `/account` requires sign-in. Other devices remain signed in. Remembered email is a separate preference and stays until cleared. |
| Inspect network response headers privately | Confirmation and user-specific routes are uncached; cookies survive refresh/redirect; no third-party asset requests on confirmation. Never copy credential-bearing headers. |
| Signed in with no league membership | `/account` works; application tables remain inaccessible. No membership is claimed automatically. |

`localhost` on a phone points to that phone, so a laptop's localhost link cannot be opened on a different physical device. Test separate browsers locally; test physical cross-device verification only after an authorized deployment with HTTPS, matching hosted Site URL and redirect allowlist, and matching environment values. Link lifetime, session lifetime, browser cookie policies, and delivery/rate limits are controlled by the hosted project and must be verified there.

## Diagnose a missing login email (development only)

The action calls `signInWithOtp` with `shouldCreateUser: false`, which the installed SDK sends to `/auth/v1/otp`. It does not call `resetPasswordForEmail` (`/auth/v1/recover`). A Supabase `user_recovery_requested` log entry alone does not establish which application method ran or that SMTP delivery was attempted.

The browser always receives generic messaging: the original implementation ignored returned `{ error }` values, and the generic-message helper still catches thrown errors. The action now inspects returned errors and exceptions before they reach that helper, without changing the authentication method or browser response.

To reproduce **once**:

1. Restart `npm run dev` so the diagnostic code is loaded; keep its server terminal visible. Do not print `.env.local`.
2. Wait until the hosted email cooldown has elapsed since the previous attempt (at least a minute, or longer if configured).
3. Open `/login`, enter your existing approved account privately, and click the request button once.
4. Inspect the terminal's `[auth.email_link_request]` entry. It contains only `method`, `stage`, `httpStatus`, redacted `supabaseErrorCode`, redacted error `name`, and redacted original `message`. Compare the attempt's time with Supabase Auth logs and Resend's delivery activity. Do not copy email addresses, tokens, sessions, request bodies, or full confirmation URLs.

`stage=response` captures the actual HTTP response status via a status-only fetch wrapper, plus the SDK error code if supplied; unfamiliar codes are preserved after redaction. A successful response has a null error code; HTTP success confirms Auth accepted the request, not that Resend received it. `stage=exception` records safe exception metadata; `stage=setup` means configuration/client preparation failed. A null status means no HTTP status was observed or supplied by the SDK. Rate limits and delivery errors remain generic in the browser.

The whole error object, stack, response data, request bodies, and sessions are never logged. Only message/name/code strings are inspected; configured sensitive environment values and the submitted email are removed, followed by redaction of URLs, email addresses, labeled credentials/tokens, key/JWT patterns, embedded sensitive fields, and long opaque values. Control characters are removed and output is bounded. The original wording is retained where safe; codes are not filtered through a known-code whitelist. Diagnostics are disabled outside `NODE_ENV=development`. Their mocked tests do not send email or identify the hosted delivery failure; the next single manual attempt supplies that evidence. Do not change auth methods or hosted security settings based solely on the audit event name.

The earlier fixed-summary diagnostic discarded the original provider wording, so it cannot be recovered from that entry. A 500 plus an email-delivery summary alone does not distinguish template rendering, SMTP setup, or another Auth-side failure. After restarting the development server, one new **user-triggered** attempt will expose the redacted original name/message/code; no automatic retry or send is performed by diagnostics.

Template inspection found no syntax issue in the HTML documented above: `.SiteURL` and `.TokenHash` are supported variables, both template actions have balanced braces, and HTML decoding of `&amp;type=email` produces the intended `type=email` query parameter. These properties are checked locally with synthetic values; this is not execution by Supabase's template renderer or proof that the hosted template matches. A hosted parse error (for example a missing dot in a variable reference) needs its actual error text before changing configuration.

## Confirmation POST origin troubleshooting

The 403 message “Open the sign-in link on the configured application and try again.” comes from `handleConfirmation` in `src/lib/auth-confirmation.ts`, before the token is read from the body or verified. The inspected local `NEXT_PUBLIC_SITE_URL` origin was `http://localhost:3000`, matching the observed browser origin. The form posts to the configured `/auth/confirm`; CSP restricts `form-action` to self and does not sandbox the document.

An isolated Chrome test with synthetic localhost forms reproduced the policy conflict: the old header/meta `no-referrer` produced `Origin: null` with `Sec-Fetch-Site: same-origin`. With `strict-origin`, the POST carried its actual origin; its Referer contained only the origin, with neither path nor query. The confirmation header **and** meta tag now use `strict-origin`, and the Next.js auth-route header agrees. No null/missing-Origin exception was introduced. A provided Fetch Metadata header must also indicate `same-origin`; clients without it still need an exact matching Origin. See [referrer policy's effect on Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Referrer-Policy#effect_on_the_origin_header).

In development only, `[auth.confirmation_post]` reports configured origin, sanitized POST Origin, bounded `Sec-Fetch-Site`, and `validation`: `accepted`, `origin_missing`, `origin_null`, `origin_mismatch`, or `fetch_site_mismatch`. It never logs token hashes, query strings, form bodies, cookies, or confirmation URLs. Invalid header values are replaced with markers rather than echoed.

Restart the development server, reopen or fully reload the received confirmation link so the new policy takes effect, and click Continue once. A previously rejected POST never reached token verification, so an otherwise unexpired link can still be used. Expect matching origins, `same-origin`, and `accepted`; successful real verification should then redirect to `/account`. Share only those origin-level diagnostics if it still fails. No email was sent for this browser reproduction, and the synthetic browser test does not establish real Supabase token verification or session persistence.

## Automated evidence and remaining work

`npm test` uses Node's runner and `tsx`. Pure auth tests use synthetic values and in-memory storage; confirmation tests inject a **mock** verifier and email-request tests inject a **mock** sender. They cover GET nonconsumption, explicit POST success/failure, missing/invalid/type-mismatched links, Origin checks, safe redirects, origin-only/no-store headers, remembered-email clearing/blocked storage, and generic send outcomes. They do not send emails, verify real tokens, write real Supabase cookies, or prove browser-session persistence. Real confirmation and persistence are supported by the reported manual checks above; refresh after access-token expiry remains unverified.

Server clients are per request. The Next.js 16 `src/proxy.ts` refreshes sessions using `getClaims` and forwards refreshed cookies to request and response. `/account` uses `getUser` for a fresh server-confirmed user/email and requires email confirmation. No server authorization trusts `getSession`'s embedded user. Subsequent database access must use this user's server client/session; no elevated key is used. See [Supabase SSR guidance](https://supabase.com/docs/guides/auth/server-side/nextjs).

Commissioner invitations, membership claiming, invitation email templates/token types, application-table read policies, and role authorization are milestone 3B. Invitations need their own supported token handling; `type=invite` is intentionally rejected by this Magic Link confirmation endpoint.

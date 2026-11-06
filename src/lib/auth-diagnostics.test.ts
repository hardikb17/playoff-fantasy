import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { reportAuthDiagnostic, sanitizedAuthDiagnostic, statusObservingFetch, redactAuthText, type AuthDiagnostic } from "./auth-diagnostics";
import { LINK_REQUEST_MESSAGE, requestEmailSignIn } from "./auth-flow";

const email = "person@example.invalid";
const token = "SyntheticOpaqueToken01234567890123456789";
const sensitive = `${email} sb_secret_synthetic ${token} https://example.invalid/auth/confirm?token_hash=synthetic Cookie=session_synthetic`;

test("diagnostics retain redacted provider wording and name without copying the error object or stack", () => {
  const entries: AuthDiagnostic[] = [];
  const error = Object.assign(new Error(`Error sending magic link email: template rendering failed ${sensitive}`), {
    name: "AuthApiError", status: 500, code: "unexpected_failure", body: sensitive, session: sensitive,
  });
  reportAuthDiagnostic("development", error, 502, "response", (entry) => entries.push(entry));
  assert.equal(entries[0].httpStatus, 502);
  assert.equal(entries[0].supabaseErrorCode, "unexpected_failure");
  assert.equal(entries[0].name, "AuthApiError");
  assert.match(entries[0].message, /^Error sending magic link email: template rendering failed/);
  assert.deepEqual(Object.keys(entries[0]).sort(), ["method", "stage", "httpStatus", "supabaseErrorCode", "name", "message"].sort());
  assert.doesNotMatch(JSON.stringify(entries), /person@|sb_secret|SyntheticOpaque|https:|session_synthetic|stack|body/);
});

test("unfamiliar provider codes and actual error names/messages remain visible after redaction", () => {
  const diagnostic = sanitizedAuthDiagnostic({
    name: "AuthApiError", code: "unfamiliar_email_v2_template_execution_failure",
    message: 'template: magic_link:1: function "SiteURL" not defined', status: 500,
  }, null, "response");
  assert.equal(diagnostic.supabaseErrorCode, "unfamiliar_email_v2_template_execution_failure");
  assert.equal(diagnostic.message, 'template: magic_link:1: function "SiteURL" not defined');
  assert.equal(diagnostic.name, "AuthApiError");
  assert.equal(diagnostic.httpStatus, 500);
  assert.equal(sanitizedAuthDiagnostic({ message: "Error sending recovery email" }, 500, "response").message, "Error sending recovery email");
});

test("redaction covers supplied secrets, addresses, URLs, credentials, labeled secrets, bodies and control characters", () => {
  const known = "shortPrivateValue";
  const text = `SMTP failure ${known} person%40example.invalid https%3A%2F%2Fexample.invalid%2Fauth%3Ftoken%3Dprivate\npassword="short secret" api_key=short-key smtp_user=private-user Bearer private-bearer re_synthetic\n${token}\nrequest_body={"arbitrary":"private-body"}`;
  const redacted = redactAuthText(text, [known]);
  assert.match(redacted, /SMTP failure/);
  for (const hidden of [known, "person", "example.invalid", "short secret", "short-key", "private-user", "private-bearer", "re_synthetic", token, "private-body", "\n"]) {
    assert.ok(!redacted.includes(hidden), `Sensitive fixture value leaked: ${hidden}`);
  }
  const object = redactAuthText('{"session":{"access_token":"private-nested-value"}}');
  assert.ok(!object.includes("private-nested-value"));
  // Error name and code use the same redactor, not a bypass around it.
  const diagnostic = sanitizedAuthDiagnostic({ name: known, code: known, message: known }, null, "exception", [known]);
  assert.ok(!JSON.stringify(diagnostic).includes(known));
  assert.ok(!redactAuthText('x'.repeat(700) + ' password="private-tail"').includes("private-tail"));
});

test("success, missing status, setup failures and absent error codes are represented honestly", () => {
  assert.equal(sanitizedAuthDiagnostic({ code: "over_email_send_rate_limit", status: 429 }, null, "response").httpStatus, 429);
  assert.match(sanitizedAuthDiagnostic(null, 200, "response").message, /delivery is not confirmed/);
  for (const status of [NaN, Infinity, 99, 600, 200.5]) {
    assert.equal(sanitizedAuthDiagnostic(new Error("failure"), status, "exception").httpStatus, null);
  }
  const diagnostic = sanitizedAuthDiagnostic(new Error("Application origin is not configured."), null, "setup");
  assert.equal(diagnostic.message, "Application origin is not configured.");
  assert.equal(diagnostic.name, "Error");
  assert.equal(diagnostic.supabaseErrorCode, null);
});

test("diagnostics never emit in production, test, or an unset environment", () => {
  for (const environment of ["production", "test", undefined]) {
    reportAuthDiagnostic(environment, new Error(sensitive), 500, "response", () => assert.fail("must not log"));
  }
});

test("mocked fetch observes response status without consuming its body or logging request data", async () => {
  const observed: number[] = [];
  const response = new Response(sensitive, { status: 429 });
  const mockFetch: typeof fetch = async (_input, init) => {
    assert.equal(init?.cache, "no-store"); return response;
  };
  const result = await statusObservingFetch(mockFetch, (status) => observed.push(status))(
    "https://example.invalid/auth/v1/otp", { method: "POST", body: sensitive });
  assert.equal(result, response);
  assert.equal(result.bodyUsed, false);
  assert.deepEqual(observed, [429]);
});

test("diagnostics preserve generic browser messaging for returned and thrown provider errors", async () => {
  const entries: AuthDiagnostic[] = [];
  for (const thrown of [false, true]) {
    const state = await requestEmailSignIn("synthetic@example.invalid", async () => {
      const error = { code: "new_provider_error", name: "AuthApiError", status: 500, message: sensitive };
      reportAuthDiagnostic("development", error, 500, thrown ? "exception" : "response", (entry) => entries.push(entry));
      if (thrown) throw error;
      return { error };
    });
    assert.deepEqual(state, { message: LINK_REQUEST_MESSAGE });
  }
  assert.equal(entries.length, 2);
  assert.ok(entries.every((entry) => !JSON.stringify(entry).includes(sensitive)));
});

test("documented template uses only supported variables and an HTML-escaped query separator", () => {
  const doc = readFileSync("docs/AUTH_SETUP.md", "utf8");
  const html = doc.match(/```html\n([\s\S]*?)\n```/)![1];
  assert.deepEqual([...html.matchAll(/{{([\s\S]*?)}}/g)].map((match) => match[1].trim()), [".SiteURL", ".TokenHash"]);
  const href = html.match(/href="([^"]+)"/)![1]
    .replace("{{ .SiteURL }}", "https://synthetic.example.invalid")
    .replace("{{ .TokenHash }}", "synthetic-hash")
    .replaceAll("&amp;", "&");
  const url = new URL(href);
  assert.equal(url.pathname, "/auth/confirm");
  assert.equal(url.searchParams.get("token_hash"), "synthetic-hash");
  assert.equal(url.searchParams.get("type"), "email");
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { confirmationPostValidation, handleConfirmation } from "./auth-confirmation";

const origin = "http://localhost:3000";
const hash = "synthetic_token_hash_1234567890";
function post(body: URLSearchParams, extra: Record<string, string> = {}) {
  return new Request(`${origin}/auth/confirm`, { method: "POST", headers: { Origin: origin, ...extra }, body });
}
function values() { return new URLSearchParams({ token_hash: hash, type: "email", next: "/account" }); }
function privateResponse(response: Response, referrerPolicy = "no-referrer") {
  assert.match(response.headers.get("cache-control")!, /private.*no-store/);
  assert.equal(response.headers.get("referrer-policy"), referrerPolicy);
}

test("confirmation GET displays Continue without verifying or using a requesting-browser cookie", async () => {
  let calls = 0;
  const response = await handleConfirmation(new Request(`${origin}/auth/confirm?${values()}`), {
    origin, async verify() { calls++; return true; },
  });
  assert.equal(calls, 0);
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /method="post"/);
  assert.match(html, /Continue/);
  assert.match(html, /action="http:\/\/localhost:3000\/auth\/confirm"/);
  assert.doesNotMatch(html, /<script|<img|<link|<iframe|autofocus|onload=/i);
  assert.match(response.headers.get("content-security-policy")!, /default-src 'none'/);
  privateResponse(response, "strict-origin");
});

test("missing/malformed/duplicate token or unsupported type never calls verify", async () => {
  let calls = 0;
  const deps = { origin, async verify() { calls++; return true; } };
  for (const query of ["", "?type=email", "?token_hash=bad&type=email", `?token_hash=${hash}&type=invite`, `?token_hash=${hash}&token_hash=${hash}&type=email`, `?token_hash=${hash}&type=email&type=email`, "?token_hash=%22%3E%3Cscript%3E&type=email"]) {
    const response = await handleConfirmation(new Request(`${origin}/auth/confirm${query}`), deps);
    assert.equal(response.status, 400);
    assert.match(await response.text(), /missing, invalid, expired, or already used/);
    privateResponse(response, "strict-origin");
  }
  for (const body of [new URLSearchParams(), new URLSearchParams({ token_hash: hash, type: "invite" }), new URLSearchParams({ token_hash: "bad", type: "email" })]) {
    const response = await handleConfirmation(post(body), deps);
    assert.equal(response.status, 303);
    assert.equal(response.headers.get("location"), `${origin}/login?reason=link_invalid`);
  }
  assert.equal(calls, 0);
});

test("mocked successful POST verifies the hash, sets no verifier requirement, strips token from redirect", async () => {
  let seen: string | undefined;
  const body = values(); body.set("next", "https://evil.example/account");
  const response = await handleConfirmation(post(body), { origin, async verify(token) { seen = token; return true; } });
  assert.equal(seen, hash);
  assert.equal(response.status, 303);
  assert.equal(response.headers.get("location"), `${origin}/account`);
  assert.doesNotMatch(response.headers.get("location")!, /token|evil/);
  privateResponse(response);
});

test("mocked invalid/expired/used results and provider exceptions redirect without token or private details", async () => {
  for (const verify of [async () => false, async () => { throw new Error("secret provider error " + hash); }]) {
    const response = await handleConfirmation(post(values()), { origin, verify });
    assert.equal(response.status, 303);
    assert.match(response.headers.get("location")!, /\/login\?reason=(link_invalid|unavailable)$/);
    assert.doesNotMatch(response.headers.get("location")!, new RegExp(hash));
    assert.equal(await response.text(), "");
    privateResponse(response);
  }
});

test("cross-origin or missing-origin POST fails before verify; arbitrary Host is not a redirect origin", async () => {
  let calls = 0;
  for (const value of ["https://evil.example", "null", ""]) {
    const response = await handleConfirmation(post(values(), { Origin: value, Host: "evil.example" }), { origin, async verify() { calls++; return true; } });
    assert.equal(response.status, 403); privateResponse(response);
  }
  assert.equal(calls, 0);
  const response = await handleConfirmation(post(values(), { Host: "evil.example" }), { origin, async verify() { return true; } });
  assert.equal(response.headers.get("location"), `${origin}/account`);
});

test("malformed form data and unsupported methods fail without verification", async () => {
  let calls = 0;
  const deps = { origin, async verify() { calls++; return true; } };
  const malformed = await handleConfirmation(new Request(`${origin}/auth/confirm`, { method: "POST", headers: { Origin: origin, "Content-Type": "application/json" }, body: "{}" }), deps);
  assert.equal(malformed.headers.get("location"), `${origin}/login?reason=link_invalid`);
  assert.equal((await handleConfirmation(new Request(`${origin}/auth/confirm`, { method: "PUT" }), deps)).status, 405);
  assert.equal(calls, 0);
});

test("regression: form document uses strict-origin in both header and meta, retaining exact-Origin validation", async () => {
  const response = await handleConfirmation(new Request(`${origin}/auth/confirm?${values()}`), { origin, async verify() { assert.fail("GET must not verify"); } });
  assert.equal(response.headers.get("referrer-policy"), "strict-origin");
  assert.match(await response.text(), /<meta name="referrer" content="strict-origin">/);
  let calls = 0;
  const deps = { origin, async verify() { calls++; return true; } };
  assert.equal((await handleConfirmation(post(values(), { Origin: "null", "Sec-Fetch-Site": "same-origin" }), deps)).status, 403);
  const accepted = await handleConfirmation(post(values(), { "Sec-Fetch-Site": "same-origin" }), deps);
  assert.equal(accepted.status, 303);
  assert.equal(accepted.headers.get("location"), `${origin}/account`);
  assert.equal(calls, 1);
});

test("confirmation diagnostics report exact rejection reasons without leaking URLs, bodies, or arbitrary headers", () => {
  for (const [header, reason] of [["null", "origin_null"], ["", "origin_missing"], ["https://elsewhere.example", "origin_mismatch"]]) {
    const diagnostic = confirmationPostValidation(post(values(), { Origin: header, "Sec-Fetch-Site": "same-origin" }), origin);
    assert.equal(diagnostic.configuredApplicationOrigin, origin);
    assert.equal(diagnostic.validation, reason);
  }
  const invalid = confirmationPostValidation(post(values(), { Origin: "http://localhost:3000/auth/confirm?token_hash=DO_NOT_LOG", "Sec-Fetch-Site": "DO_NOT_LOG" }), origin);
  assert.equal(invalid.postOriginHeader, "[invalid-origin]");
  assert.equal(invalid.secFetchSite, "[invalid-value]");
  assert.ok(!JSON.stringify(invalid).includes("DO_NOT_LOG"));
  const missing = new Request(`${origin}/auth/confirm`, { method: "POST" });
  assert.equal(confirmationPostValidation(missing, origin).validation, "origin_missing");
});

test("conflicting Fetch Metadata rejects before token verification, even with a claimed matching Origin", async () => {
  let calls = 0;
  for (const site of ["cross-site", "same-site", "none", "invalid"]) {
    const response = await handleConfirmation(post(values(), { "Sec-Fetch-Site": site }), { origin, async verify() { calls++; return true; } });
    assert.equal(response.status, 403);
  }
  assert.equal(calls, 0);
});

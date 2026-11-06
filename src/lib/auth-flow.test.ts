import assert from "node:assert/strict";
import { test } from "node:test";
import { applicationOrigin, emailLinkOptions, LINK_REQUEST_MESSAGE, normalizedEmail, postLoginPath, requestEmailSignIn } from "./auth-flow";
import { readRememberedEmail, REMEMBERED_EMAIL_KEY, saveRememberedEmail } from "./remembered-email";

test("only the approved post-login path is accepted, with no URL normalization tricks", () => {
  assert.equal(postLoginPath("/account"), "/account");
  for (const value of ["https://evil.example", "//evil.example", "/\\evil.example", "%2f%2fevil.example", "/account/../evil", "/account?next=https://evil.example", "/auth/confirm", null, undefined, ["/account"], "\r\nLocation: https://evil.example"]) {
    assert.equal(postLoginPath(value), "/account");
  }
});

test("application origin is explicitly configured; only HTTPS and loopback HTTP are allowed", () => {
  assert.equal(applicationOrigin("http://localhost:3000"), "http://localhost:3000");
  assert.equal(applicationOrigin("https://playoffs.example/"), "https://playoffs.example");
  for (const value of [undefined, "", "//evil.example", "http://evil.example", "https://user:password@example.com", "https://example.com/path", "https://example.com/?next=evil", "https://example.com/#hash", "javascript:alert(1)"]) {
    assert.throws(() => applicationOrigin(value));
  }
});

test("email input is validated before a mocked send; account/rate/provider errors have identical messaging", async () => {
  let calls = 0;
  const invalid = await requestEmailSignIn("not-an-email", async () => { calls++; });
  assert.equal(invalid.message, "Enter a valid email address.");
  assert.equal(calls, 0);
  for (const providerResult of [null, { error: { code: "user_not_found" } }, { error: { status: 429 } }, { error: { message: "SMTP provider detail" } }]) {
    const result = await requestEmailSignIn("  synthetic@example.invalid  ", async (email) => {
      assert.equal(email, "synthetic@example.invalid"); return providerResult;
    });
    assert.deepEqual(result, { message: LINK_REQUEST_MESSAGE });
  }
  assert.deepEqual(await requestEmailSignIn("synthetic@example.invalid", async () => { throw new Error("private detail"); }), { message: LINK_REQUEST_MESSAGE });
  for (const value of [null, undefined, "", "a@b", "a b@example.invalid", "x".repeat(255) + "@example.invalid"]) {
    assert.equal(normalizedEmail(value), null);
  }
});

function fakeStorage() {
  const data = new Map<string, string>();
  return { data, getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => { data.set(key, value); },
    removeItem: (key: string) => { data.delete(key); } };
}

test("remembered-email preference stores only the email and supports opt-out and clear", () => {
  const storage = fakeStorage();
  assert.equal(readRememberedEmail(storage), "");
  saveRememberedEmail(storage, " synthetic@example.invalid ", true);
  assert.deepEqual([...storage.data], [[REMEMBERED_EMAIL_KEY, "synthetic@example.invalid"]]);
  assert.equal(readRememberedEmail(storage), "synthetic@example.invalid");
  saveRememberedEmail(storage, "synthetic@example.invalid", false);
  assert.equal(readRememberedEmail(storage), "");
  saveRememberedEmail(storage, "synthetic@example.invalid", true);
  saveRememberedEmail(storage, "", false);
  assert.equal(storage.data.size, 0);
});

test("remembered-email rejects malformed saved values and tolerates blocked browser storage", () => {
  const storage = fakeStorage();
  storage.data.set(REMEMBERED_EMAIL_KEY, '{"access_token":"not-a-session"}');
  assert.equal(readRememberedEmail(storage), "");
  saveRememberedEmail(storage, "bad email", true);
  assert.equal(storage.data.size, 0);
  const blocked = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); }, removeItem() { throw new Error("blocked"); } };
  assert.equal(readRememberedEmail(blocked), "");
  assert.doesNotThrow(() => saveRememberedEmail(blocked, "synthetic@example.invalid", true));
  assert.doesNotThrow(() => saveRememberedEmail(blocked, "", false));
});

test("email-link request options disable signup and use only the configured confirmation origin", () => {
  assert.deepEqual(emailLinkOptions("http://localhost:3000"), {
    shouldCreateUser: false,
    emailRedirectTo: "http://localhost:3000/auth/confirm",
  });
  assert.throws(() => emailLinkOptions("https://example.com/attacker-path"));
});

import { applicationOrigin, AUTH_MESSAGES, postLoginPath } from "./auth-flow";

export const PRIVATE_AUTH_HEADERS = {
  "Cache-Control": "private, no-store, max-age=0, must-revalidate",
  Expires: "0",
  Pragma: "no-cache",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
};

// no-referrer makes navigation-mode form POSTs send Origin: null.
// strict-origin preserves Origin while excluding referrer paths/query strings.
export const CONFIRMATION_REFERRER_POLICY = "strict-origin";

export interface ConfirmationPostDiagnostic {
  configuredApplicationOrigin: string;
  postOriginHeader: string | null;
  secFetchSite: string | null;
  validation: "accepted" | "origin_missing" | "origin_null" | "origin_mismatch" | "fetch_site_mismatch";
}

export function confirmationPostValidation(request: Request, origin: string): ConfirmationPostDiagnostic {
  const rawOrigin = request.headers.get("origin");
  const rawSite = request.headers.get("sec-fetch-site");
  let safeOrigin: string | null = rawOrigin === "null" ? "null" : null;
  if (rawOrigin !== null && rawOrigin !== "null") {
    try {
      const parsed = new URL(rawOrigin);
      safeOrigin = ["http:", "https:"].includes(parsed.protocol) && parsed.origin === rawOrigin
        ? parsed.origin : "[invalid-origin]";
    } catch { safeOrigin = "[invalid-origin]"; }
  }
  const site = rawSite === null ? null : ["same-origin", "same-site", "cross-site", "none"].includes(rawSite)
    ? rawSite : "[invalid-value]";
  const validation = rawOrigin === null || rawOrigin === "" ? "origin_missing"
    : rawOrigin === "null" ? "origin_null"
    : rawOrigin !== origin ? "origin_mismatch"
    : rawSite !== null && rawSite !== "same-origin" ? "fetch_site_mismatch" : "accepted";
  return { configuredApplicationOrigin: origin, postOriginHeader: safeOrigin, secFetchSite: site, validation };
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function validToken(value: unknown): value is string {
  // Opaque token hash, not an OTP code. Do not assume a particular hash length.
  return typeof value === "string" && /^[A-Za-z0-9_-]{20,512}$/.test(value);
}

export function confirmationPage(token: string | null, origin: string): Response {
  const content = token
    ? `<h1>Finish signing in</h1><p>Continue only if you requested this sign-in link.</p><form method="post" action="${escapeHtml(origin)}/auth/confirm"><input type="hidden" name="token_hash" value="${escapeHtml(token)}"><input type="hidden" name="type" value="email"><input type="hidden" name="next" value="/account"><button type="submit">Continue</button></form>`
    : `<h1>Sign-in link unavailable</h1><p>${AUTH_MESSAGES.link_invalid}</p><p><a href="${escapeHtml(origin)}/login">Request a new link</a> · <a href="${escapeHtml(origin)}/account">Account</a></p>`;
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin"><title>Confirm sign-in | Playoff Fantasy</title><style>body{font:1rem/1.6 system-ui,sans-serif;margin:0;background:#f4f5f7;color:#16202c}main{max-width:28rem;margin:10vh auto;padding:2rem;background:white;border-radius:1rem}button{font:inherit;background:#172f50;color:white;border:0;border-radius:.5rem;padding:.7rem 1.4rem;cursor:pointer}a{color:#172f50}@media(max-width:32rem){main{margin:2rem 1rem}}</style></head><body><main>${content}</main></body></html>`, {
    status: token ? 200 : 400,
    headers: { ...PRIVATE_AUTH_HEADERS, "Referrer-Policy": CONFIRMATION_REFERRER_POLICY, "Content-Type": "text/html; charset=utf-8" },
  });
}

interface ConfirmationDependencies {
  origin: string;
  verify: (tokenHash: string) => Promise<boolean>;
  onPostValidation?: (diagnostic: ConfirmationPostDiagnostic) => void;
}

/** GET never verifies, reads sessions, or loads third-party assets. */
export async function handleConfirmation(request: Request, deps: ConfirmationDependencies): Promise<Response> {
  const origin = applicationOrigin(deps.origin);
  if (request.method === "GET" || request.method === "HEAD") {
    const query = new URL(request.url).searchParams;
    const token = query.get("token_hash");
    return confirmationPage(query.getAll("token_hash").length === 1 && query.getAll("type").length === 1 && query.get("type") === "email" && validToken(token) ? token : null, origin);
  }
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { ...PRIVATE_AUTH_HEADERS, Allow: "GET, HEAD, POST" } });
  // Prevent login CSRF: POSTs must originate from the configured app, never Host.
  const validation = confirmationPostValidation(request, origin);
  deps.onPostValidation?.(validation);
  if (validation.validation !== "accepted") {
    return new Response("Open the sign-in link on the configured application and try again.", { status: 403, headers: PRIVATE_AUTH_HEADERS });
  }
  function outcome(path: string) {
    return new Response(null, { status: 303, headers: { ...PRIVATE_AUTH_HEADERS, Location: new URL(path, origin).href } });
  }
  let body: FormData;
  try { body = await request.formData(); } catch { return outcome("/login?reason=link_invalid"); }
  const token = body.get("token_hash");
  if (body.getAll("token_hash").length !== 1 || body.getAll("type").length !== 1 || body.get("type") !== "email" || !validToken(token)) {
    return outcome("/login?reason=link_invalid");
  }
  try {
    if (await deps.verify(token)) return outcome(postLoginPath(body.get("next")));
    return outcome("/login?reason=link_invalid");
  } catch {
    return outcome("/login?reason=unavailable");
  }
}

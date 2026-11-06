/** Only explicitly approved destinations; never resolve user input against a host. */
export function postLoginPath(value: unknown): "/account" {
  // There is currently one approved destination. Extend the allowlist explicitly.
  return value === "/account" ? value : "/account";
}

export function applicationOrigin(value: string | undefined): string {
  if (!value) throw new Error("Application origin is not configured.");
  const url = new URL(value);
  if (url.username || url.password || url.pathname !== "/" || url.search || url.hash ||
    (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)))) {
    throw new Error("Application origin must be an HTTPS origin or local HTTP origin.");
  }
  return url.origin;
}

export function normalizedEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim();
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

export interface LoginState { message: string; }
export const LINK_REQUEST_MESSAGE = "If sign-in is available for this email, a link will arrive shortly. If it does not arrive, wait a minute before trying again; sending may be temporarily unavailable.";

/** Provider errors, including unknown accounts and rate limits, share one response. */
export async function requestEmailSignIn(
  email: unknown,
  send: (email: string) => Promise<unknown>,
): Promise<LoginState> {
  const valid = normalizedEmail(email);
  if (!valid) return { message: "Enter a valid email address." };
  try { await send(valid); } catch { /* Deliberately do not expose or log provider errors. */ }
  return { message: LINK_REQUEST_MESSAGE };
}

export const AUTH_MESSAGES: Record<string, string> = {
  link_invalid: "This sign-in link is missing, invalid, expired, or already used. Request a fresh link, or open Account if you are already signed in.",
  unavailable: "Sign-in is temporarily unavailable. Please try again later.",
  signed_out: "You have signed out on this browser.",
  signout_failed: "Sign-out could not be completed. Please try again.",
};

export function emailLinkOptions(origin: string) {
  return {
    shouldCreateUser: false as const,
    emailRedirectTo: `${applicationOrigin(origin)}/auth/confirm`,
  };
}

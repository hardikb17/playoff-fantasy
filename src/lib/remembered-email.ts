import { normalizedEmail } from "./auth-flow";

export const REMEMBERED_EMAIL_KEY = "playoff-fantasy:remembered-email";
type EmailStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;

export function readRememberedEmail(storage: EmailStorage): string {
  try { return normalizedEmail(storage.getItem(REMEMBERED_EMAIL_KEY)) ?? ""; }
  catch { return ""; }
}

/** This preference contains only an email; auth credentials use Supabase cookies. */
export function saveRememberedEmail(storage: EmailStorage, email: string, remember: boolean): void {
  try {
    const valid = normalizedEmail(email);
    if (remember && valid) storage.setItem(REMEMBERED_EMAIL_KEY, valid);
    else storage.removeItem(REMEMBERED_EMAIL_KEY);
  } catch { /* Storage may be disabled; sign-in must still work. */ }
}

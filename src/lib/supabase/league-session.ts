import "server-only";
import { redirect } from "next/navigation";
import { applicationOrigin } from "../auth-flow";
import { createServerSupabase } from "./server";

/** Return the user's own cookie-bound client, never an elevated client. */
export async function requireLeagueSession() {
  const origin = applicationOrigin(process.env.NEXT_PUBLIC_SITE_URL);
  const supabase = await createServerSupabase();
  let verified = false;
  try {
    const { data, error } = await supabase.auth.getUser();
    verified = !error && Boolean(data.user?.email_confirmed_at);
  } catch { /* Fail closed; do not log session/provider data. */ }
  if (!verified) redirect(`${origin}/login`);
  return supabase;
}

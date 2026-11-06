"use server";

import { redirect } from "next/navigation";
import { applicationOrigin } from "@/lib/auth-flow";
import { createServerSupabase } from "@/lib/supabase/server";

export async function signOut() {
  const origin = applicationOrigin(process.env.NEXT_PUBLIC_SITE_URL);
  let failed = false;
  try {
    const supabase = await createServerSupabase({ writable: true });
    // Authenticated network lookup, never getSession's embedded user.
    await supabase.auth.getUser();
    const { error } = await supabase.auth.signOut({ scope: "local" });
    failed = Boolean(error);
  } catch { failed = true; }
  redirect(`${origin}/login?reason=${failed ? "signout_failed" : "signed_out"}`);
}

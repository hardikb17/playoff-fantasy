"use server";

import { createClient } from "@supabase/supabase-js";
import { applicationOrigin, emailLinkOptions, requestEmailSignIn, type LoginState } from "@/lib/auth-flow";
import { reportAuthDiagnostic, statusObservingFetch, type AuthDiagnostic } from "@/lib/auth-diagnostics";
import { supabaseConfig } from "@/lib/supabase/config";

export async function requestLink(_previous: LoginState, form: FormData): Promise<LoginState> {
  let httpStatus: number | null = null;
  // Values stay in memory solely for redaction; never log the environment or form.
  const sensitiveValues = Object.entries(process.env)
    .filter(([name, value]) => /KEY|TOKEN|SECRET|PASSWORD|SMTP|SUPABASE_URL|SITE_URL/i.test(name) && value && value.length >= 6)
    .map(([, value]) => value!);
  const submittedEmail = form.get("email");
  if (typeof submittedEmail === "string") sensitiveValues.push(submittedEmail.trim());
  const diagnose = (error: unknown, stage: AuthDiagnostic["stage"]) => {
    reportAuthDiagnostic(process.env.NODE_ENV, error, httpStatus, stage, (diagnostic) => {
      console.info("[auth.email_link_request]", diagnostic);
    }, sensitiveValues);
  };
  try {
    const origin = applicationOrigin(process.env.NEXT_PUBLIC_SITE_URL);
    const { url, key } = supabaseConfig();
    // Sessionless sender: no requesting-browser verifier or auth cookie is needed.
    const supabase = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { fetch: statusObservingFetch(fetch, (status) => { httpStatus = status; }) },
    });
    return await requestEmailSignIn(form.get("email"), async (email) => {
      try {
        const result = await supabase.auth.signInWithOtp({ email, options: emailLinkOptions(origin) });
        diagnose(result.error, "response");
        return result;
      } catch (error) {
        diagnose(error, "exception");
        throw error; // The generic-message helper catches this; no error reaches the browser.
      }
    });
  } catch (error) {
    diagnose(error, "setup");
    return { message: "Sign-in is temporarily unavailable. Please try again later." };
  }
}

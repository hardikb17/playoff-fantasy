import { handleConfirmation, PRIVATE_AUTH_HEADERS } from "@/lib/auth-confirmation";
import { createServerSupabase } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

async function handle(request: Request) {
  try {
    return await handleConfirmation(request, {
      origin: process.env.NEXT_PUBLIC_SITE_URL ?? "",
      onPostValidation(diagnostic) {
        if (process.env.NODE_ENV === "development") {
          console.info("[auth.confirmation_post]", diagnostic);
        }
      },
      async verify(tokenHash) {
        const supabase = await createServerSupabase({ writable: true });
        const { data, error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "email" });
        return !error && Boolean(data.session && data.user);
      },
    });
  } catch {
    return new Response("Sign-in is temporarily unavailable. Please try again later.", { status: 503, headers: PRIVATE_AUTH_HEADERS });
  }
}

export const GET = handle;
export const POST = handle;

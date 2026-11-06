import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { authCookieOptions, supabaseConfig } from "./lib/supabase/config";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  // Auth pages stay private even when configuration/network is unavailable.
  const protect = () => {
    response.headers.set("Cache-Control", "private, no-store, max-age=0, must-revalidate");
    response.headers.set("Referrer-Policy", "no-referrer");
    response.headers.set("Expires", "0");
    response.headers.set("Pragma", "no-cache");
    return response;
  };
  try {
    const { url, key } = supabaseConfig();
    const supabase = createServerClient(url, key, {
      cookieOptions: authCookieOptions(),
      global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(values, headers) {
          values.forEach(({ name, value }) => request.cookies.set(name, value));
          const priorCookies = response.cookies.getAll();
          response = NextResponse.next({ request });
          priorCookies.forEach((cookie) => response.cookies.set(cookie));
          Object.entries(headers).forEach(([name, value]) => response.headers.set(name, value));
          values.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        },
      },
    });
    await supabase.auth.getClaims();
  } catch { /* Pages verify identity independently and fail closed. Never log auth data. */ }
  return protect();
}

export const config = { matcher: ["/login", "/account/:path*"] };

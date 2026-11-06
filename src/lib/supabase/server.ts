import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { authCookieOptions, supabaseConfig } from "./config";

export async function createServerSupabase({ writable = false }: { writable?: boolean } = {}) {
  const store = await cookies();
  const { url, key } = supabaseConfig();
  return createServerClient(url, key, {
    cookieOptions: authCookieOptions(),
    global: { fetch: (input, init) => fetch(input, { ...init, cache: "no-store" }) },
    cookies: {
      getAll: () => store.getAll(),
      setAll(values) {
        try { values.forEach(({ name, value, options }) => store.set(name, value, options)); }
        catch {
          if (writable) throw new Error("Could not persist authentication cookies.");
          // Server Components cannot set cookies. Proxy refreshes them first.
          // Route Handlers and Server Actions have a writable cookie store.
        }
      },
    },
  });
}

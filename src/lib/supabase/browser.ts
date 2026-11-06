"use client";

import { createBrowserClient } from "@supabase/ssr";
import { authCookieOptions, supabaseConfig } from "./config";

export function createBrowserSupabase() {
  const { url, key } = supabaseConfig();
  return createBrowserClient(url, key, { cookieOptions: authCookieOptions() });
}

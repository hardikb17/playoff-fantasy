import { applicationOrigin } from "../auth-flow";

export function supabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key?.startsWith("sb_publishable_")) {
    throw new Error("Supabase public configuration is missing or invalid.");
  }
  const parsed = new URL(url);
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== "/") {
    throw new Error("A hosted development Supabase URL is required.");
  }
  return { url: parsed.origin, key };
}

export function authCookieOptions() {
  return {
    path: "/",
    sameSite: "lax" as const,
    secure: applicationOrigin(process.env.NEXT_PUBLIC_SITE_URL).startsWith("https://"),
  };
}

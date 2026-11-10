import Link from "next/link";
import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { applicationOrigin } from "@/lib/auth-flow";
import { createServerSupabase } from "@/lib/supabase/server";
import { signOut } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Account | Playoff Fantasy" };

export default async function AccountPage() {
  let origin: string;
  try { origin = applicationOrigin(process.env.NEXT_PUBLIC_SITE_URL); }
  catch { return <main className="p-8">Sign-in is temporarily unavailable. Please try again later.</main>; }
  let user: User | null = null;
  try {
    const supabase = await createServerSupabase();
    const result = await supabase.auth.getUser();
    if (!result.error && result.data.user?.email_confirmed_at) user = result.data.user;
  } catch { /* Fail closed without logging credentials or provider details. */ }
  if (!user) redirect(`${origin}/login`);
  return (
    <main className="flex flex-1 items-center justify-center bg-slate-100 px-4 py-12 text-slate-950">
      <section className="w-full max-w-md space-y-5 rounded-2xl bg-white p-8 shadow-sm">
        <h1 className="text-3xl font-bold">Your account</h1>
        <p className="break-words">Signed in as <strong>{user.email}</strong></p>
        <p className="text-sm leading-6 text-slate-600">Your identity is verified. League access requires a separate approved membership.</p>
        <Link prefetch={false} href="/leagues" className="inline-block underline underline-offset-4">My leagues</Link>
        <form action={signOut}><button className="rounded-lg bg-slate-900 px-5 py-3 font-semibold text-white">Sign out on this browser</button></form>
      </section>
    </main>
  );
}

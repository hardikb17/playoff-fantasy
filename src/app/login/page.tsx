import { AUTH_MESSAGES } from "@/lib/auth-flow";
import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";
export const metadata = { title: "Sign in | Playoff Fantasy" };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ reason?: string }> }) {
  const { reason } = await searchParams;
  const message = typeof reason === "string" && Object.hasOwn(AUTH_MESSAGES, reason) ? AUTH_MESSAGES[reason] : "";
  return (
    <main className="flex flex-1 items-center justify-center bg-slate-100 px-4 py-12 text-slate-950">
      <section className="w-full max-w-md rounded-2xl bg-white p-6 shadow-sm sm:p-9">
        <p className="mb-3 text-xs font-semibold uppercase tracking-widest text-slate-600">2026 NFL season · Playoffs 2027</p>
        <h1 className="mb-3 text-3xl font-bold">Sign in to Playoff Fantasy</h1>
        <p className="mb-7 text-sm leading-6 text-slate-600">Use the email approved for your account. We will send a single-use link. No password needed.</p>
        <LoginForm initialMessage={message} />
        <p className="mt-6 text-xs leading-5 text-slate-600">Signing in verifies your identity. League membership is managed separately.</p>
        <a href="/account" className="mt-4 inline-block text-sm underline">Already signed in? Open Account</a>
      </section>
    </main>
  );
}

import Link from "next/link";
export default function LeaguesLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen bg-slate-100 px-4 py-8 text-slate-950 sm:py-12">
      <div className="mx-auto max-w-3xl">
        <nav aria-label="Account navigation" className="mb-6 flex gap-5 text-sm underline underline-offset-4">
          <Link prefetch={false} href="/leagues">My leagues</Link><Link prefetch={false} href="/account">Account</Link>
        </nav>
        {children}
      </div>
    </main>
  );
}

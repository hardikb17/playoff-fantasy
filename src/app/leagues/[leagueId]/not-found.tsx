import Link from "next/link";
export default function LeagueNotFound() {
  return <section className="rounded-2xl bg-white p-8"><h1 className="mb-3 text-2xl font-bold">League not found</h1><p>This league is unavailable.</p><Link prefetch={false} href="/leagues" className="mt-4 inline-block underline">Back to my leagues</Link></section>;
}

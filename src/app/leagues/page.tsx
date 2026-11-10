import Link from "next/link";
import { LEAGUE_COLUMNS, seasonLabel, type LeagueSummary } from "@/lib/league-overview";
import { requireLeagueSession } from "@/lib/supabase/league-session";

export const dynamic = "force-dynamic";
export const metadata = { title: "My leagues | Playoff Fantasy" };

export default async function LeaguesPage() {
  const supabase = await requireLeagueSession();
  const { data, error } = await supabase.from("leagues").select(LEAGUE_COLUMNS).order("name").returns<LeagueSummary[]>();
  return (
    <section className="rounded-2xl bg-white p-6 shadow-sm sm:p-9">
      <h1 className="mb-5 text-3xl font-bold">My leagues</h1>
      {error || !data ? <p role="alert">Leagues are temporarily unavailable. Please try again later.</p> :
        data.length === 0 ? <p>You have no active league memberships. Signing in does not automatically join a league.</p> :
          <ul className="space-y-4">{data.map((league) => (
            <li key={league.id} className="rounded-lg border border-slate-200 p-4">
              <Link prefetch={false} href={`/leagues/${league.id}`} className="text-lg font-semibold underline underline-offset-4">{league.name}</Link>
              <p className="mt-2 text-sm text-slate-600">{seasonLabel(league.season_year)}</p>
              <p className="text-sm text-slate-600">{league.manager_count} managers · {league.draft_rounds} rounds</p>
            </li>
          ))}</ul>}
    </section>
  );
}

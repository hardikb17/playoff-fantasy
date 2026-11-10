import { notFound } from "next/navigation";
import { isLeagueId, LEAGUE_COLUMNS, MANAGER_COLUMNS, SCORING_COLUMNS, scoringRows, seasonLabel,
  type LeagueSummary, type LeagueManager, type LeagueScoringVersion } from "@/lib/league-overview";
import { requireLeagueSession } from "@/lib/supabase/league-session";

export const dynamic = "force-dynamic";
export const metadata = { title: "League | Playoff Fantasy" };

export default async function LeaguePage({ params }: { params: Promise<{ leagueId: string }> }) {
  const supabase = await requireLeagueSession();
  const { leagueId } = await params;
  if (!isLeagueId(leagueId)) notFound();
  // RLS determines visibility. A guessed/unauthorized UUID returns no row.
  const { data: league, error } = await supabase.from("leagues").select(LEAGUE_COLUMNS)
    .eq("id", leagueId).maybeSingle<LeagueSummary>();
  if (error || !league) notFound();
  const [managers, scoring] = await Promise.all([
    supabase.from("league_memberships").select(MANAGER_COLUMNS).eq("league_id", leagueId).order("display_name").returns<LeagueManager[]>(),
    supabase.from("league_scoring_versions").select(SCORING_COLUMNS).eq("league_id", leagueId).order("version").returns<LeagueScoringVersion[]>(),
  ]);
  return (
    <article className="space-y-8 rounded-2xl bg-white p-6 shadow-sm sm:p-9">
      <header>
        <p className="mb-2 text-sm text-slate-600">{seasonLabel(league.season_year)}</p>
        <h1 className="break-words text-3xl font-bold">{league.name}</h1>
        <p className="mt-3">{league.manager_count} managers · {league.draft_rounds} rounds</p>
      </header>
      <section>
        <h2 className="mb-3 text-xl font-semibold">Managers</h2>
        {managers.error || !managers.data ? <p role="alert">The manager roster is temporarily unavailable.</p> :
          managers.data.length === 0 ? <p>No managers are currently visible.</p> :
            <ul className="divide-y divide-slate-200">{managers.data.map((manager) => (
              <li key={manager.id} className="flex flex-wrap justify-between gap-2 py-3">
                <span className="break-words">{manager.display_name}</span>
                <span className="text-sm text-slate-600">{manager.role === "commissioner" ? "Commissioner" : "Member"}{manager.departed_at ? " · Departed" : " · Active"}</span>
              </li>
            ))}</ul>}
      </section>
      <section>
        <h2 className="mb-3 text-xl font-semibold">Scoring rules</h2>
        {scoring.error || !scoring.data ? <p role="alert">Scoring rules are temporarily unavailable.</p> :
          scoring.data.length === 0 ? <p>No scoring version is configured yet.</p> : scoring.data.map((version) => (
            <div key={version.version} className="mb-6">
              <h3 className="mb-2 font-medium">Version {version.version}</h3>
              <table className="w-full text-left text-sm">
                <caption className="sr-only">Fantasy points per stat for scoring version {version.version}</caption>
                <thead><tr><th className="py-2">Stat</th><th className="py-2 text-right">Points</th></tr></thead>
                <tbody>{scoringRows(version).map((row) => <tr key={row.key} className="border-t border-slate-200"><td className="py-2 pr-3">{row.label}</td><td className="py-2 text-right tabular-nums">{row.points}</td></tr>)}</tbody>
              </table>
              <p className="mt-4 text-sm text-slate-600">Only fumbles lost are penalized. No long-play or yardage bonuses; no return-yardage points. Touchdown categories are separate; conversion plays do not also count as ordinary play stats. Unusual recovery touchdowns and blocked-kick classifications remain unresolved.</p>
            </div>
          ))}
      </section>
    </article>
  );
}

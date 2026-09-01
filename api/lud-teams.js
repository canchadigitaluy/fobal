import { createClient } from "@supabase/supabase-js";
import { fetchLeagueJson } from "./_league-cache.js";

export const config = {
  maxDuration: 30,
};

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");
  res.setHeader("access-control-allow-headers", "content-type");

  if (req.method === "OPTIONS") {
    return res.status(200).json({ ok: true });
  }

  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const cached = await loadCachedClubs();
  try {
    const teams = await fetchLeagueJson("/teams/?ordering=name&limit=500", 12000);
    const teamRows = Array.isArray(teams)
      ? teams
      : Array.isArray(teams?.results)
        ? teams.results
        : Array.isArray(teams?.data)
          ? teams.data
          : [];
    const leagueClubs = teamRows
      .filter((team) => Number.isInteger(team.id) && team.name)
      .map((team) => ({
        id: `lud-team-${team.id}`,
        display_name: team.name,
        lud_team_id: team.id,
        logo_url: team.logo_url ?? null,
      }))
      .sort((a, b) => a.display_name.localeCompare(b.display_name));

    const persisted = await persistLeagueClubs(leagueClubs);
    const clubs = mergeClubs([...persisted, ...leagueClubs], cached);

    res.setHeader("cache-control", "s-maxage=300, stale-while-revalidate=1800");
    return res.status(200).json({ clubs, source: "league" });
  } catch (error) {
    if (cached.length > 0) {
      res.setHeader("cache-control", "s-maxage=120, stale-while-revalidate=900");
      return res.status(200).json({ clubs: cached, source: "cache" });
    }
    return res.status(502).json({
      error: "liga_unreachable",
      details: String(error?.message || error),
    });
  }
}

async function loadCachedClubs() {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return [];
  }
  try {
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { data, error } = await supabase
      .from("cantera_clubs")
      .select("id, display_name, lud_team_id")
      .eq("status", "active")
      .order("display_name");
    if (error || !Array.isArray(data)) return [];
    return data
      .filter((club) => club.id && club.display_name)
      .map((club) => ({
        id: club.id,
        display_name: club.display_name,
        lud_team_id: club.lud_team_id,
      }));
  } catch (_) {
    return [];
  }
}

async function persistLeagueClubs(clubs) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return [];
  }
  try {
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    await supabase.from("lud_teams").upsert(
      clubs.map((club) => ({
        lud_team_id: club.lud_team_id,
        name: club.display_name,
        short_name: club.display_name,
        logo_url: club.logo_url,
      })),
      { onConflict: "lud_team_id" },
    );
    const { error } = await supabase.from("cantera_clubs").upsert(
      clubs.map((club) => ({
        lud_team_id: club.lud_team_id,
        display_name: club.display_name,
        status: "active",
      })),
      { onConflict: "lud_team_id" },
    );
    if (error) return [];
    return loadCachedClubs();
  } catch (_) {
    return [];
  }
}

function mergeClubs(primary, secondary) {
  const merged = new Map();
  for (const club of [...primary, ...secondary]) {
    const key = club.lud_team_id == null
      ? `name:${club.display_name.toLowerCase()}`
      : `team:${club.lud_team_id}`;
    if (!merged.has(key)) merged.set(key, club);
  }
  return [...merged.values()].sort((a, b) =>
    a.display_name.localeCompare(b.display_name),
  );
}

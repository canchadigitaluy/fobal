import { createClient } from "@supabase/supabase-js";

const LUD_API_BASE = "https://lud-backend-ld7d.onrender.com/api";

export default async function handler(req, res) {
  if (req.method !== "POST" && req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const syncSecret = process.env.CANTERA_SYNC_SECRET;
  const requestSecret = req.headers["x-sync-secret"];
  if (!syncSecret || requestSecret !== syncSecret) {
    return res.status(403).json({ error: "Forbidden" });
  }

  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(500).json({
      error: "Falta SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en Vercel.",
    });
  }

  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );

  const response = await fetch(`${LUD_API_BASE}/teams/?ordering=name&limit=500`);
  if (!response.ok) {
    return res.status(502).json({
      error: `LUD Stats respondio ${response.status}`,
    });
  }

  const teams = await response.json();
  const cleanTeams = teams
    .filter((team) => Number.isInteger(team.id) && team.name)
    .map((team) => ({
      lud_team_id: team.id,
      name: team.name,
      short_name: team.name,
      logo_url: team.logo_url ?? null,
      source_payload: team,
    }));

  const { error: teamError } = await supabase
    .from("lud_teams")
    .upsert(cleanTeams, { onConflict: "lud_team_id" });

  if (teamError) {
    return res.status(500).json({ error: teamError.message });
  }

  const canteraClubs = cleanTeams.map((team) => ({
    lud_team_id: team.lud_team_id,
    display_name: team.name,
    logo_url: team.logo_url,
    status: "active",
  }));

  const { error: clubError } = await supabase
    .from("cantera_clubs")
    .upsert(canteraClubs, { onConflict: "lud_team_id" });

  if (clubError) {
    return res.status(500).json({ error: clubError.message });
  }

  return res.status(200).json({
    ok: true,
    source: `${LUD_API_BASE}/teams/?ordering=name&limit=500`,
    teams: cleanTeams.length,
  });
}

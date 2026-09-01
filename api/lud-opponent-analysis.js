import { fetchLeagueJson } from "./_league-cache.js";

export const config = { maxDuration: 30 };

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");
  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });
  if (req.method !== "GET") return res.status(405).json({ error: "method_not_allowed" });

  const teamId = Number(req.query.opponentTeamId);
  const phaseId = Number(req.query.phaseId);
  const categoryName = String(req.query.categoryName || "").trim();
  if (!Number.isInteger(teamId)) return res.status(400).json({ error: "invalid_team" });

  const [seasonRaw, matchesRaw, standingsRaw] = await Promise.all([
    fetchLeagueJson(`/teams/${teamId}/season-players/`, 9000).catch(() => []),
    Number.isInteger(phaseId)
      ? fetchLeagueJson(`/phases/${phaseId}/matches/`, 9000).catch(() => [])
      : Promise.resolve([]),
    Number.isInteger(phaseId)
      ? fetchLeagueJson(`/phases/${phaseId}/standings/`, 9000).catch(() => [])
      : Promise.resolve([]),
  ]);

  const entries = rows(seasonRaw).filter((entry) =>
    sameCategory(entry.category || entry.category_name, categoryName),
  );
  const latestYear = Math.max(0, ...entries.map((entry) => Number(entry.season_year) || 0));
  const currentEntries = entries.filter(
    (entry) => !latestYear || Number(entry.season_year) === latestYear,
  );
  const playerMap = new Map();
  for (const entry of currentEntries) {
    for (const player of entry.players || []) {
      const id = Number(player.id);
      if (!Number.isInteger(id)) continue;
      const existing = playerMap.get(id) || {};
      playerMap.set(id, {
        id,
        name: player.name || existing.name || "Jugador",
        position: player.position || player.position_name || existing.position || "",
        matches: Math.max(Number(player.matches) || 0, existing.matches || 0),
        minutes: Math.max(Number(player.minutes) || 0, existing.minutes || 0),
        goals: Math.max(Number(player.goals) || 0, existing.goals || 0),
        assists: Math.max(Number(player.assists) || 0, existing.assists || 0),
      });
    }
  }
  const players = [...playerMap.values()];
  const danger = [...players]
    .sort((a, b) => b.goals - a.goals || b.assists - a.assists || b.minutes - a.minutes)
    .slice(0, 5);
  const continuity = [...players].sort((a, b) => b.minutes - a.minutes).slice(0, 5);

  const finished = rows(matchesRaw)
    .filter((match) => belongs(match, teamId) && score(match, "home") != null && score(match, "away") != null)
    .sort((a, b) => String(b.date || "").localeCompare(String(a.date || "")))
    .slice(0, 5);
  let gf = 0;
  let ga = 0;
  const results = finished.map((match) => {
    const home = teamId === Number(match.home_team?.id || match.home_team_id);
    const own = score(match, home ? "home" : "away") || 0;
    const against = score(match, home ? "away" : "home") || 0;
    gf += own;
    ga += against;
    const opponent = home ? match.away_team?.name : match.home_team?.name;
    return `${own > against ? "G" : own < against ? "P" : "E"} ${own}-${against} vs ${opponent || "rival"}`;
  });

  const standings = rows(standingsRaw);
  const standingIndex = standings.findIndex((row) =>
    Number(row.team?.id || row.team_id || row.id) === teamId,
  );
  const standing = standingIndex >= 0 ? standings[standingIndex] : null;
  const played = Number(standing?.played || standing?.matches_played || standing?.pj) || 0;
  const points = Number(standing?.points || standing?.pts) || 0;

  const tableContext = standing
    ? `Puesto ${standingIndex + 1} de ${standings.length}; ${played} partidos y ${points} puntos.`
    : "La tabla de esta categoría no publicó todavía una posición verificable para el rival.";
  const formContext = finished.length
    ? `Últimos ${finished.length}: ${results.join("; ")}. Balance: ${gf} goles a favor y ${ga} en contra.`
    : "No hay resultados recientes verificables disponibles para completar la forma del rival.";
  const dangerContext = danger.length
    ? danger.map((p) => `${p.name}: ${p.goals} goles, ${p.assists} asistencias, ${p.minutes} min`).join("; ")
    : "No hay estadísticas individuales verificables para esta categoría.";
  const squadContext = continuity.length
    ? `Jugadores con mayor continuidad: ${continuity.map((p) => `${p.name} (${p.minutes} min, ${p.matches} PJ${p.position ? `, ${p.position}` : ""})`).join("; ")}.`
    : "No hay minutos individuales publicados para esta categoría.";

  res.setHeader("cache-control", "no-store, max-age=0");
  return res.status(200).json({
    tableContext,
    styleSummary: `${formContext} ${squadContext} El sistema y los comportamientos tácticos deben confirmarse con observación del DT; no se inventan desde estadísticas.`,
    dangerPlayers: dangerContext,
    memorySummary: formContext,
    squadSummary: squadContext,
    recentMatches: results,
  });
}

function rows(value) {
  if (Array.isArray(value)) return value;
  for (const key of ["results", "data", "items", "matches", "standings"]) {
    if (Array.isArray(value?.[key])) return value[key];
  }
  return [];
}

function normalize(value) {
  return String(value || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]/g, "");
}

function sameCategory(a, b) {
  if (!b) return true;
  const left = normalize(a);
  const right = normalize(b);
  return left === right || left.includes(right) || right.includes(left);
}

function belongs(match, teamId) {
  return Number(match.home_team?.id || match.home_team_id) === teamId || Number(match.away_team?.id || match.away_team_id) === teamId;
}

function score(match, side) {
  const value = match[`${side}_score`] ?? match[`${side}Score`];
  return value == null || value === "" ? null : Number(value);
}

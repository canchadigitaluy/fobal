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

  const seasonPromise = fetchLeagueJson(`/teams/${teamId}/season-players/`, 9000).catch(() => []);
  const matchesPromise = Number.isInteger(phaseId)
    ? fetchLeagueJson(`/phases/${phaseId}/matches/`, 9000).catch(() => [])
    : Promise.resolve([]);
  const standingsPromise = Number.isInteger(phaseId)
    ? fetchLeagueJson(`/phases/${phaseId}/standings/`, 9000).catch(() => [])
    : Promise.resolve([]);

  const matchesRaw = await matchesPromise;
  const allFinishedForEvents = rows(matchesRaw)
    .filter((match) => belongs(match, teamId) && score(match, "home") != null && score(match, "away") != null)
    .sort((a, b) => String(b.date || "").localeCompare(String(a.date || "")))
    .slice(0, 5);
  const goalMinutePromise = buildGoalMinuteData(allFinishedForEvents, teamId);

  const [seasonRaw, standingsRaw] = await Promise.all([seasonPromise, standingsPromise]);

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

  const allFinished = rows(matchesRaw)
    .filter((match) => belongs(match, teamId) && score(match, "home") != null && score(match, "away") != null)
    .sort((a, b) => String(b.date || "").localeCompare(String(a.date || "")));
  const finished = allFinished.slice(0, 5);
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
  const objectiveStats = buildObjectiveStats(allFinished, teamId);
  const goalMinuteData = await goalMinutePromise;

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
    homeAwaySplit: objectiveStats.homeAwaySplit,
    avgGoalsPerMatch: objectiveStats.avgGoalsPerMatch,
    biggestWin: objectiveStats.biggestWin,
    biggestLoss: objectiveStats.biggestLoss,
    currentStreak: objectiveStats.currentStreak,
    cleanSheets: objectiveStats.cleanSheets,
    goalMinuteBuckets: goalMinuteData.goalMinuteBuckets,
    goalMinuteSampleSize: goalMinuteData.goalMinuteSampleSize,
  });
}

function buildObjectiveStats(matches, teamId) {
  const split = {
    home: emptySplitSide(),
    away: emptySplitSide(),
  };
  let totalFor = 0;
  let totalAgainst = 0;
  let cleanSheets = 0;
  let biggestWin = null;
  let biggestLoss = null;
  const streakResults = [];

  for (const match of matches) {
    const home = teamId === Number(match.home_team?.id || match.home_team_id);
    const own = score(match, home ? "home" : "away") || 0;
    const against = score(match, home ? "away" : "home") || 0;
    const side = home ? split.home : split.away;
    const opponent = home ? match.away_team?.name : match.home_team?.name;
    const diff = own - against;

    side.played += 1;
    side.gf += own;
    side.ga += against;
    if (diff > 0) side.won += 1;
    else if (diff < 0) side.lost += 1;
    else side.drawn += 1;

    totalFor += own;
    totalAgainst += against;
    if (against === 0) cleanSheets += 1;
    streakResults.push(diff > 0 ? "W" : diff < 0 ? "L" : "D");

    if (diff > 0 && (!biggestWin || diff > biggestWin.diff)) {
      biggestWin = { diff, score: `${own}-${against}`, opponent: opponent || "rival" };
    }
    if (diff < 0 && (!biggestLoss || Math.abs(diff) > biggestLoss.diff)) {
      biggestLoss = { diff: Math.abs(diff), score: `${own}-${against}`, opponent: opponent || "rival" };
    }
  }

  return {
    homeAwaySplit: split,
    avgGoalsPerMatch: {
      for: round1(matches.length ? totalFor / matches.length : 0),
      against: round1(matches.length ? totalAgainst / matches.length : 0),
    },
    biggestWin: biggestWin ? { score: biggestWin.score, opponent: biggestWin.opponent } : null,
    biggestLoss: biggestLoss ? { score: biggestLoss.score, opponent: biggestLoss.opponent } : null,
    currentStreak: buildCurrentStreak(streakResults),
    cleanSheets,
  };
}

function emptySplitSide() {
  return { played: 0, won: 0, drawn: 0, lost: 0, gf: 0, ga: 0 };
}

function round1(value) {
  return Math.round(value * 10) / 10;
}

function buildCurrentStreak(results) {
  if (!results.length) return null;
  const type = results[0];
  let count = 0;
  for (const result of results) {
    if (result !== type) break;
    count += 1;
  }
  return { type, count };
}

async function buildGoalMinuteData(matches, teamId) {
  const buckets = [
    { range: "0-15", goalsFor: 0, goalsAgainst: 0 },
    { range: "16-30", goalsFor: 0, goalsAgainst: 0 },
    { range: "31-45", goalsFor: 0, goalsAgainst: 0 },
    { range: "46-60", goalsFor: 0, goalsAgainst: 0 },
    { range: "61-75", goalsFor: 0, goalsAgainst: 0 },
    { range: "76-90", goalsFor: 0, goalsAgainst: 0 },
  ];
  const eventRows = await Promise.all(
    matches.map((match) =>
      fetchLeagueJson(`/matches/${match.id}/events/`, 9000)
        .then((value) => ({ readable: true, events: rows(value) }))
        .catch(() => ({ readable: false, events: [] })),
    ),
  );
  const readable = eventRows.filter((row) => row.readable);
  for (const row of readable) {
    const events = Array.isArray(row.events) ? row.events : [];
    for (const event of events) {
      if (event?.event_type !== "goal") continue;
      const minute = Number(event.minute) || 0;
      const bucket = buckets[goalBucketIndex(minute)];
      if (Number(event.team) === teamId) bucket.goalsFor += 1;
      else bucket.goalsAgainst += 1;
    }
  }
  return {
    goalMinuteBuckets: buckets,
    goalMinuteSampleSize: readable.length,
  };
}

function goalBucketIndex(minute) {
  if (minute <= 15) return 0;
  if (minute <= 30) return 1;
  if (minute <= 45) return 2;
  if (minute <= 60) return 3;
  if (minute <= 75) return 4;
  return 5;
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

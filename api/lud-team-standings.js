import { fetchLeagueJson } from "./_league-cache.js";

export const config = {
  maxDuration: 30,
};

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");
  res.setHeader("access-control-allow-headers", "content-type");
  res.setHeader("cache-control", "s-maxage=900, stale-while-revalidate=3600");

  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });
  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const teamId = Number(req.query.teamId);
  const clubName = text(req.query.clubName);
  const categoryName = text(req.query.categoryName);
  const categoryId = Number(req.query.categoryId);

  if (!Number.isInteger(teamId) && !clubName) {
    return res.status(400).json({ error: "teamId o clubName requerido" });
  }
  if (!categoryName && !Number.isInteger(categoryId)) {
    return res.status(400).json({ error: "categoryName requerido" });
  }

  try {
    const requestedCategory = categoryName || categoryLabelFromId(categoryId);
    const candidates = await candidatePhases(requestedCategory, teamId);
    let bestEmpty = null;

    for (const phase of candidates) {
      const rows = await fetchJson(`/phases/${phase.id}/standings/`, 5000).catch(
        () => [],
      );
      if (!Array.isArray(rows) || rows.length === 0) continue;
      const target = rows.find((row) => teamMatches(row, teamId, clubName));
      if (!target) {
        bestEmpty ??= {
          source: "league",
          categoryName: phase.categoryName || requestedCategory,
          seasonYear: phase.seasonYear || null,
          phaseName: phase.name || "",
          teamName: clubName,
          rows: [],
        };
        continue;
      }
      const table = rows
        .sort(compareStanding)
        .map((row, index) => ({
          rank: index + 1,
          teamId: row?.team?.id ?? null,
          teamName: text(row?.team?.name),
          logoUrl: row?.team?.logo_url ?? null,
          played: number(row?.played),
          won: number(row?.won ?? row?.total_won),
          drawn: number(row?.drawn ?? row?.total_drawn),
          lost: number(row?.lost ?? row?.total_lost),
          goalsFor: number(row?.goals_for),
          goalsAgainst: number(row?.goals_against),
          goalDifference: number(row?.goal_difference),
          points: number(row?.total_points ?? row?.points),
          isOwnTeam: teamMatches(row, teamId, clubName),
        }));

      return res.status(200).json({
        source: "league",
        categoryName: text(target.phase_detail?.tournament?.category) || phase.categoryName || requestedCategory,
        seasonYear: target.phase_detail?.season ?? phase.seasonYear,
        phaseName:
          text(target.phase_detail?.tournament?.name) ||
          text(target.phase_detail?.name) ||
          phase.name,
        teamName: text(target.team?.name) || clubName,
        rows: table,
      });
    }

    const fallbackRows = await fetchJson(`/standings/`, 5000).catch(() => []);
    const categoryRows = Array.isArray(fallbackRows)
      ? fallbackRows.filter((row) =>
          categoryMatches(
            [
              row?.phase_detail?.tournament?.category,
              row?.phase_detail?.tournament?.name,
              row?.phase_detail?.name,
            ].join(" "),
            requestedCategory
          )
        )
      : [];
    const latestSeason = categoryRows.reduce(
      (max, row) => Math.max(max, Number(row?.phase_detail?.season) || 0),
      0
    );
    const seasonRows = categoryRows.filter(
      (row) => Number(row?.phase_detail?.season) === latestSeason
    );
    const target = seasonRows.find((row) => teamMatches(row, teamId, clubName));
    if (!target) {
      return res.status(200).json(bestEmpty ?? {
        source: "league",
        categoryName: requestedCategory,
        seasonYear: latestSeason || null,
        phaseName: "",
        teamName: clubName,
        rows: [],
      });
    }

    const phaseId = target.phase_detail?.id;
    const table = seasonRows
      .filter((row) => row?.phase_detail?.id === phaseId)
      .sort(compareStanding)
      .map((row, index) => ({
        rank: index + 1,
        teamId: row?.team?.id ?? null,
        teamName: text(row?.team?.name),
        logoUrl: row?.team?.logo_url ?? null,
        played: number(row?.played),
        won: number(row?.won ?? row?.total_won),
        drawn: number(row?.drawn ?? row?.total_drawn),
        lost: number(row?.lost ?? row?.total_lost),
        goalsFor: number(row?.goals_for),
        goalsAgainst: number(row?.goals_against),
        goalDifference: number(row?.goal_difference),
        points: number(row?.total_points ?? row?.points),
        isOwnTeam: teamMatches(row, teamId, clubName),
      }));

    return res.status(200).json({
      source: "league",
      categoryName: text(target.phase_detail?.tournament?.category) || categoryName,
      seasonYear: target.phase_detail?.season ?? latestSeason,
      phaseName:
        text(target.phase_detail?.tournament?.name) ||
        text(target.phase_detail?.name),
      teamName: text(target.team?.name) || clubName,
      rows: table,
    });
  } catch (error) {
    return res.status(502).json({
      error: "standings_unreachable",
      message: "No se pudo conectar con la tabla de la liga.",
      details: String(error?.message || error),
      rows: [],
    });
  }
}

async function fetchJson(path, timeoutMs = 7000) {
  return fetchLeagueJson(path, timeoutMs);
}

async function candidatePhases(categoryName, teamId) {
  const phases = [];
  const [teamDetail, seasons] = await Promise.all([
    Number.isInteger(teamId)
      ? fetchJson(`/teams/${teamId}/`, 5000).catch(() => null)
      : Promise.resolve(null),
    fetchJson("/tournaments/selector/", 5000).catch(() => []),
  ]);
  for (const phase of teamDetail?.phases ?? []) {
    const haystack = [
      phase.name,
      phase.tournament,
      phase.tournament_name,
      phase.category,
      phase.category_name,
      phase.season,
    ].join(" ");
    if (!categoryMatches(haystack, categoryName)) continue;
    phases.push({
      id: Number(phase.id),
      name: text(phase.name),
      categoryName,
      seasonYear: Number(phase.season) || null,
    });
  }
  const categories = seasons?.[0]?.categories ?? [];
  for (const category of categories) {
    if (!categoryMatches(category?.name, categoryName)) continue;
    for (const division of category.divisions ?? []) {
      for (const phase of division.phases ?? []) {
        phases.push({
          id: Number(phase.id),
          name: text(phase.name),
          categoryName: text(category.name),
          seasonYear: Number(seasons?.[0]?.name) || null,
        });
      }
    }
  }
  const seen = new Set();
  return phases
    .filter((phase) => Number.isInteger(phase.id))
    .filter((phase) => {
      if (seen.has(phase.id)) return false;
      seen.add(phase.id);
      return true;
    });
}

function compareStanding(a, b) {
  return (
    number(b?.total_points ?? b?.points) - number(a?.total_points ?? a?.points) ||
    number(b?.goal_difference) - number(a?.goal_difference) ||
    number(b?.goals_for) - number(a?.goals_for) ||
    text(a?.team?.name).localeCompare(text(b?.team?.name))
  );
}

function teamMatches(row, teamId, clubName) {
  const rowTeamId = Number(row?.team?.id);
  if (Number.isInteger(teamId) && rowTeamId === teamId) return true;
  const wanted = normalizeTeamName(clubName);
  const got = normalizeTeamName(row?.team?.name);
  return Boolean(wanted && got && (got.includes(wanted) || wanted.includes(got)));
}

function categoryLabelFromId(id) {
  return {
    1: "Mayores",
    2: "Reserva",
    3: "Presenior",
    4: "Master",
    5: "Sub 20",
    6: "Sub 18",
    7: "Sub 16",
  }[id] || "";
}

function categoryMatches(source, requestedCategory) {
  const requested = normalizeCategoryName(requestedCategory);
  const haystack = normalizeCategoryName(source);
  if (!requested || !haystack) return false;
  const requestedSub = requested.match(/sub(\d+)/)?.[1];
  if (requestedSub) return haystack.includes(`sub${requestedSub}`);
  if (requested.includes("mayores")) {
    return haystack.includes("mayores") || haystack.includes("primera");
  }
  if (requested.includes("reserva")) return haystack.includes("reserva");
  if (requested.includes("master")) return haystack.includes("master");
  if (requested.includes("presenior")) return haystack.includes("presenior");
  return haystack.includes(requested);
}

function normalizeCategoryName(value) {
  return normalize(value)
    .replace(/\bsub[-\s]?/g, "sub")
    .replace(/\bu[-\s]?/g, "sub")
    .replace(/\bmayor(?:es)?\b/g, "mayores")
    .replace(/categoria-/g, "")
    .replace(/division-/g, "");
}

function normalizeTeamName(value) {
  return normalize(value)
    .replace(/\buniversitario\b/g, "")
    .replace(/\bclub\b/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

function normalize(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, "-");
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function text(value) {
  return String(value ?? "").trim();
}

import { fetchLeagueJson, normalizeLeaguePath } from "./_league-cache.js";

const LUD_API_BASE = "https://lud-backend-ld7d.onrender.com/api";
const PLAYA_HONDA_FIXTURE_URL = "https://playahondau.github.io/playahondau/";

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

  const teamId = Number(req.query.teamId);
  if (!Number.isInteger(teamId)) {
    return res.status(400).json({ error: "teamId invalido" });
  }

  const categoryId = Number(req.query.categoryId);
  const categoryName = String(req.query.categoryName ?? "").trim();
  const clubName = String(req.query.clubName ?? "").trim();
  const horizonDays = clamp(Number(req.query.horizonDays) || 90, 7, 240);
  const historyOnly = String(req.query.history ?? "") === "1";
  const hasCategoryFilter = Number.isInteger(categoryId) || Boolean(categoryName);

  const errors = [];

  const requestedCategory = categoryName || categoryLabelFromId(categoryId);
  const phaseUrls = await candidatePhaseUrls(requestedCategory, teamId).catch(
    () => [],
  );
  const attempts = [
    `${LUD_API_BASE}/teams/${teamId}/matches/`,
    ...phaseUrls,
    ...candidateUrls({ teamId, categoryId, categoryName }),
  ];
  let bestEmptyResult = null;
  for (const url of attempts) {
    try {
      const raw = await fetchJson(normalizeLeaguePath(url), 3500);
      const rows = extractRows(raw);
      const normalized = rows.map((item) => normalizeMatch(item, teamId));
      const relevant = normalized.filter((match) =>
        isRelevant(match, teamId, categoryId, categoryName)
      );
      let matches;
      let mode;
  if (historyOnly) {
        matches = relevant
          .filter((match) =>
            isPlayedResult(match)
          )
          .sort((a, b) => b.date.localeCompare(a.date))
          .slice(0, 5)
          .map(publicMatch);
        mode = "history";
      } else {
        matches = relevant
          .filter((match) => isUpcoming(match, horizonDays))
          .sort((a, b) => a.date.localeCompare(b.date))
          .map(publicMatch);
        mode = "upcoming";
        if (matches.length === 0) {
          matches = relevant
            .filter((match) => match.date)
            .sort((a, b) => b.date.localeCompare(a.date))
            .slice(0, 5)
            .map(publicMatch);
          mode = "recent";
        }
      }
      const result = {
        teamId,
        categoryId: Number.isInteger(categoryId) ? categoryId : null,
        categoryName,
        source: "lud_live",
        syncedAt: new Date().toISOString(),
        fixtureDiagnostics: {
          checkedUrl: safeUrl(url),
          rawRows: rows.length,
          categoryRows: relevant.length,
          invalidDateRows: relevant.filter((match) => !match.date).length,
          mode,
        },
        matches,
      };

      if (matches.length > 0 || !hasCategoryFilter) {
        return res.status(200).json(result);
      }
      bestEmptyResult = chooseBetterEmptyResult(bestEmptyResult, result);
    } catch (error) {
      errors.push(`${url} -> ${error?.message || error}`);
    }
  }

  const fallback = await loadPublicFixtureFallback({
    teamId,
    clubName,
    categoryId,
    categoryName,
    horizonDays,
    historyOnly,
    upstreamErrors: errors,
  });
  if (fallback) {
    return res.status(200).json(fallback);
  }

  if (bestEmptyResult) {
    return res.status(200).json({
      ...bestEmptyResult,
      fixtureDiagnostics: {
        ...bestEmptyResult.fixtureDiagnostics,
        checkedAttempts: attempts.length,
        categoryVerified: false,
      },
    });
  }

  return res.status(502).json({
    error: "lud_fixture_unreachable",
    message: "No se pudo consultar el fixture de la liga.",
    details: errors.slice(0, 6),
    matches: [],
  });
}

async function loadPublicFixtureFallback({
  teamId,
  clubName,
  categoryId,
  categoryName,
  horizonDays,
  historyOnly,
  upstreamErrors,
}) {
  if (!isPlayaHondaClub(clubName)) return null;
  const section = playaHondaSection(categoryName);
  if (!section) return null;

  try {
    const response = await fetch(PLAYA_HONDA_FIXTURE_URL, {
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      upstreamErrors.push(`${PLAYA_HONDA_FIXTURE_URL} -> ${response.status}`);
      return null;
    }
    const html = await response.text();
    const seasonYear = Number(
      html.match(/Temporada\s+(\d{4})/)?.[1] || new Date().getUTCFullYear()
    );
    const upcomingRows = extractPlayHondaRows(html, section.upcomingIds, "proximo");
    const upcoming = upcomingRows.map((row, index) =>
      normalizePlayHondaUpcomingMatch(row, {
        teamId,
        categoryId: Number.isInteger(categoryId) ? categoryId : null,
        categoryName: section.label,
        seasonYear,
        index,
      })
    );
    let normalized = upcoming;
    let matches = [];
    let fallbackMode = historyOnly ? "ultimos-resultados" : "proximos";
    if (!historyOnly) {
      matches = upcoming
        .filter((match) => isUpcoming(match, horizonDays))
        .sort((a, b) => a.date.localeCompare(b.date))
        .map(publicMatch);
    }
    if (historyOnly || matches.length === 0) {
      const playedRows = extractPlayHondaRows(html, section.playedIds, "jugado");
      normalized = playedRows.map((row, index) =>
        normalizePlayHondaPlayedMatch(row, {
          teamId,
          categoryId: Number.isInteger(categoryId) ? categoryId : null,
          categoryName: section.label,
          seasonYear,
          index,
        })
      );
      matches = normalized
        .filter((match) =>
          match.date && match.homeScore !== null && match.awayScore !== null
        )
        .sort((a, b) => b.date.localeCompare(a.date))
        .slice(0, 5)
        .map(publicMatch);
      fallbackMode = "ultimos-resultados";
    }

    return {
      teamId,
      categoryId: Number.isInteger(categoryId) ? categoryId : null,
      categoryName: section.label,
      source: "ludfan_public_fallback",
      syncedAt: new Date().toISOString(),
      fixtureDiagnostics: {
        checkedUrl: "playahondau.github.io/playahondau",
        rawRows: normalized.length,
        categoryRows: normalized.length,
        invalidDateRows: normalized.filter((match) => !match.date).length,
        checkedAttempts: upstreamErrors.length + 1,
        categoryVerified: true,
        mode: fallbackMode,
        upstream: "LUD no disponible; respaldo publico del club",
      },
      matches,
    };
  } catch (error) {
    upstreamErrors.push(`${PLAYA_HONDA_FIXTURE_URL} -> ${error?.message || error}`);
    return null;
  }
}

function isPlayaHondaClub(clubName) {
  const name = normalizeCategoryName(clubName);
  return name.includes("playa-honda");
}

function playaHondaSection(categoryName) {
  const requested = normalizeCategoryName(categoryName);
  const sections = [
    fixtureSection("Mayores", ["mayores", "mayor"], "may"),
    fixtureSection("Reserva", ["reserva"], "res"),
    fixtureSection("Pre Senior", ["pre-senior", "presenior"], "pre"),
    fixtureSection("Sub 20", ["sub20"], "s20", "sub20"),
    fixtureSection("Sub 18", ["sub18"], "s18", "sub18"),
    fixtureSection("Master", ["master"], "mas", "master"),
  ];
  return sections.find((section) =>
    section.keys.some((key) => requested.includes(key))
  );
}

function fixtureSection(label, keys, shortId, longId = shortId) {
  return {
    label,
    keys,
    upcomingIds: [`part-${shortId}-proximos`, `part-${longId}-proximos`],
    playedIds: [`part-${shortId}-jugados`, `part-${longId}-jugados`],
  };
}

function extractPlayHondaRows(html, ids, kind) {
  const id = ids.find((candidate) => html.includes(`id="${candidate}"`));
  if (!id) return [];
  const start = html.indexOf(`id="${id}"`);
  const nextSection = html.indexOf("<!--", start + 1);
  const chunk = html.slice(
    start,
    nextSection > start ? nextSection : start + 8000
  );
  const rows = [];
  const rowPattern =
    new RegExp(`<div class="part-row ${kind}[^"]*">[\\s\\S]*?<span class="part-fecha">([\\s\\S]*?)<\\/span>[\\s\\S]*?<span class="part-equipos">([\\s\\S]*?)<\\/span>[\\s\\S]*?<span class="part-loc">([\\s\\S]*?)<\\/span>[\\s\\S]*?<\\/div>`, "g");
  let match;
  while ((match = rowPattern.exec(chunk))) {
    rows.push({
      date: cleanHtml(match[1]),
      teams: cleanHtml(match[2]),
      location: cleanHtml(match[3]),
      kind,
    });
  }
  return rows;
}

function normalizePlayHondaUpcomingMatch(row, { teamId, categoryId, categoryName, seasonYear, index }) {
  const [leftRaw, rightRaw] = row.teams.split(/\s+vs\s+/i);
  const left = cleanTeamName(leftRaw);
  const right = cleanTeamName(rightRaw);
  const isLocal = normalizeCategoryName(row.location).includes("local");
  const homeTeamName = isLocal ? "Playa Honda" : left;
  const awayTeamName = isLocal ? right : "Playa Honda";
  const opponentName = normalizeCategoryName(homeTeamName).includes("playa-honda")
    ? awayTeamName
    : homeTeamName;
  const date = normalizePlayHondaDate(row.date, seasonYear);
  return {
    id: `playa-honda-${categoryName}-${index}-${date || row.date}-${opponentName}`,
    date,
    rawDate: row.date,
    competition: "Fixture publico Playa Honda / LUD",
    categoryId,
    categoryName,
    homeTeamId: null,
    homeTeamName,
    awayTeamId: null,
    awayTeamName,
    opponentName,
    venue: row.location,
    round: "",
    status: "proximo",
    sourcePayload: row,
  };
}

function normalizePlayHondaPlayedMatch(row, context) {
  const scoreMatch = row.teams.match(/^(.*?)\s+(\d+)\s+[-]\s+(\d+)\s+(.*?)$/);
  if (!scoreMatch) {
    return {
      ...normalizePlayHondaUpcomingMatch(
        { ...row, teams: row.teams.replace(/^vs\s+/i, "Playa Honda vs ") },
        context
      ),
      status: "jugado_sin_resultado",
      homeScore: null,
      awayScore: null,
    };
  }
  const left = cleanTeamName(scoreMatch[1]);
  const leftScore = Number(scoreMatch[2]);
  const rightScore = Number(scoreMatch[3]);
  const right = cleanTeamName(scoreMatch[4]);
  const date = normalizePlayHondaDate(row.date, context.seasonYear);
  const opponentName = normalizeCategoryName(left).includes("playa-honda")
    ? right
    : left;
  return {
    id: `playa-honda-${context.categoryName}-played-${context.index}-${date || row.date}-${opponentName}`,
    date,
    rawDate: row.date,
    competition: "Resultados publicados Playa Honda / LUD",
    categoryId: context.categoryId,
    categoryName: context.categoryName,
    homeTeamId: null,
    homeTeamName: left,
    awayTeamId: null,
    awayTeamName: right,
    opponentName,
    homeScore: Number.isFinite(leftScore) ? leftScore : null,
    awayScore: Number.isFinite(rightScore) ? rightScore : null,
    venue: row.location,
    round: "",
    status: "jugado",
    sourcePayload: row,
  };
}

function normalizePlayHondaDate(value, seasonYear) {
  const cleaned = normalizeText(value);
  const match = cleaned.match(/\b(\d{1,2})\s+([a-z]+)\b/i);
  if (!match) return "";
  const day = Number(match[1]);
  const month = monthNumber(match[2]);
  if (!month || !validDateParts({ day, month, year: seasonYear })) return "";
  return new Date(Date.UTC(seasonYear, month - 1, day, 12, 0, 0)).toISOString();
}

function monthNumber(value) {
  const key = normalizeText(value).slice(0, 3);
  return {
    ene: 1,
    feb: 2,
    mar: 3,
    abr: 4,
    may: 5,
    jun: 6,
    jul: 7,
    ago: 8,
    sep: 9,
    oct: 10,
    nov: 11,
    dic: 12,
  }[key];
}

function cleanHtml(value) {
  return decodeEntities(String(value || "").replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function cleanTeamName(value) {
  return cleanHtml(value).replace(/\s+$/g, "");
}

function decodeEntities(value) {
  return String(value)
    .replace(/&mdash;/g, "-")
    .replace(/&ndash;/g, "-")
    .replace(/&oacute;/g, "o")
    .replace(/&aacute;/g, "a")
    .replace(/&eacute;/g, "e")
    .replace(/&iacute;/g, "i")
    .replace(/&uacute;/g, "u")
    .replace(/&ntilde;/g, "n")
    .replace(/&amp;/g, "&");
}

function normalizeText(value) {
  return String(value || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

function candidateUrls({ teamId, categoryId, categoryName }) {
  const params = [
    `team=${teamId}`,
    `team_id=${teamId}`,
    `teamId=${teamId}`,
    `home_team=${teamId}`,
    `away_team=${teamId}`,
  ];
  const categoryParams = Number.isInteger(categoryId)
    ? [`category=${categoryId}`, `category_id=${categoryId}`]
    : categoryName
      ? [`category=${encodeURIComponent(categoryName)}`]
      : [];

  const urls = [];
  for (const param of params) {
    for (const categoryParam of categoryParams) {
      urls.push(`${LUD_API_BASE}/matches/?${param}&${categoryParam}&limit=250`);
    }
    urls.push(`${LUD_API_BASE}/matches/?${param}&limit=250`);
  }
  urls.push(
    `${LUD_API_BASE}/teams/${teamId}/matches/`,
    `${LUD_API_BASE}/teams/${teamId}/fixtures/`,
    `${LUD_API_BASE}/matches/?limit=250`
  );
  return [...new Set(urls)];
}

async function candidatePhaseUrls(categoryName, teamId) {
  if (!categoryName) return [];
  const [teamPhases, seasons] = await Promise.all([
    Number.isInteger(teamId)
      ? fetchJson(`/teams/${teamId}/`, 5000)
      .then((team) => team?.phases ?? [])
        .catch(() => [])
      : Promise.resolve([]),
    fetchJson("/tournaments/selector/", 5000).catch(() => []),
  ]);
  const urls = [];
  for (const phase of teamPhases) {
    const haystack = [
      phase.name,
      phase.tournament,
      phase.tournament_name,
      phase.category,
      phase.category_name,
      phase.season,
    ].join(" ");
    if (categoryMatches(haystack, categoryName) && Number.isInteger(Number(phase.id))) {
      urls.push(`${LUD_API_BASE}/phases/${Number(phase.id)}/matches/`);
    }
  }
  const categories = seasons?.[0]?.categories ?? [];
  for (const category of categories) {
    if (!categoryMatches(category?.name, categoryName)) continue;
    for (const division of category.divisions ?? []) {
      for (const phase of division.phases ?? []) {
        if (Number.isInteger(Number(phase.id))) {
          urls.push(`${LUD_API_BASE}/phases/${Number(phase.id)}/matches/`);
        }
      }
    }
  }
  return [...new Set(urls)];
}

async function fetchJson(path, timeoutMs = 7000) {
  return fetchLeagueJson(path, timeoutMs);
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

function extractRows(raw) {
  if (Array.isArray(raw)) return raw;
  if (!raw || typeof raw !== "object") return [];
  for (const key of ["results", "matches", "fixtures", "data", "items"]) {
    if (Array.isArray(raw[key])) return raw[key];
  }
  return [];
}

function normalizeMatch(row, teamId) {
  const home = normalizeTeam(row.home_team ?? row.homeTeam ?? row.local_team ?? row.localTeam ?? row.team_home);
  const away = normalizeTeam(row.away_team ?? row.awayTeam ?? row.visitor_team ?? row.visitorTeam ?? row.team_away);
  const category =
    row.category ??
    row.phase ??
    row.division ??
    row.age_category ??
    row.tournament_category ??
    row.group ??
    {};
  const categoryName =
    text(category.tournament_name) ||
    text(category.category_name) ||
    text(category.name) ||
    text(category.category_name) ||
    text(category.title) ||
    text(category) ||
    text(row.category_name) ||
    text(row.categoryName) ||
    text(row.phase?.category_name);
  const categoryId =
    number(category.id) ??
    number(row.category_id) ??
    number(row.categoryId) ??
    null;
  const phaseId = number(row.phase?.id) ?? number(row.phase_id) ?? null;
  const date =
    text(row.date) ||
    text(row.fecha) ||
    text(row.match_date) ||
    text(row.matchDate) ||
    text(row.fixture_date) ||
    text(row.scheduled_date) ||
    text(row.kickoff) ||
    text(row.starts_at) ||
    text(row.datetime) ||
    text(row.start_time);
  const homeId = home.id ?? number(row.home_team_id) ?? number(row.homeTeamId);
  const awayId = away.id ?? number(row.away_team_id) ?? number(row.awayTeamId);
  const homeName = home.name || text(row.home_team_name) || text(row.homeName);
  const awayName = away.name || text(row.away_team_name) || text(row.awayName);
  const isHome = homeId === teamId;
  const opponentName = isHome ? awayName : awayId === teamId ? homeName : "";

  return {
    id: text(row.id) || `${teamId}-${date}-${homeName}-${awayName}`,
    date: normalizeDate(date),
    rawDate: date,
    competition:
      text(row.competition?.name) ||
      text(row.tournament?.name) ||
      text(row.league?.name) ||
      text(row.phase?.tournament_name) ||
      text(row.competition) ||
      "",
    categoryId,
    phaseId,
    categoryName,
    homeTeamId: homeId,
    homeTeamName: homeName,
    awayTeamId: awayId,
    awayTeamName: awayName,
    opponentTeamId: isHome ? awayId : awayId === teamId ? homeId : null,
    opponentName,
    homeScore: number(row.home_score) ?? number(row.homeScore),
    awayScore: number(row.away_score) ?? number(row.awayScore),
    venue: text(row.venue?.name) || text(row.field) || text(row.venue) || "",
    round:
      text(row.round?.name) ||
      text(row.round?.number ? `Fecha ${row.round.number}` : "") ||
      text(row.round) ||
      text(row.matchday) ||
      "",
    status: text(row.status) || text(row.state) || "",
    sourcePayload: row,
  };
}

function normalizeTeam(value) {
  if (!value || typeof value !== "object") {
    return { id: number(value), name: text(value) };
  }
  return {
    id: number(value.id) ?? number(value.team_id),
    name: text(value.name) || text(value.display_name) || text(value.short_name),
  };
}

function publicMatch(match) {
  const { sourcePayload, ...safeMatch } = match;
  return safeMatch;
}

function isPlayedResult(match) {
  if (!match.date || match.homeScore === null || match.awayScore === null) {
    return false;
  }
  const status = normalize(match.status);
  if (
    status.includes("programad") ||
    status.includes("proximo") ||
    status.includes("pendiente") ||
    status.includes("fixture")
  ) {
    return false;
  }
  if (status.includes("jugado") || status.includes("final")) return true;
  if (match.homeScore === 0 && match.awayScore === 0) return false;
  return new Date(`${match.date}T00:00:00Z`).getTime() < Date.now();
}

function chooseBetterEmptyResult(current, next) {
  if (!current) return next;
  const currentScore =
    current.fixtureDiagnostics.categoryRows * 4 + current.fixtureDiagnostics.rawRows;
  const nextScore =
    next.fixtureDiagnostics.categoryRows * 4 + next.fixtureDiagnostics.rawRows;
  return nextScore > currentScore ? next : current;
}

function safeUrl(url) {
  return String(url).replace(LUD_API_BASE, "/api");
}

function isRelevant(match, teamId, categoryId, categoryName) {
  const teamMatches = match.homeTeamId === teamId || match.awayTeamId === teamId;
  if (!teamMatches) return false;
  const hasCategoryFilter = Number.isInteger(categoryId) || Boolean(categoryName);
  if (Number.isInteger(categoryId) && match.categoryId === categoryId) {
    return true;
  }
  const requestedCategory = categoryName || categoryLabelFromId(categoryId);
  if (requestedCategory) {
    return categoryMatches(
      [
        match.categoryName,
        match.competition,
        match.round,
        match.status,
        text(match.sourcePayload?.category_name),
        text(match.sourcePayload?.categoryName),
        text(match.sourcePayload?.division),
        text(match.sourcePayload?.age_category),
        text(match.sourcePayload?.tournament_category),
        text(match.sourcePayload?.group),
      ].join(" "),
      requestedCategory
    );
  }
  return !hasCategoryFilter;
}

function categoryMatches(source, requestedCategory) {
  const requested = normalizeCategoryName(requestedCategory);
  const haystack = normalizeCategoryName(source);
  if (!requested || !haystack) return false;

  const requestedSub = requested.match(/sub(\d+)/)?.[1];
  if (requestedSub) {
    return haystack.includes(`sub${requestedSub}`);
  }

  if (requested.includes("mayores")) {
    return (
      haystack.includes("mayores") ||
      haystack.includes("primera") ||
      haystack.includes("mayor")
    );
  }

  if (requested.includes("reserva")) return haystack.includes("reserva");
  if (requested.includes("master")) return haystack.includes("master");
  if (requested.includes("presenior")) {
    return haystack.includes("presenior") || haystack.includes("pre-senior");
  }

  return haystack.includes(requested);
}

function isUpcoming(match, horizonDays) {
  const date = Date.parse(match.date || match.rawDate || "");
  if (Number.isNaN(date)) return false;
  const now = new Date();
  now.setHours(0, 0, 0, 0);
  const horizon = new Date(now);
  horizon.setDate(horizon.getDate() + horizonDays);
  return date >= now.getTime() && date <= horizon.getTime();
}

function normalizeDate(value) {
  const textValue = text(value);
  if (!textValue) return "";

  const isoLike = Date.parse(textValue);
  if (/^\d{4}-\d{1,2}-\d{1,2}/.test(textValue) && !Number.isNaN(isoLike)) {
    return new Date(isoLike).toISOString();
  }

  const uyDate = textValue.match(/\b(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2,4})\b/);
  if (uyDate) {
    const day = Number(uyDate[1]);
    const month = Number(uyDate[2]);
    const year = Number(uyDate[3].length === 2 ? `20${uyDate[3]}` : uyDate[3]);
    if (validDateParts({ day, month, year })) {
      return new Date(Date.UTC(year, month - 1, day, 12, 0, 0)).toISOString();
    }
  }

  if (!Number.isNaN(isoLike)) {
    return new Date(isoLike).toISOString();
  }

  return "";
}

function validDateParts({ day, month, year }) {
  if (!Number.isInteger(day) || !Number.isInteger(month) || !Number.isInteger(year)) {
    return false;
  }
  if (year < 2020 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function text(value) {
  if (value == null) return "";
  if (typeof value === "string" || typeof value === "number") {
    return String(value).trim();
  }
  return "";
}

function number(value) {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function normalize(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, "-");
}

function normalizeCategoryName(value) {
  return normalize(value)
    .replace(/\bsub[-\s]?/g, "sub")
    .replace(/\bu[-\s]?/g, "sub")
    .replace(/\bmayor(?:es)?\b/g, "mayores")
    .replace(/categoria-/g, "")
    .replace(/division-/g, "");
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

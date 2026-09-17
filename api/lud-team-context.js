import { createClient } from "@supabase/supabase-js";

const LUD_API_BASE = "https://lud-backend-ld7d.onrender.com/api";

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

  let teamResponse;
  let categoriesResponse;
  let seasonPlayersResponse;
  try {
    [teamResponse, categoriesResponse, seasonPlayersResponse] =
      await Promise.all([
        fetch(`${LUD_API_BASE}/teams/${teamId}/`, {
          signal: AbortSignal.timeout(10000),
        }),
        fetch(`${LUD_API_BASE}/teams/${teamId}/categories/`, {
          signal: AbortSignal.timeout(10000),
        }),
        fetch(`${LUD_API_BASE}/teams/${teamId}/season-players/`, {
          signal: AbortSignal.timeout(10000),
        }),
      ]);
  } catch (error) {
    const cached = await loadCachedContext(teamId);
    if (cached) return res.status(200).json(cached);
    return res.status(502).json({
      error: "lud_unreachable",
      message: "No se pudo conectar con LUD Stats.",
      details: String(error?.message || error),
    });
  }

  if (!teamResponse.ok || !categoriesResponse.ok || !seasonPlayersResponse.ok) {
    const cached = await loadCachedContext(teamId);
    if (cached) return res.status(200).json(cached);
    return res.status(502).json({
      error: "lud_incomplete_response",
      message: "LUD Stats no respondio completo.",
      status: {
        team: teamResponse.status,
        categories: categoriesResponse.status,
        seasonPlayers: seasonPlayersResponse.status,
      },
    });
  }

  const team = await teamResponse.json();
  const rawCategories = await categoriesResponse.json();
  const seasonEntries = await seasonPlayersResponse.json();

  const latestYear = seasonEntries.reduce(
    (max, entry) => Math.max(max, Number(entry.season_year) || 0),
    0,
  );
  const latestYearByCategory = new Map();
  for (const entry of seasonEntries) {
    const key = normalize(entry.category);
    if (!key) continue;
    latestYearByCategory.set(
      key,
      Math.max(latestYearByCategory.get(key) ?? 0, Number(entry.season_year) || 0),
    );
  }
  const currentEntries = seasonEntries.filter((entry) => {
    const key = normalize(entry.category);
    return Number(entry.season_year) === (latestYearByCategory.get(key) ?? latestYear);
  });

  const categorySource = mergeCategories(rawCategories, currentEntries);
  const categories = categorySource.map((category) => {
    const entries = currentEntries.filter(
      (entry) => normalize(entry.category) === normalize(category.name),
    );
    const playerCount = new Set(
      entries.flatMap((entry) =>
        (entry.players ?? []).map((player) => Number(player.id)),
      ),
    ).size;

    return {
      id: `lud-cat-${teamId}-${category.id ?? normalize(category.name)}`,
      ludCategoryId: category.id ?? null,
      name: category.name,
      ageGroup: category.name,
      coachName: "",
      playerCount,
      currentFocus: "",
      seasonYear: latestYearByCategory.get(normalize(category.name)) ?? latestYear,
    };
  });

  const categoryByName = new Map(
    categories.map((category) => [normalize(category.name), category.id]),
  );
  const playersById = new Map();

  for (const entry of currentEntries) {
    const categoryId =
      categoryByName.get(normalize(entry.category)) ??
      `lud-cat-${teamId}-${normalize(entry.category)}`;

    for (const player of entry.players ?? []) {
      const playerId = Number(player.id);
      if (!Number.isInteger(playerId)) continue;
      const key = `${categoryId}-${playerId}`;
      const existing = playersById.get(key);
      playersById.set(key, {
        id: `lud-player-${playerId}-${normalize(entry.category)}`,
        ludPlayerId: playerId,
        categoryId: existing?.categoryId ?? categoryId,
        fullName: player.name ?? "",
        position: player.position ?? player.position_name ?? "",
        matches: Math.max(existing?.matches ?? 0, Number(player.matches) || 0),
        minutes: Math.max(existing?.minutes ?? 0, Number(player.minutes) || 0),
        goals: Math.max(existing?.goals ?? 0, Number(player.goals) || 0),
        assists: Math.max(existing?.assists ?? 0, Number(player.assists) || 0),
        yellowCards: Math.max(
          existing?.yellowCards ?? 0,
          Number(player.yellow_cards) || 0,
        ),
        redCards: Math.max(
          existing?.redCards ?? 0,
          Number(player.red_cards) || 0,
        ),
      });
    }
  }

  const players = Array.from(playersById.values()).sort((a, b) =>
    a.fullName.localeCompare(b.fullName),
  );

  await cacheContext(teamId, team, categorySource, currentEntries, players).catch(
    () => {},
  );

  res.setHeader("cache-control", "no-store, max-age=0");
  return res.status(200).json({
    team: {
      id: team.id,
      name: team.name,
      shortName: team.short_name ?? team.name,
      logoUrl: team.logo_url ?? null,
    },
    seasonYear: latestYear,
    source: "lud_live",
    syncedAt: new Date().toISOString(),
    categories,
    players,
  });
}

function normalize(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, "-");
}

function mergeCategories(rawCategories, entries) {
  const byName = new Map();
  for (const category of rawCategories) {
    if (!category?.name) continue;
    byName.set(normalize(category.name), category);
  }
  for (const entry of entries) {
    if (!entry?.category) continue;
    const key = normalize(entry.category);
    if (!byName.has(key)) {
      byName.set(key, { id: null, name: entry.category });
    }
  }
  return Array.from(byName.values()).sort((a, b) =>
    categorySortValue(a.name) - categorySortValue(b.name) ||
    String(a.name).localeCompare(String(b.name)),
  );
}

function categorySortValue(name) {
  const normalized = normalize(name);
  if (normalized.includes("mayores")) return 10;
  if (normalized.includes("reserva")) return 20;
  if (normalized.includes("sub-20") || normalized.includes("sub20")) return 30;
  if (normalized.includes("sub-18") || normalized.includes("sub18")) return 40;
  if (normalized.includes("sub-16") || normalized.includes("sub16")) return 50;
  if (normalized.includes("presenior") || normalized.includes("pre-senior")) return 60;
  if (normalized.includes("master")) return 70;
  return 99;
}

async function cacheContext(teamId, team, categorySource, entries, players) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return;
  }

  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );

  await supabase.from("lud_teams").upsert(
    {
      lud_team_id: teamId,
      name: team.name ?? `LUD ${teamId}`,
      short_name: team.short_name ?? null,
      logo_url: team.logo_url ?? null,
      season: entries[0]?.season_year?.toString() ?? null,
      source_payload: team,
    },
    { onConflict: "lud_team_id" },
  );

  await supabase.from("lud_team_categories").upsert(
    categorySource.map((category) => ({
      lud_team_id: teamId,
      lud_category_id: category.id ?? null,
      name: category.name,
      source_payload: category,
    })),
    { onConflict: "lud_team_id,name" },
  );

  // Requires a Supabase unique key on (lud_team_id, category_key, lud_player_id)
  // and a category_key column so multi-category players do not overwrite each
  // other in cache. Without that migration, Supabase will reject this upsert and
  // live data remains the source of truth.
  const playersResult = await supabase.from("lud_players").upsert(
    players.map((player) => ({
      lud_player_id: player.ludPlayerId,
      lud_team_id: teamId,
      category_key: normalize(player.categoryId || player.id),
      full_name: player.fullName,
      season: entries[0]?.season_year?.toString() ?? null,
      source_payload: player,
    })),
    { onConflict: "lud_team_id,category_key,lud_player_id" },
  );
  if (playersResult.error) throw playersResult.error;
}

async function loadCachedContext(teamId) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return null;
  }
  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );
  const [teamResult, categoriesResult, playersResult] = await Promise.all([
    supabase.from("lud_teams").select("name,short_name,logo_url,season").eq("lud_team_id", teamId).maybeSingle(),
    supabase.from("lud_team_categories").select("lud_category_id,name,source_payload").eq("lud_team_id", teamId).order("name"),
    supabase.from("lud_players").select("lud_player_id,full_name,source_payload").eq("lud_team_id", teamId).order("full_name"),
  ]);
  if (teamResult.error || categoriesResult.error || playersResult.error) return null;
  if (!teamResult.data || categoriesResult.data.length === 0) return null;

  const categories = categoriesResult.data.map((category) => ({
    id: `lud-cat-${teamId}-${category.lud_category_id ?? normalize(category.name)}`,
    ludCategoryId: category.lud_category_id,
    name: category.name,
    ageGroup: category.name,
    coachName: "",
    playerCount: 0,
    currentFocus: "",
    seasonYear: Number(teamResult.data.season) || 0,
  }));
  const validCategoryIds = new Set(categories.map((category) => category.id));
  const categoryNameById = new Map(
    categories.map((category) => [category.id, category.name]),
  );
  const players = playersResult.data.map((player) => {
    const payload = player.source_payload ?? {};
    const categoryId = validCategoryIds.has(payload.categoryId) ? payload.categoryId : "";
    const categoryName = categoryNameById.get(categoryId) ?? "";
    const cachedId = categoryName
      ? `lud-player-${player.lud_player_id}-${normalize(categoryName)}`
      : payload.id ?? `lud-player-${player.lud_player_id}`;
    return {
      ...payload,
      id: cachedId,
      ludPlayerId: player.lud_player_id,
      fullName: player.full_name,
      categoryId,
    };
  });
  for (const category of categories) {
    category.playerCount = players.filter((player) => player.categoryId === category.id).length;
  }
  return {
    team: {
      id: teamId,
      name: teamResult.data.name,
      shortName: teamResult.data.short_name ?? teamResult.data.name,
      logoUrl: teamResult.data.logo_url,
    },
    seasonYear: teamResult.data.season,
    source: "supabase_cache",
    syncedAt: null,
    categories,
    players,
  };
}

const LEAGUE_API_BASE = "https://lud-backend-ld7d.onrender.com/api";
const LUDFAN_SUPABASE_URL =
  process.env.LUDFAN_SUPABASE_URL || "https://tnhqnsinsqgmbggqwown.supabase.co";
const LUDFAN_SUPABASE_ANON_KEY =
  process.env.LUDFAN_SUPABASE_ANON_KEY ||
  "sb_publishable_q33jnJrrXmi4LFpXQ_ZRpw_TQaukr-G";

export async function fetchLeagueJson(pathOrUrl, timeoutMs = 3500) {
  const path = normalizeLeaguePath(pathOrUrl);
  const live = await fetchLive(path, timeoutMs).catch(() => null);
  if (live != null) return live;
  const cached = await fetchLudfanCache(path, timeoutMs).catch(() => null);
  if (cached != null) return cached;
  throw new Error(`league_unavailable:${path}`);
}

export function normalizeLeaguePath(pathOrUrl) {
  const value = String(pathOrUrl || "");
  if (value.startsWith(LEAGUE_API_BASE)) return value.slice(LEAGUE_API_BASE.length);
  if (value.startsWith("http")) {
    try {
      const parsed = new URL(value);
      return `${parsed.pathname.replace(/^\/api/, "")}${parsed.search}`;
    } catch (_) {
      return value;
    }
  }
  return value.startsWith("/") ? value : `/${value}`;
}

async function fetchLive(path, timeoutMs) {
  const response = await fetch(`${LEAGUE_API_BASE}${path}`, {
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`league ${response.status}: ${path}`);
  return response.json();
}

async function fetchLudfanCache(path, timeoutMs) {
  if (!LUDFAN_SUPABASE_URL || !LUDFAN_SUPABASE_ANON_KEY) return null;
  const cacheUrl = new URL(`${LUDFAN_SUPABASE_URL}/rest/v1/lud_cache`);
  cacheUrl.searchParams.set("path", `eq.${path}`);
  cacheUrl.searchParams.set("select", "payload");
  cacheUrl.searchParams.set("limit", "1");
  const response = await fetch(cacheUrl, {
    headers: {
      apikey: LUDFAN_SUPABASE_ANON_KEY,
      authorization: `Bearer ${LUDFAN_SUPABASE_ANON_KEY}`,
    },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`cache ${response.status}: ${path}`);
  const rows = await response.json();
  return rows?.[0]?.payload ?? null;
}

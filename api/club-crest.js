const FALLBACK_BY_TEAM = {
  120: "https://lud-escudos.s3.us-east-1.amazonaws.com/team-escudos/PLAYA_HONDA_UNIVERSITARIO.png",
};

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "GET") return res.status(405).end();

  const teamId = Number(req.query.teamId);
  const requestedUrl = String(req.query.url || "");
  const imageUrl = Number.isInteger(teamId)
    ? FALLBACK_BY_TEAM[teamId] || requestedUrl
    : requestedUrl;

  if (!imageUrl || !imageUrl.startsWith("https://lud-escudos.s3.us-east-1.amazonaws.com/")) {
    return res.status(400).json({ error: "invalid_crest_url" });
  }

  try {
    const response = await fetch(imageUrl, {
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) return res.status(response.status).end();
    const buffer = Buffer.from(await response.arrayBuffer());
    res.setHeader("content-type", response.headers.get("content-type") || "image/png");
    res.setHeader("cache-control", "public, max-age=86400, s-maxage=86400");
    return res.status(200).send(buffer);
  } catch (error) {
    return res.status(502).json({ error: "crest_unavailable" });
  }
}

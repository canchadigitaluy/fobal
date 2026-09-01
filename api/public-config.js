export default function handler(req, res) {
  res.setHeader("Cache-Control", "no-store, max-age=0");
  res.setHeader("Access-Control-Allow-Origin", "*");

  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const supabaseUrl = process.env.SUPABASE_URL || "";
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || "";
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error("[public-config] Missing Supabase public configuration", {
      hasUrl: Boolean(supabaseUrl),
      hasAnonKey: Boolean(supabaseAnonKey),
    });
    return res.status(503).json({
      error: "auth_not_configured",
      message: "La autenticacion no esta configurada en este entorno.",
    });
  }

  return res.status(200).json({
    supabaseUrl,
    supabaseAnonKey,
  });
}

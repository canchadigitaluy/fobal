import { createClient } from "@supabase/supabase-js";

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "POST, OPTIONS");
  res.setHeader("access-control-allow-headers", "authorization, content-type");
  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const required = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY"];
  if (required.some((key) => !process.env[key])) {
    return res.status(503).json({ error: "missing_configuration", message: "La gestion segura de categorias no esta configurada." });
  }
  const authorization = String(req.headers.authorization || "");
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!token) return res.status(401).json({ error: "not_authenticated" });

  const payload = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
  const clubId = String(payload?.clubId || "");
  const categoryId = String(payload?.categoryId || "");
  if (!clubId || !categoryId) {
    return res.status(400).json({ error: "invalid_request", message: "Falta club o categoria." });
  }

  const userClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return res.status(401).json({ error: "invalid_session" });

  const adminClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const { data: membership, error } = await adminClient
    .from("club_memberships")
    .select("role,status,category_ids,cantera_clubs(lud_team_id)")
    .eq("club_id", clubId)
    .eq("user_id", authData.user.id)
    .maybeSingle();
  if (error || !membership || membership.status !== "active") {
    return res.status(403).json({ error: "access_denied", message: "Tu acceso al club no esta activo." });
  }
  if (["platform_admin", "club_admin"].includes(membership.role)) {
    return res.status(200).json({ ok: true, categoryIds: [] });
  }
  const assigned = Array.isArray(membership.category_ids) ? membership.category_ids : [];
  if (assigned.length > 0) {
    if (!assigned.includes(categoryId)) {
      return res.status(403).json({ error: "category_denied", message: "Esa categoria no esta asignada a tu cuenta." });
    }
    return res.status(200).json({ ok: true, categoryIds: assigned });
  }
  const teamId = membership.cantera_clubs?.lud_team_id;
  if (teamId && !categoryId.startsWith(`lud-cat-${teamId}-`)) {
    return res.status(400).json({ error: "invalid_category", message: "La categoria no pertenece al club." });
  }
  const { error: updateError } = await adminClient
    .from("club_memberships")
    .update({ category_ids: [categoryId], updated_at: new Date().toISOString() })
    .eq("club_id", clubId)
    .eq("user_id", authData.user.id)
    .eq("status", "active");
  if (updateError) {
    return res.status(500).json({ error: "assignment_failed", message: "No se pudo fijar la categoria." });
  }
  return res.status(200).json({ ok: true, categoryIds: [categoryId] });
}

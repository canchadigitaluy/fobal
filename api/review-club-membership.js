import { createClient } from "@supabase/supabase-js";

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "POST, OPTIONS");
  res.setHeader("access-control-allow-headers", "authorization, content-type");
  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(503).json({ error: "missing_configuration", message: "La gestion segura de accesos no esta configurada." });
  }

  const authorization = String(req.headers.authorization || "");
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if (!token) return res.status(401).json({ error: "not_authenticated", message: "Inicia sesion para gestionar accesos." });

  const payload = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
  const clubId = String(payload?.clubId || "");
  const targetUserId = String(payload?.userId || "");
  const action = ["approve", "reject", "update"].includes(payload?.action) ? payload.action : "";
  const categoryIds = Array.isArray(payload?.categoryIds)
    ? [...new Set(payload.categoryIds.map(String).filter(Boolean))].slice(0, 2)
    : [];
  if (!clubId || !targetUserId || !action) {
    return res.status(400).json({ error: "invalid_request", message: "Faltan datos para revisar la solicitud." });
  }

  const userClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) {
    return res.status(401).json({ error: "invalid_session", message: "Tu sesion vencio. Vuelve a ingresar." });
  }
  const { data: reviewer, error: reviewerError } = await userClient
    .from("club_memberships")
    .select("role,status")
    .eq("club_id", clubId)
    .eq("user_id", authData.user.id)
    .eq("status", "active")
    .maybeSingle();
  if (reviewerError || !reviewer || !["platform_admin", "club_admin"].includes(reviewer.role)) {
    return res.status(403).json({ error: "admin_required", message: "Solo un administrador activo del club puede revisar accesos." });
  }

  const adminClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data: targetMembership, error: targetError } = await adminClient
    .from("club_memberships")
    .select("role, cantera_clubs(lud_team_id)")
    .eq("club_id", clubId)
    .eq("user_id", targetUserId)
    .eq("status", action === "update" ? "active" : "pending")
    .maybeSingle();
  if (targetError || !targetMembership) {
    return res.status(409).json({ error: "request_not_pending", message: "La solicitud ya no esta pendiente. Actualiza la lista." });
  }
  const requiresCategory = ["coach", "assistant", "physical_trainer"].includes(targetMembership.role);
  if (["approve", "update"].includes(action) && requiresCategory && categoryIds.length === 0) {
    return res.status(400).json({ error: "category_required", message: "Asigna al menos una categoria antes de aprobar." });
  }
  const teamId = targetMembership.cantera_clubs?.lud_team_id;
  if (categoryIds.some((id) => teamId && !id.startsWith(`lud-cat-${teamId}-`))) {
    return res.status(400).json({ error: "invalid_category", message: "Hay una categoria que no pertenece al club." });
  }
  const { data: updated, error: updateError } = await adminClient
    .from("club_memberships")
    .update({
      status: action === "reject" ? "rejected" : "active",
      category_ids: action === "reject" ? [] : categoryIds,
      approved_by: authData.user.id,
      updated_at: new Date().toISOString(),
    })
    .eq("club_id", clubId)
    .eq("user_id", targetUserId)
    .eq("status", action === "update" ? "active" : "pending")
    .select("status")
    .maybeSingle();
  if (updateError || !updated) {
    return res.status(409).json({ error: "membership_changed", message: "El acceso cambio. Actualiza la lista." });
  }
  return res.status(200).json({ ok: true, status: updated.status });
}

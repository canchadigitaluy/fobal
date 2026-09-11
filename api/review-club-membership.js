import { createClient } from "@supabase/supabase-js";

// Two admin surfaces share this one function to stay under Vercel's
// Hobby-plan serverless function cap: per-club membership review
// (approve/reject/update) and the platform-wide account panel
// (list_accounts/ban/unban), gated separately below.
const CLUB_ACTIONS = new Set(["approve", "reject", "update"]);
const PLATFORM_ACTIONS = new Set(["list_accounts", "ban", "unban"]);

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
  const action = String(payload?.action || "");

  const userClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) {
    return res.status(401).json({ error: "invalid_session", message: "Tu sesion vencio. Vuelve a ingresar." });
  }

  if (PLATFORM_ACTIONS.has(action)) {
    return handlePlatformAction({ req, res, action, userClient, authData });
  }
  if (!CLUB_ACTIONS.has(action)) {
    return res.status(400).json({ error: "invalid_request", message: "Accion invalida." });
  }
  return handleClubMembershipAction({ req, res, action, payload, userClient, authData });
}

// --- per-club membership review (approve/reject/update) --------------------

async function handleClubMembershipAction({ req, res, action, payload, userClient, authData }) {
  const clubId = String(payload?.clubId || "");
  const targetUserId = String(payload?.userId || "");
  const categoryIds = Array.isArray(payload?.categoryIds)
    ? [...new Set(payload.categoryIds.map(String).filter(Boolean))].slice(0, 2)
    : [];
  if (!clubId || !targetUserId) {
    return res.status(400).json({ error: "invalid_request", message: "Faltan datos para revisar la solicitud." });
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

// --- platform-wide account panel (list_accounts/ban/unban) -----------------
// Manual clubs are isolated purely by auth.uid() (see club_documents RLS),
// so a per-club status flag would not actually block anything — banning the
// Supabase Auth user is the only enforcement point that works for both LUD
// and manual accounts alike.

async function handlePlatformAction({ req, res, action, userClient, authData }) {
  const { data: admin, error: adminError } = await userClient
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", authData.user.id)
    .maybeSingle();
  if (adminError || !admin) {
    return res.status(403).json({ error: "admin_required", message: "Esta cuenta no tiene permisos de administrador." });
  }

  const adminClient = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  if (action === "list_accounts") {
    try {
      const [profiles, manualClubs, memberships, authUsers] = await Promise.all([
        adminClient.from("user_profiles").select("id, email, full_name, created_at").order("created_at", { ascending: false }),
        adminClient.from("club_documents").select("user_id, club_id, data, updated_at"),
        adminClient.from("club_memberships").select("user_id, role, status, cantera_clubs(display_name)"),
        listAllUsers(adminClient),
      ]);
      if (profiles.error) throw profiles.error;
      if (manualClubs.error) throw manualClubs.error;
      if (memberships.error) throw memberships.error;

      const bannedByUser = new Map(authUsers.map((u) => [u.id, isBanned(u.banned_until)]));
      const manualByUser = new Map();
      for (const row of manualClubs.data || []) {
        const name = row.data?.name || "Club sin nombre";
        const list = manualByUser.get(row.user_id) || [];
        list.push({ clubId: row.club_id, name, updatedAt: row.updated_at });
        manualByUser.set(row.user_id, list);
      }
      const ludByUser = new Map();
      for (const row of memberships.data || []) {
        const name = row.cantera_clubs?.display_name || "Club de liga";
        const list = ludByUser.get(row.user_id) || [];
        list.push({ name, role: row.role, status: row.status });
        ludByUser.set(row.user_id, list);
      }
      const accounts = (profiles.data || []).map((p) => ({
        userId: p.id,
        email: p.email || "",
        fullName: p.full_name || "",
        createdAt: p.created_at,
        banned: bannedByUser.get(p.id) ?? false,
        manualClubs: manualByUser.get(p.id) || [],
        ludMemberships: ludByUser.get(p.id) || [],
      }));
      return res.status(200).json({ accounts });
    } catch (error) {
      return res.status(500).json({ error: "list_failed", message: String(error?.message || error) });
    }
  }

  // ban / unban
  const payload = req.body && typeof req.body === "object" ? req.body : {};
  const targetUserId = String(payload.userId || "");
  if (!targetUserId) {
    return res.status(400).json({ error: "invalid_request", message: "Falta el usuario." });
  }
  try {
    const { error } = await adminClient.auth.admin.updateUserById(targetUserId, {
      ban_duration: action === "ban" ? "876000h" : "none",
    });
    if (error) throw error;
    return res.status(200).json({ ok: true, banned: action === "ban" });
  } catch (error) {
    return res.status(500).json({ error: "update_failed", message: String(error?.message || error) });
  }
}

function isBanned(bannedUntil) {
  if (!bannedUntil) return false;
  const until = Date.parse(bannedUntil);
  return Number.isFinite(until) && until > Date.now();
}

async function listAllUsers(adminClient) {
  const users = [];
  let page = 1;
  for (let i = 0; i < 20; i++) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 200 });
    if (error || !data?.users?.length) break;
    users.push(...data.users);
    if (data.users.length < 200) break;
    page += 1;
  }
  return users;
}

import { createClient } from "@supabase/supabase-js";

// Three admin surfaces share this one function to stay under Vercel's
// Hobby-plan serverless function cap: per-club membership review
// (approve/reject/update), the platform-wide account panel
// (list_accounts/ban/unban), and manual-club collaborators
// (invite/revoke/list_collaborators/list_my_collaborations), each gated
// separately below.
const CLUB_ACTIONS = new Set(["approve", "reject", "update"]);
const PLATFORM_ACTIONS = new Set(["list_accounts", "ban", "unban", "platform_metrics"]);
const COLLABORATOR_ACTIONS = new Set([
  "invite_collaborator",
  "revoke_collaborator",
  "list_collaborators",
  "list_my_collaborations",
]);

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
  if (COLLABORATOR_ACTIONS.has(action)) {
    return handleCollaboratorAction({ res, action, payload, authData });
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
  const MAX_CATEGORY_IDS = 2;
  const requestedCategoryIds = Array.isArray(payload?.categoryIds)
    ? [...new Set(payload.categoryIds.map(String).filter(Boolean))]
    : [];
  if (!clubId || !targetUserId) {
    return res.status(400).json({ error: "invalid_request", message: "Faltan datos para revisar la solicitud." });
  }
  // Truncar en silencio hacia category_ids hacia dejaba al admin creyendo que
  // guardo todas las categorias pedidas cuando en verdad el DT perdia acceso
  // a las que sobraban. Mejor rechazar explicito que perder datos sin avisar.
  if (requestedCategoryIds.length > MAX_CATEGORY_IDS) {
    return res.status(400).json({
      error: "too_many_categories",
      message: `Un DT puede tener hasta ${MAX_CATEGORY_IDS} categorias asignadas.`,
      max: MAX_CATEGORY_IDS,
    });
  }
  const categoryIds = requestedCategoryIds;

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

  if (action === "platform_metrics") {
    try {
      const recentSince = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
      const [
        profilesCount,
        manualClubsCount,
        activeMemberships,
        collaboratorsCount,
        recentUsersCount,
        recentManualClubsCount,
        recentMembershipsCount,
      ] = await Promise.all([
        adminClient.from("user_profiles").select("id", { count: "exact", head: true }),
        adminClient.from("club_documents").select("club_id", { count: "exact", head: true }),
        adminClient.from("club_memberships").select("club_id").eq("status", "active"),
        adminClient
          .from("club_collaborators")
          .select("user_id", { count: "exact", head: true })
          .eq("status", "active"),
        adminClient
          .from("user_profiles")
          .select("id", { count: "exact", head: true })
          .gte("created_at", recentSince),
        adminClient
          .from("club_documents")
          .select("club_id", { count: "exact", head: true })
          .gte("updated_at", recentSince),
        adminClient
          .from("club_memberships")
          .select("id", { count: "exact", head: true })
          .gte("created_at", recentSince),
      ]);
      for (const result of [
        profilesCount,
        manualClubsCount,
        activeMemberships,
        collaboratorsCount,
        recentUsersCount,
        recentManualClubsCount,
        recentMembershipsCount,
      ]) {
        if (result.error) throw result.error;
      }
      const activeLudClubIds = new Set((activeMemberships.data || []).map((row) => row.club_id).filter(Boolean));
      return res.status(200).json({
        metrics: {
          activeUsers: profilesCount.count || 0,
          manualClubs: manualClubsCount.count || 0,
          activeLudClubs: activeLudClubIds.size,
          activeCollaborators: collaboratorsCount.count || 0,
          recentUsers: recentUsersCount.count || 0,
          recentManualClubs: recentManualClubsCount.count || 0,
          recentLudMemberships: recentMembershipsCount.count || 0,
          recentSince,
        },
      });
    } catch (error) {
      return res.status(500).json({ error: "metrics_failed", message: String(error?.message || error) });
    }
  }

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
        const categories = (row.data?.categories || [])
          .map((category) => category?.name)
          .filter((value) => typeof value === "string" && value.trim());
        const list = manualByUser.get(row.user_id) || [];
        list.push({ clubId: row.club_id, name, updatedAt: row.updated_at, categories });
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

// --- manual-club collaborators ----------------------------------------------
// Manual clubs have no row in cantera_clubs (that table is the LUD league
// registry only), so club_memberships can't be reused here — a separate
// club_collaborators table backs this, and club_documents' RLS was extended
// to also allow an active collaborator, on top of the original owner-only
// check, so every existing single-owner club keeps working unchanged.
const COLLABORATOR_ROLES = new Set(["coach", "assistant", "physical_trainer", "viewer"]);

async function handleCollaboratorAction({ res, action, payload, authData }) {
  const adminClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );
  const callerId = authData.user.id;

  if (action === "list_my_collaborations") {
    const { data, error } = await adminClient
      .from("club_collaborators")
      .select("club_id, role, status, owner_user_id")
      .eq("user_id", callerId)
      .eq("status", "active");
    if (error) return res.status(500).json({ error: "list_failed", message: String(error.message) });
    const clubIds = [...new Set((data || []).map((row) => row.club_id))];
    let names = {};
    if (clubIds.length > 0) {
      const { data: docs } = await adminClient
        .from("club_documents")
        .select("club_id, data")
        .in("club_id", clubIds);
      names = Object.fromEntries((docs || []).map((d) => [d.club_id, d.data?.name || "Club"]));
    }
    return res.status(200).json({
      collaborations: (data || []).map((row) => ({
        clubId: row.club_id,
        role: row.role,
        clubName: names[row.club_id] || "Club",
      })),
    });
  }

  const clubId = String(payload?.clubId || "");
  if (!clubId) return res.status(400).json({ error: "invalid_request", message: "Falta el club." });

  const { data: ownerDoc, error: ownerError } = await adminClient
    .from("club_documents")
    .select("user_id")
    .eq("club_id", clubId)
    .maybeSingle();
  if (ownerError || !ownerDoc) {
    return res.status(404).json({ error: "club_not_found", message: "No se encontro el club." });
  }
  const isOwner = ownerDoc.user_id === callerId;

  if (action === "list_collaborators") {
    if (!isOwner) {
      const { data: membership } = await adminClient
        .from("club_collaborators")
        .select("user_id")
        .eq("club_id", clubId)
        .eq("user_id", callerId)
        .eq("status", "active")
        .maybeSingle();
      if (!membership) return res.status(403).json({ error: "not_a_member", message: "No tenes acceso a este club." });
    }
    const { data, error } = await adminClient
      .from("club_collaborators")
      .select("user_id, role, status, invited_email, created_at")
      .eq("club_id", clubId)
      .neq("status", "revoked");
    if (error) return res.status(500).json({ error: "list_failed", message: String(error.message) });
    const userIds = (data || []).map((row) => row.user_id);
    let profiles = {};
    if (userIds.length > 0) {
      const { data: rows } = await adminClient
        .from("user_profiles")
        .select("id, email, full_name")
        .in("id", userIds);
      profiles = Object.fromEntries((rows || []).map((p) => [p.id, p]));
    }
    return res.status(200).json({
      collaborators: (data || []).map((row) => ({
        userId: row.user_id,
        role: row.role,
        email: profiles[row.user_id]?.email || row.invited_email || "",
        fullName: profiles[row.user_id]?.full_name || "",
      })),
    });
  }

  // invite_collaborator / revoke_collaborator: owner-only.
  if (!isOwner) {
    return res.status(403).json({ error: "owner_required", message: "Solo el dueno del club puede gestionar colaboradores." });
  }

  if (action === "invite_collaborator") {
    const email = String(payload?.email || "").trim().toLowerCase();
    const role = COLLABORATOR_ROLES.has(payload?.role) ? payload.role : "coach";
    if (!email) return res.status(400).json({ error: "invalid_request", message: "Falta el email." });
    const { data: target } = await adminClient
      .from("user_profiles")
      .select("id")
      .ilike("email", email)
      .maybeSingle();
    if (!target) {
      return res.status(404).json({
        error: "no_account",
        message: "Esa persona todavia no tiene una cuenta en fobal. Pedile que se registre y volve a invitarla.",
      });
    }
    if (target.id === callerId) {
      return res.status(400).json({ error: "self_invite", message: "Ya sos el dueno de este club." });
    }
    const { error } = await adminClient.from("club_collaborators").upsert(
      {
        club_id: clubId,
        owner_user_id: callerId,
        user_id: target.id,
        role,
        status: "active",
        invited_email: email,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "club_id,user_id" },
    );
    if (error) return res.status(500).json({ error: "invite_failed", message: String(error.message) });
    return res.status(200).json({ ok: true });
  }

  if (action === "revoke_collaborator") {
    const targetUserId = String(payload?.userId || "");
    if (!targetUserId) return res.status(400).json({ error: "invalid_request", message: "Falta el usuario." });
    const { error } = await adminClient
      .from("club_collaborators")
      .update({ status: "revoked", updated_at: new Date().toISOString() })
      .eq("club_id", clubId)
      .eq("user_id", targetUserId);
    if (error) return res.status(500).json({ error: "revoke_failed", message: String(error.message) });
    return res.status(200).json({ ok: true });
  }

  return res.status(400).json({ error: "invalid_request", message: "Accion invalida." });
}

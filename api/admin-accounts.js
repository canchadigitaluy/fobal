import { createClient } from "@supabase/supabase-js";

// Platform-wide admin endpoint: list every registered account (LUD + manual)
// and ban/unban one. Banning uses Supabase Auth's own ban mechanism (not a
// cosmetic status flag) so a revoked account genuinely loses access —
// manual clubs are isolated purely by auth.uid(), so an account-level ban
// is the only enforcement point that works for both LUD and manual clubs.

async function requirePlatformAdmin(req) {
  const authorization = String(req.headers.authorization || "");
  const token = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";
  if (!token) return { error: "not_authenticated", status: 401 };

  const userClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    },
  );
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) {
    return { error: "invalid_session", status: 401 };
  }
  const { data: admin, error: adminError } = await userClient
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", authData.user.id)
    .maybeSingle();
  if (adminError || !admin) {
    return { error: "admin_required", status: 403 };
  }
  return { userId: authData.user.id };
}

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, POST, OPTIONS");
  res.setHeader("access-control-allow-headers", "authorization, content-type");
  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });

  if (
    !process.env.SUPABASE_URL ||
    !process.env.SUPABASE_ANON_KEY ||
    !process.env.SUPABASE_SERVICE_ROLE_KEY
  ) {
    return res.status(503).json({
      error: "missing_configuration",
      message: "El panel de administracion no esta configurado.",
    });
  }

  const auth = await requirePlatformAdmin(req);
  if (auth.error) {
    return res.status(auth.status).json({
      error: auth.error,
      message:
        auth.error === "admin_required"
          ? "Esta cuenta no tiene permisos de administrador."
          : "Inicia sesion para administrar cuentas.",
    });
  }

  const adminClient = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_ROLE_KEY,
    { auth: { persistSession: false } },
  );

  if (req.method === "GET") {
    try {
      const [profiles, manualClubs, memberships, authUsers] = await Promise.all([
        adminClient
          .from("user_profiles")
          .select("id, email, full_name, created_at")
          .order("created_at", { ascending: false }),
        adminClient.from("club_documents").select("user_id, club_id, data, updated_at"),
        adminClient
          .from("club_memberships")
          .select("user_id, role, status, cantera_clubs(display_name)"),
        listAllUsers(adminClient),
      ]);
      if (profiles.error) throw profiles.error;
      if (manualClubs.error) throw manualClubs.error;
      if (memberships.error) throw memberships.error;

      const bannedByUser = new Map(
        authUsers.map((u) => [u.id, isBanned(u.banned_until)]),
      );
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
      return res.status(500).json({
        error: "list_failed",
        message: String(error?.message || error),
      });
    }
  }

  if (req.method === "POST") {
    const payload = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const targetUserId = String(payload?.userId || "");
    const action = ["ban", "unban"].includes(payload?.action) ? payload.action : "";
    if (!targetUserId || !action) {
      return res.status(400).json({ error: "invalid_request", message: "Faltan datos." });
    }
    try {
      const { error } = await adminClient.auth.admin.updateUserById(targetUserId, {
        // Supabase's ban field: a far-future duration effectively revokes
        // access; "none" clears it. No custom RLS flag needed — this is
        // Auth's own gate, checked on every request.
        ban_duration: action === "ban" ? "876000h" : "none",
      });
      if (error) throw error;
      return res.status(200).json({ ok: true, banned: action === "ban" });
    } catch (error) {
      return res.status(500).json({
        error: "update_failed",
        message: String(error?.message || error),
      });
    }
  }

  return res.status(405).json({ error: "method_not_allowed" });
}

function isBanned(bannedUntil) {
  if (!bannedUntil) return false;
  const until = Date.parse(bannedUntil);
  return Number.isFinite(until) && until > Date.now();
}

async function listAllUsers(adminClient) {
  const users = [];
  let page = 1;
  // Admin API paginates; 259 clubs give a sense of scale, one extra page
  // guard keeps this bounded even if the account list grows a lot.
  for (let i = 0; i < 20; i++) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage: 200,
    });
    if (error || !data?.users?.length) break;
    users.push(...data.users);
    if (data.users.length < 200) break;
    page += 1;
  }
  return users;
}

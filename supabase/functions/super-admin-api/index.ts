import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const allowedOrigins = new Set([
  "https://messageia.github.io",
  "http://localhost",
  "http://127.0.0.1",
]);

function corsFor(req: Request) {
  const origin = req.headers.get("origin");
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-super-admin-session",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Vary": "Origin",
  };
  if (
    origin &&
    (
      allowedOrigins.has(origin) ||
      origin.startsWith("http://localhost:") ||
      origin.startsWith("http://127.0.0.1:")
    )
  ) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

const te = new TextEncoder();
const json = (req: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsFor(req), "content-type": "application/json" },
  });

function b64ToBytes(value: string) {
  const raw = atob(value);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}
function bytesToB64Url(bytes: Uint8Array) {
  let raw = "";
  for (const b of bytes) raw += String.fromCharCode(b);
  return btoa(raw).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
async function sha256Hex(value: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", te.encode(value)));
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function verifyPin(code: string, saltB64: string, hashB64: string, iterations: number) {
  const keyMaterial = await crypto.subtle.importKey("raw", te.encode(code), "PBKDF2", false, ["deriveBits"]);
  const bits = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: b64ToBytes(saltB64), iterations },
    keyMaterial,
    256,
  ));
  const expected = b64ToBytes(hashB64);
  if (bits.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < bits.length; i++) diff |= bits[i] ^ expected[i];
  return diff === 0;
}
function normalizeCode(value: string) {
  return value.trim().toUpperCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 20);
}
function normalizeUser(value: string) {
  return value.trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}
function randomHex(bytes = 3) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)))
    .map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

function isStrongPassword(value: string) {
  return value.length >= 10 &&
    /[a-z]/.test(value) &&
    /[A-Z]/.test(value) &&
    /[0-9]/.test(value);
}

// Paginer côté serveur : la limite PostgREST de 1000 lignes ne doit jamais
// dissimuler les demandes, écoles ou comptes plus anciens.
async function readAll(query: any, pageSize = 500): Promise<any[]> {
  const rows: any[] = [];
  for (let page = 0; page < 40; page++) {
    const { data, error } = await query.range(page * pageSize, (page + 1) * pageSize - 1);
    if (error) throw error;
    const batch = data ?? [];
    rows.push(...batch);
    if (batch.length < pageSize) return rows;
  }
  throw new Error("results_limit_exceeded");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(req) });
  if (req.method !== "POST") return json(req, { error: "method_not_allowed" }, 405);

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 65536) {
    return json(req, { error: "payload_too_large" }, 413);
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const server = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "login") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const code = String(body.code ?? "").trim();
      if (!email || !code) return json(req, { error: "identifiants_requis" }, 400);

      const { data: admin, error } = await server.from("platform_super_admins")
        .select("id,user_id,email,pin_salt,pin_hash,pin_iterations,active,failed_attempts,locked_until")
        .eq("email", email).maybeSingle();
      if (error) return json(req, { error: "login_unavailable" }, 500);
      if (!admin || !admin.active) return json(req, { error: "acces_refuse" }, 403);

      const now = new Date();
      if (admin.locked_until && new Date(admin.locked_until) > now) {
        return json(req, { error: "compte_temporairement_verrouille", locked_until: admin.locked_until }, 429);
      }

      const ok = await verifyPin(code, admin.pin_salt, admin.pin_hash, Number(admin.pin_iterations));
      if (!ok) {
        const attempts = Number(admin.failed_attempts ?? 0) + 1;
        const lockedUntil = attempts >= 5 ? new Date(Date.now() + 15 * 60 * 1000).toISOString() : null;
        await server.from("platform_super_admins").update({
          failed_attempts: attempts >= 5 ? 0 : attempts,
          locked_until: lockedUntil,
          updated_at: new Date().toISOString(),
        }).eq("id", admin.id);
        await server.from("platform_activity_events").insert({
          organization_id: null,
          actor_user_id: admin.user_id,
          event_type: "super_admin_login_failed",
          module: "super_admin",
          message: "Tentative de connexion Super Admin refusée",
          metadata: { attempts, locked: lockedUntil != null },
        });
        return json(req, { error: "identifiants_invalides" }, 401);
      }

      const token = bytesToB64Url(crypto.getRandomValues(new Uint8Array(32)));
      const tokenHash = await sha256Hex(token);
      const expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
      await server.from("platform_super_admins").update({
        failed_attempts: 0, locked_until: null, updated_at: new Date().toISOString(),
      }).eq("id", admin.id);
      await server.from("platform_super_admin_sessions")
        .update({ revoked_at: new Date().toISOString() })
        .eq("super_admin_id", admin.id)
        .is("revoked_at", null);
      const { error: sessionError } = await server.from("platform_super_admin_sessions").insert({
        super_admin_id: admin.id,
        token_hash: tokenHash,
        expires_at: expiresAt,
      });
      if (sessionError) return json(req, { error: "session_creation_failed" }, 500);

      await server.from("platform_activity_events").insert({
        organization_id: null,
        actor_user_id: admin.user_id,
        event_type: "super_admin_login",
        module: "super_admin",
        message: "Connexion au tableau de bord Super Admin",
        metadata: {},
      });

      return json(req, { token, expires_at: expiresAt, email: admin.email });
    }

    const token = req.headers.get("x-super-admin-session") ?? "";
    if (!token) return json(req, { error: "session_requise" }, 401);
    const tokenHash = await sha256Hex(token);
    const { data: session } = await server.from("platform_super_admin_sessions")
      .select("id,super_admin_id,expires_at,revoked_at")
      .eq("token_hash", tokenHash)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (!session) return json(req, { error: "session_invalide_ou_expiree" }, 401);

    const { data: admin } = await server.from("platform_super_admins")
      .select("id,user_id,email,active")
      .eq("id", session.super_admin_id).eq("active", true).maybeSingle();
    if (!admin) return json(req, { error: "acces_refuse" }, 403);
    await server.from("platform_super_admin_sessions")
      .update({ last_seen_at: new Date().toISOString() }).eq("id", session.id);

    if (action === "logout") {
      await server.from("platform_super_admin_sessions")
        .update({ revoked_at: new Date().toISOString() }).eq("id", session.id);
      return json(req, { ok: true });
    }

    if (action === "overview") {
      const [orgs, members, devices, syncs, requests, eventsRes] = await Promise.all([
        readAll(server.from("organizations").select(
          "id,code,name,active,subscription_status,subscription_cycle,subscription_started_at,subscription_expires_at,subscription_confirmed_at,created_at,updated_at"
        ).order("id")),
        readAll(server.from("organization_members").select(
          "id,organization_id,user_id,role,username,display_name,active,status,must_change_password,created_at"
        ).order("id")),
        readAll(server.from("devices").select(
          "id,organization_id,user_id,device_key,platform,app_version,last_seen_at,created_at"
        ).order("id")),
        readAll(server.from("sync_metadata").select(
          "organization_id,revision,size_bytes,updated_at,uploaded_at,current_path"
        ).order("organization_id")),
        readAll(server.from("admin_registration_requests").select(
          "id,user_id,email,display_name,school_name,preferred_code,status,created_at,reviewed_at,review_note"
        ).eq("status", "pending").order("created_at", { ascending: true }).order("id")),
        server.from("platform_activity_events")
          .select("id,organization_id,actor_user_id,event_type,module,message,metadata,created_at")
          .order("created_at", { ascending: false }).limit(150),
      ]);
      if (eventsRes.error) return json(req, { error: eventsRes.error.message }, 500);
      const now = Date.now();
      const events = eventsRes.data ?? [];
      const organizations = orgs.map((org) => {
        const om = members.filter((m) => m.organization_id === org.id);
        const od = devices.filter((d) => d.organization_id === org.id);
        const sync = syncs.find((row) => row.organization_id === org.id) ?? null;
        const paidUntil = org.subscription_expires_at ? Date.parse(org.subscription_expires_at) : 0;
        const subscriptionEffectiveStatus = !org.active ? "suspended"
          : org.subscription_status === "legacy" ? "legacy"
          : org.subscription_status === "active" && paidUntil > now ? "active" : "expired";
        const syncEvent = events.find((ev) => ev.organization_id === org.id
          && ["sync_error", "sync_uploaded", "sync_restored"].includes(ev.event_type));
        return {
          subscription_effective_status: subscriptionEffectiveStatus,
          ...org,
          admin: om.find((m) => m.role === "admin") ?? null,
          managers: om.filter((m) => m.role === "manager"),
          device_count: od.length,
          online_device_count: od.filter((d) => d.last_seen_at
            && now - new Date(d.last_seen_at).getTime() <= 120000).length,
          last_seen_at: od.reduce((acc: string | null, d) =>
            !acc || (d.last_seen_at && d.last_seen_at > acc) ? (d.last_seen_at ?? acc) : acc, null),
          sync, latest_sync_event: syncEvent ?? null,
        };
      });
      const recentActivity = events.map((event) => {
        const org = organizations.find((o) => o.id === event.organization_id);
        return { ...event, organization_name: org?.name ?? null, organization_code: org?.code ?? null };
      });
      const active = organizations.filter((o) => o.subscription_effective_status === "active");
      return json(req, {
        generated_at: new Date().toISOString(),
        totals: {
          schools: organizations.length,
          active_schools: organizations.filter((o) => o.active).length,
          managers: members.filter((m) => m.role === "manager" && m.active && m.status === "active").length,
          devices: devices.length,
          online_devices: devices.filter((d) => d.last_seen_at
            && now - new Date(d.last_seen_at).getTime() <= 120000).length,
          subscriptions_active: active.length,
          subscriptions_expired: organizations.filter((o) => o.subscription_effective_status === "expired").length,
          requests_pending: requests.length,
          sync_errors_recent: organizations.filter((o) => o.latest_sync_event?.event_type === "sync_error").length,
        },
        organizations,
        pending_requests: requests,
        recent_activity: recentActivity,
      });
    }

    if (action === "organization_detail") {
      const organizationId = String(body.organization_id ?? "");
      if (!organizationId) return json(req, { error: "organization_id_requis" }, 400);
      const [org, members, devices, sync, payments, events] = await Promise.all([
        server.from("organizations").select(
          "id,code,name,active,subscription_status,subscription_cycle,subscription_started_at,subscription_expires_at,subscription_confirmed_at,created_at,updated_at"
        ).eq("id", organizationId).maybeSingle(),
        server.from("organization_members").select(
          "id,organization_id,role,username,display_name,active,status,must_change_password,created_at"
        ).eq("organization_id", organizationId).order("role"),
        server.from("devices").select(
          "id,user_id,device_key,platform,app_version,last_seen_at,created_at"
        ).eq("organization_id", organizationId).order("last_seen_at", { ascending: false }),
        server.from("sync_metadata").select(
          "revision,size_bytes,updated_at,uploaded_at,checksum_sha256"
        ).eq("organization_id", organizationId).maybeSingle(),
        server.from("subscription_payments").select(
          "id,cycle,starts_at,expires_at,confirmed_at,reference,event_type"
        ).eq("organization_id", organizationId).order("confirmed_at", { ascending: false }).limit(100),
        server.from("platform_activity_events").select(
          "id,event_type,module,message,created_at"
        ).eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(50),
      ]);
      for (const result of [org, members, devices, sync, payments, events]) {
        if (result.error) return json(req, { error: result.error.message }, 500);
      }
      if (!org.data) return json(req, { error: "ecole_introuvable" }, 404);
      return json(req, {
        organization: org.data,
        members: members.data ?? [], devices: devices.data ?? [],
        sync: sync.data, subscription_payments: payments.data ?? [],
        events: events.data ?? [],
      });
    }

    if (action === "registration_history") {
      const offset = Math.max(0, Math.min(10000, Number(body.offset ?? 0) || 0));
      const { data, error } = await server.from("admin_registration_requests").select(
        "id,email,display_name,school_name,status,created_at,reviewed_at,review_note,organization_id"
      ).in("status", ["approved", "rejected"])
        .order("reviewed_at", { ascending: false }).range(offset, offset + 99);
      if (error) return json(req, { error: error.message }, 500);
      return json(req, { items: data ?? [], offset, has_more: (data ?? []).length === 100 });
    }

    if (action === "activity_history") {
      const organizationId = String(body.organization_id ?? "").trim();
      const offset = Math.max(0, Math.min(10000, Number(body.offset ?? 0) || 0));
      let query = server.from("platform_activity_events")
        .select("id,organization_id,actor_user_id,event_type,module,message,created_at")
        .order("created_at", { ascending: false });
      if (organizationId) query = query.eq("organization_id", organizationId);
      const { data, error } = await query.range(offset, offset + 99);
      if (error) return json(req, { error: error.message }, 500);
      return json(req, { items: data ?? [], offset, has_more: (data ?? []).length === 100 });
    }

    if (action === "set_manager_active") {
      const organizationId = String(body.organization_id ?? "");
      const memberId = String(body.member_id ?? "");
      const active = body.active === true;
      if (!organizationId || !memberId) return json(req, { error: "identifiant_requis" }, 400);
      const { data: member, error: lookupError } = await server.from("organization_members")
        .select("id,user_id,display_name,role,active,organization_id")
        .eq("id", memberId).eq("organization_id", organizationId).maybeSingle();
      if (lookupError || !member || member.role !== "manager") {
        return json(req, { error: "gestionnaire_introuvable" }, 404);
      }
      const { error } = await server.from("organization_members")
        .update({ active, status: active ? "active" : "disabled", updated_at: new Date().toISOString() })
        .eq("id", memberId).eq("organization_id", organizationId).eq("role", "manager");
      if (error) return json(req, { error: error.message }, 409);
      await server.from("platform_activity_events").insert({
        organization_id: organizationId, actor_user_id: admin.user_id,
        event_type: active ? "manager_activated" : "manager_disabled",
        module: "security", message: active ? "Gestionnaire réactivé" : "Gestionnaire désactivé",
        metadata: { member_id: memberId },
      });
      return json(req, { ok: true });
    }

    if (action === "reset_manager_password") {
      const organizationId = String(body.organization_id ?? "");
      const memberId = String(body.member_id ?? "");
      const password = String(body.temporary_password ?? "");
      if (!organizationId || !memberId || !isStrongPassword(password)) {
        return json(req, { error: "mot_de_passe_ou_compte_invalide" }, 400);
      }
      const { data: member, error: lookupError } = await server.from("organization_members")
        .select("id,user_id,role").eq("id", memberId)
        .eq("organization_id", organizationId).maybeSingle();
      if (lookupError || !member || member.role !== "manager") {
        return json(req, { error: "gestionnaire_introuvable" }, 404);
      }
      const { error: changeError } = await server.auth.admin.updateUserById(member.user_id, { password });
      if (changeError) return json(req, { error: changeError.message }, 409);
      const { error: memberError } = await server.from("organization_members")
        .update({ must_change_password: true, updated_at: new Date().toISOString() })
        .eq("id", memberId).eq("organization_id", organizationId);
      if (memberError) return json(req, { error: "password_changed_membership_update_failed" }, 500);
      await server.from("platform_activity_events").insert({
        organization_id: organizationId, actor_user_id: admin.user_id,
        event_type: "manager_password_reset", module: "security",
        message: "Mot de passe provisoire du gestionnaire renouvelé",
        metadata: { member_id: memberId },
      });
      return json(req, { ok: true });
    }

    if (action === "approve_request") {
      const requestId = String(body.request_id ?? "");
      const cycle = String(body.subscription_cycle ?? "");
      if (!requestId || !["monthly","annual"].includes(cycle)) return json(req, { error: "demande_ou_abonnement_invalide" }, 400);
      const { data: request, error: requestError } = await server.from("admin_registration_requests")
        .select("id,user_id,email,status").eq("id", requestId).eq("status", "pending").maybeSingle();
      if (requestError || !request) return json(req, { error: "demande_introuvable" }, 404);
      const { data: profile, error: profileError } = await server.auth.admin.getUserById(request.user_id);
      if (profileError || !profile.user || !profile.user.email_confirmed_at
          || profile.user.email?.toLowerCase() !== request.email.toLowerCase()) {
        return json(req, { error: "email_administrateur_non_confirme" }, 409);
      }
      const { data, error } = await server.rpc("admin_approve_registration", {
        p_request_id: requestId, p_cycle: cycle, p_approver: admin.user_id,
      });
      if (error) return json(req, { error: error.message }, 409);
      await server.auth.admin.updateUserById(request.user_id, {
        app_metadata: { gesapp_role: "admin", organization_id: data.organization_id },
      });
      return json(req, { ok: true, organization: data });
    }

    if (action === "reject_request") {
      const requestId = String(body.request_id ?? "");
      if (!requestId) return json(req, { error: "demande_introuvable" }, 400);
      const { data, error } = await server.rpc("admin_reject_registration", {
        p_request_id: requestId, p_reviewer: admin.user_id,
        p_note: String(body.note ?? "").slice(0, 500),
      });
      if (error) return json(req, { error: error.message }, 409);
      return json(req, data);
    }

    if (action === "renew_subscription") {
      const organizationId = String(body.organization_id ?? "");
      const cycle = String(body.subscription_cycle ?? "");
      // La référence est conservée pour compatibilité avec d'anciens clients.
      // La nouvelle console exige son renseignement avant l'activation.
      const reference = String(body.reference ?? "").trim().slice(0, 200);
      if (!organizationId || !["monthly","annual"].includes(cycle)) return json(req, { error: "abonnement_invalide" }, 400);
      if (reference) {
        const { data: duplicate, error: duplicateError } = await server
          .from("subscription_payments").select("id")
          .eq("organization_id", organizationId).eq("reference", reference).limit(1);
        if (duplicateError) return json(req, { error: duplicateError.message }, 500);
        if ((duplicate ?? []).length > 0) {
          return json(req, { error: "reference_paiement_deja_utilisee" }, 409);
        }
      }
      const { data, error } = await server.rpc("admin_confirm_subscription", {
        p_organization_id: organizationId, p_cycle: cycle,
        p_approver: admin.user_id, p_reference: reference,
      });
      if (error) return json(req, { error: error.message }, 409);
      return json(req, { ok: true, subscription: data });
    }

    if (action === "create_school") {
      const name = String(body.name ?? "").trim();
      const preferredCode = normalizeCode(String(body.code ?? ""));
      const adminEmail = String(body.admin_email ?? "").trim().toLowerCase();
      const adminName = String(body.admin_name ?? "").trim();
      const adminPassword = String(body.admin_password ?? "");
      const managerUsername = normalizeUser(String(body.manager_username ?? ""));
      const managerName = String(body.manager_name ?? "").trim();
      const managerPassword = String(body.manager_password ?? "");
      // Anciennes versions du tableau Super Admin choisissent implicitement
      // le cycle mensuel. Les nouveaux formulaires fournissent le choix explicite.
      const subscriptionCycle = String(body.subscription_cycle ?? "").trim() || "monthly";
      if (!["monthly","annual"].includes(subscriptionCycle)) return json(req, { error: "abonnement_invalide" }, 400);

      if (name.length < 3 || !adminEmail.includes("@") || adminName.length < 2 || !isStrongPassword(adminPassword)) {
        return json(req, { error: "donnees_ecole_ou_admin_invalides" }, 400);
      }
      if (managerUsername.length < 3 || managerName.length < 2 || !isStrongPassword(managerPassword)) {
        return json(req, { error: "donnees_gestionnaire_invalides" }, 400);
      }

      let adminUserId: string | null = null;
      let managerUserId: string | null = null;
      let orgId: string | null = null;
      try {
        const { data: createdAdmin, error: adminErr } = await server.auth.admin.createUser({
          email: adminEmail,
          password: adminPassword,
          email_confirm: true,
          app_metadata: { gesapp_role: "admin" },
          user_metadata: { display_name: adminName },
        });
        if (adminErr || !createdAdmin.user) return json(req, { error: adminErr?.message ?? "creation_admin_impossible" }, 409);
        adminUserId = createdAdmin.user.id;

        const baseCode = preferredCode || normalizeCode(name) || "ECOLE";
        let code = baseCode + "-" + randomHex(3);
        for (let attempt = 0; attempt < 4; attempt++) {
          const { data: existing } = await server.from("organizations").select("id").eq("code", code).maybeSingle();
          if (!existing) break;
          code = baseCode + "-" + randomHex(3);
        }

        const { data: org, error: orgErr } = await server.from("organizations")
          .insert({ code, name, created_by: adminUserId, active: true })
          .select("id,code,name,active").single();
        if (orgErr || !org) throw new Error(orgErr?.message ?? "creation_ecole_impossible");
        orgId = org.id;

        const { error: adminMemberErr } = await server.from("organization_members").insert({
          organization_id: orgId,
          user_id: adminUserId,
          display_name: adminName,
          role: "admin",
          status: "active",
          active: true,
          must_change_password: false,
          created_by: admin.user_id,
        });
        if (adminMemberErr) throw new Error(adminMemberErr.message);

        const { error: syncErr } = await server.from("sync_metadata").insert({ organization_id: orgId, revision: 0 });
        if (syncErr) throw new Error(syncErr.message);

        await server.auth.admin.updateUserById(adminUserId, {
          app_metadata: { gesapp_role: "admin", organization_id: orgId },
        });

        const syntheticEmail = `manager.${normalizeUser(code)}.${managerUsername}@auth.gesapp.invalid`;
        const { data: createdManager, error: managerErr } = await server.auth.admin.createUser({
          email: syntheticEmail,
          password: managerPassword,
          email_confirm: true,
          app_metadata: { gesapp_role: "manager", organization_id: orgId },
          user_metadata: { gesapp_username: managerUsername, display_name: managerName },
        });
        if (managerErr || !createdManager.user) throw new Error(managerErr?.message ?? "creation_gestionnaire_impossible");
        managerUserId = createdManager.user.id;

        const { error: managerMemberErr } = await server.from("organization_members").insert({
          organization_id: orgId,
          user_id: managerUserId,
          username: managerUsername,
          display_name: managerName,
          role: "manager",
          status: "active",
          active: true,
          must_change_password: true,
          created_by: admin.user_id,
        });
        if (managerMemberErr) throw new Error(managerMemberErr.message);

        const { error: billingError } = await server.rpc("admin_confirm_subscription", {
          p_organization_id: orgId, p_cycle: subscriptionCycle, p_approver: admin.user_id,
          p_reference: "Création manuelle par le Super Admin",
        });
        if (billingError) throw new Error(billingError.message);

        await server.from("platform_activity_events").insert({
          organization_id: orgId,
          actor_user_id: admin.user_id,
          event_type: "school_created",
          module: "super_admin",
          message: "Établissement créé depuis le tableau de bord Super Admin",
          metadata: { code, admin_email: adminEmail, manager_username: managerUsername },
        });

        return json(req, {
          ok: true,
          organization: org,
          administrator: { email: adminEmail, display_name: adminName },
          manager: { username: managerUsername, display_name: managerName },
        }, 201);
      } catch (e) {
        if (orgId) {
          await server.from("subscription_payments").delete().eq("organization_id", orgId);
          await server.from("organization_members").delete().eq("organization_id", orgId);
          await server.from("sync_metadata").delete().eq("organization_id", orgId);
          await server.from("devices").delete().eq("organization_id", orgId);
          await server.from("platform_activity_events").delete().eq("organization_id", orgId);
          await server.from("organizations").delete().eq("id", orgId);
        }
        if (managerUserId) await server.auth.admin.deleteUser(managerUserId);
        if (adminUserId) await server.auth.admin.deleteUser(adminUserId);
        console.error("create_school_failed", e);
        return json(req, { error: "creation_ecole_impossible" }, 409);
      }
    }

    if (action === "set_school_active") {
      const organizationId = String(body.organization_id ?? "");
      const active = body.active === true;
      if (!organizationId) return json(req, { error: "organization_id_requis" }, 400);
      const { data: org, error } = await server.from("organizations")
        .update({ active, updated_at: new Date().toISOString() })
        .eq("id", organizationId).select("id,code,name,active").maybeSingle();
      if (error || !org) return json(req, { error: error?.message ?? "ecole_introuvable" }, 404);
      await server.from("platform_activity_events").insert({
        organization_id: organizationId,
        actor_user_id: admin.user_id,
        event_type: active ? "school_activated" : "school_suspended",
        module: "super_admin",
        message: active ? "Établissement activé" : "Établissement suspendu",
        metadata: { code: org.code },
      });
      return json(req, { ok: true, organization: org });
    }

    return json(req, { error: "action_inconnue" }, 400);
  } catch (e) {
    console.error("super_admin_api_unhandled", e);
    return json(req, { error: "internal_error" }, 500);
  }
});
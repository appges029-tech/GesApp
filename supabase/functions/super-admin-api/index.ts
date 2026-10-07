import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-super-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const te = new TextEncoder();
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const server = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");

    if (action === "login") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const code = String(body.code ?? "").trim();
      if (!email || !code) return json({ error: "identifiants_requis" }, 400);

      const { data: admin, error } = await server.from("platform_super_admins")
        .select("id,user_id,email,pin_salt,pin_hash,pin_iterations,active,failed_attempts,locked_until")
        .eq("email", email).maybeSingle();
      if (error) return json({ error: "login_unavailable" }, 500);
      if (!admin || !admin.active) return json({ error: "acces_refuse" }, 403);

      const now = new Date();
      if (admin.locked_until && new Date(admin.locked_until) > now) {
        return json({ error: "compte_temporairement_verrouille", locked_until: admin.locked_until }, 429);
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
        return json({ error: "identifiants_invalides" }, 401);
      }

      const token = bytesToB64Url(crypto.getRandomValues(new Uint8Array(32)));
      const tokenHash = await sha256Hex(token);
      const expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
      await server.from("platform_super_admins").update({
        failed_attempts: 0, locked_until: null, updated_at: new Date().toISOString(),
      }).eq("id", admin.id);
      await server.from("platform_super_admin_sessions").delete()
        .eq("super_admin_id", admin.id).lt("expires_at", new Date().toISOString());
      const { error: sessionError } = await server.from("platform_super_admin_sessions").insert({
        super_admin_id: admin.id,
        token_hash: tokenHash,
        expires_at: expiresAt,
      });
      if (sessionError) return json({ error: "session_creation_failed" }, 500);

      await server.from("platform_activity_events").insert({
        organization_id: null,
        actor_user_id: admin.user_id,
        event_type: "super_admin_login",
        module: "super_admin",
        message: "Connexion au tableau de bord Super Admin",
        metadata: {},
      });

      return json({ token, expires_at: expiresAt, email: admin.email });
    }

    const token = req.headers.get("x-super-admin-session") ?? String(body.session_token ?? "");
    if (!token) return json({ error: "session_requise" }, 401);
    const tokenHash = await sha256Hex(token);
    const { data: session } = await server.from("platform_super_admin_sessions")
      .select("id,super_admin_id,expires_at,revoked_at")
      .eq("token_hash", tokenHash)
      .is("revoked_at", null)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (!session) return json({ error: "session_invalide_ou_expiree" }, 401);

    const { data: admin } = await server.from("platform_super_admins")
      .select("id,user_id,email,active")
      .eq("id", session.super_admin_id).eq("active", true).maybeSingle();
    if (!admin) return json({ error: "acces_refuse" }, 403);
    await server.from("platform_super_admin_sessions")
      .update({ last_seen_at: new Date().toISOString() }).eq("id", session.id);

    if (action === "logout") {
      await server.from("platform_super_admin_sessions")
        .update({ revoked_at: new Date().toISOString() }).eq("id", session.id);
      return json({ ok: true });
    }

    if (action === "overview") {
      const [orgsRes, membersRes, devicesRes, syncRes, eventsRes] = await Promise.all([
        server.from("organizations").select("id,code,name,active,created_at,updated_at").order("created_at", { ascending: false }),
        server.from("organization_members").select("id,organization_id,user_id,role,username,display_name,active,status,must_change_password,created_at"),
        server.from("devices").select("id,organization_id,user_id,device_key,platform,app_version,last_seen_at,created_at").order("last_seen_at", { ascending: false }),
        server.from("sync_metadata").select("organization_id,revision,size_bytes,updated_at,uploaded_at,current_path"),
        server.from("platform_activity_events")
          .select("id,organization_id,actor_user_id,event_type,module,message,metadata,created_at")
          .order("created_at", { ascending: false }).limit(80),
      ]);
      for (const result of [orgsRes, membersRes, devicesRes, syncRes, eventsRes]) {
        if (result.error) return json({ error: result.error.message }, 500);
      }
      const members = membersRes.data ?? [], devices = devicesRes.data ?? [], syncs = syncRes.data ?? [];
      const now = Date.now();
      const organizations = (orgsRes.data ?? []).map((org) => {
        const om = members.filter((m) => m.organization_id === org.id);
        const od = devices.filter((d) => d.organization_id === org.id);
        const sync = syncs.find((s) => s.organization_id === org.id) ?? null;
        return {
          ...org,
          admin: om.find((m) => m.role === "admin") ?? null,
          managers: om.filter((m) => m.role === "manager"),
          device_count: od.length,
          online_device_count: od.filter((d) => d.last_seen_at && now - new Date(d.last_seen_at).getTime() <= 120000).length,
          last_seen_at: od.length ? od[0].last_seen_at : null,
          sync,
        };
      });
      const online = devices.filter((d) => d.last_seen_at && now - new Date(d.last_seen_at).getTime() <= 120000).length;
      const recentActivity = (eventsRes.data ?? []).map((event) => {
        const org = organizations.find((o) => o.id === event.organization_id);
        return {
          ...event,
          organization_name: org?.name ?? null,
          organization_code: org?.code ?? null,
        };
      });
      return json({
        generated_at: new Date().toISOString(),
        totals: {
          schools: organizations.length,
          active_schools: organizations.filter((o) => o.active).length,
          managers: members.filter((m) => m.role === "manager" && m.active).length,
          devices: devices.length,
          online_devices: online,
        },
        organizations,
        recent_activity: recentActivity,
      });
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

      if (name.length < 3 || !adminEmail.includes("@") || adminName.length < 2 || adminPassword.length < 8) {
        return json({ error: "donnees_ecole_ou_admin_invalides" }, 400);
      }
      if (managerUsername.length < 3 || managerName.length < 2 || managerPassword.length < 8) {
        return json({ error: "donnees_gestionnaire_invalides" }, 400);
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
        if (adminErr || !createdAdmin.user) return json({ error: adminErr?.message ?? "creation_admin_impossible" }, 409);
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

        await server.from("platform_activity_events").insert({
          organization_id: orgId,
          actor_user_id: admin.user_id,
          event_type: "school_created",
          module: "super_admin",
          message: "Établissement créé depuis le tableau de bord Super Admin",
          metadata: { code, admin_email: adminEmail, manager_username: managerUsername },
        });

        return json({
          ok: true,
          organization: org,
          administrator: { email: adminEmail, display_name: adminName },
          manager: { username: managerUsername, display_name: managerName },
        }, 201);
      } catch (e) {
        if (orgId) {
          await server.from("organization_members").delete().eq("organization_id", orgId);
          await server.from("sync_metadata").delete().eq("organization_id", orgId);
          await server.from("devices").delete().eq("organization_id", orgId);
          await server.from("platform_activity_events").delete().eq("organization_id", orgId);
          await server.from("organizations").delete().eq("id", orgId);
        }
        if (managerUserId) await server.auth.admin.deleteUser(managerUserId);
        if (adminUserId) await server.auth.admin.deleteUser(adminUserId);
        return json({ error: e instanceof Error ? e.message : String(e) }, 409);
      }
    }

    if (action === "set_school_active") {
      const organizationId = String(body.organization_id ?? "");
      const active = body.active === true;
      if (!organizationId) return json({ error: "organization_id_requis" }, 400);
      const { data: org, error } = await server.from("organizations")
        .update({ active, updated_at: new Date().toISOString() })
        .eq("id", organizationId).select("id,code,name,active").maybeSingle();
      if (error || !org) return json({ error: error?.message ?? "ecole_introuvable" }, 404);
      await server.from("platform_activity_events").insert({
        organization_id: organizationId,
        actor_user_id: admin.user_id,
        event_type: active ? "school_activated" : "school_suspended",
        module: "super_admin",
        message: active ? "Établissement activé" : "Établissement suspendu",
        metadata: { code: org.code },
      });
      return json({ ok: true, organization: org });
    }

    return json({ error: "action_inconnue" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
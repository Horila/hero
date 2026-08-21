// Supabase Edge Function: manage-users
// Lets the owner (app_users.is_owner = true) add/remove/edit other logins and their
// view_only/full_access permission. Uses the service-role key (auto-injected into every
// edge function — never exposed to the browser) to call the Auth admin API, which no
// client-side key is allowed to do.
//
// Deploy via mcp__claude_ai_Supabase__deploy_edge_function, name it exactly "manage-users".

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "content-type": "application/json" },
  });
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) return json({ error: "not authenticated" }, 401);

    const { data: callerRow } = await admin
      .from("app_users")
      .select("is_owner")
      .eq("user_id", caller.id)
      .single();
    if (!callerRow?.is_owner) return json({ error: "only the owner can manage users" }, 403);

    const { action, ...body } = await req.json();

    if (action === "list") {
      const { data, error } = await admin
        .from("app_users")
        .select("user_id,email,name,permission,is_owner,created_at")
        .order("created_at", { ascending: true });
      if (error) return json({ error: error.message }, 500);
      return json(data);
    }

    if (action === "create") {
      const { email, password, name, permission } = body;
      if (!email || !password || !name) return json({ error: "email, password, and name are required" }, 400);
      if (password.length < 8) return json({ error: "password must be at least 8 characters" }, 400);
      if (permission !== "view_only" && permission !== "full_access") return json({ error: "invalid permission" }, 400);

      const { data: created, error: createErr } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (createErr) return json({ error: createErr.message }, 400);

      const { error: insertErr } = await admin.from("app_users").insert({
        user_id: created.user.id, email, name, permission,
      });
      if (insertErr) {
        const { error: rollbackErr } = await admin.auth.admin.deleteUser(created.user.id); // roll back the auth user, don't leave an orphan login
        if (rollbackErr) {
          return json({ error: `${insertErr.message} (rollback also failed: ${rollbackErr.message} — orphaned auth user ${created.user.id})` }, 500);
        }
        return json({ error: insertErr.message }, 500);
      }
      return json({ ok: true });
    }

    if (action === "update") {
      const { user_id, name, permission } = body;
      if (!user_id) return json({ error: "user_id required" }, 400);
      if (permission && permission !== "view_only" && permission !== "full_access") return json({ error: "invalid permission" }, 400);
      if (user_id === caller.id && permission && permission !== "full_access") {
        return json({ error: "you can't downgrade your own account" }, 400);
      }
      const patch: Record<string, unknown> = {};
      if (name !== undefined) patch.name = name;
      if (permission !== undefined) patch.permission = permission;
      const { error } = await admin.from("app_users").update(patch).eq("user_id", user_id);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true });
    }

    if (action === "delete") {
      const { user_id } = body;
      if (!user_id) return json({ error: "user_id required" }, 400);
      if (user_id === caller.id) return json({ error: "you can't delete your own account" }, 400);
      const { error } = await admin.auth.admin.deleteUser(user_id); // app_users row cascades via FK
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true });
    }

    return json({ error: "unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

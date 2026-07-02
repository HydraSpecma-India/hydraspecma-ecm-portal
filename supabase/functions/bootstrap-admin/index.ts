// POST /functions/v1/bootstrap-admin  { email, role }
// Grants a role to a user by email. Authorized either by:
//   * a matching x-bootstrap-secret header (first-time setup), OR
//   * a caller who is already SUPER_ADMIN / ECM_ADMIN.
import { corsHeaders, json } from "../_shared/cors.ts";
import { adminClient, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const body = await req.json().catch(() => ({}));
  const email = String(body.email ?? "").trim();
  const role = String(body.role ?? "SUPER_ADMIN").trim();
  if (!email) return json({ error: "email is required" }, 400);

  // Authorization
  const secret = Deno.env.get("BOOTSTRAP_SECRET");
  const providedSecret = req.headers.get("x-bootstrap-secret");
  let authorized = Boolean(secret && providedSecret && providedSecret === secret);

  if (!authorized) {
    const me = userClient(req);
    const { data } = await me.rpc("fn_me");
    const roles: string[] = data?.roles ?? [];
    authorized = roles.includes("SUPER_ADMIN") || roles.includes("ECM_ADMIN");
  }
  if (!authorized) return json({ error: "Not authorized" }, 403);

  const admin = adminClient();
  const { error } = await admin.rpc("fn_grant_role", { p_email: email, p_role: role });
  if (error) return json({ error: error.message }, 400);
  return json({ ok: true, email, role });
});

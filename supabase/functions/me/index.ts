// GET /functions/v1/me — returns the caller's profile, roles and permissions.
import { corsHeaders, json } from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { supabase } = await requireUser(req);
    const { data, error } = await supabase.rpc("fn_me");
    if (error) return json({ error: error.message }, 400);
    return json(data);
  } catch (e) {
    if (e instanceof Response) return e;
    return json({ error: String(e) }, 500);
  }
});

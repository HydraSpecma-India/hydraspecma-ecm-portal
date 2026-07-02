// Supabase client helpers for Edge Functions (Deno).
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

/** Service-role client — bypasses RLS. Use ONLY for trusted server operations. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/** Client acting as the calling user (RLS applies), using their bearer token. */
export function userClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
      auth: { persistSession: false } },
  );
}

/** Resolve and require the authenticated user; throws Response(401) if missing. */
export async function requireUser(req: Request) {
  const supabase = userClient(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) throw new Response("Unauthorized", { status: 401 });
  return { user: data.user, supabase };
}

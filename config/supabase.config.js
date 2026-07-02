/**
 * supabase.config.js — Singleton Supabase client (client-safe, ESM).
 * Uses the anon key + the signed-in user's JWT; RLS enforces all access.
 * The @supabase/supabase-js ESM bundle is loaded directly from a pinned CDN,
 * so no build step/bundler is required. Override the URL via an import map if
 * you prefer to self-host (see docs/SETUP-GUIDE.md).
 * @module config/supabase
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { env } from './app.config.js';

let _client = null;

/** @returns {import('https://esm.sh/@supabase/supabase-js@2.45.0').SupabaseClient} */
export function getSupabase() {
  if (_client) return _client;
  const url = env('VITE_SUPABASE_URL');
  const anon = env('VITE_SUPABASE_ANON_KEY');
  if (!url || !anon) {
    throw new Error('[supabase] Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY — see docs/SETUP-GUIDE.md.');
  }
  _client = createClient(url, anon, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
    realtime: { params: { eventsPerSecond: 10 } },
    global: { headers: { 'x-client-info': 'hydraspecma-ecm-portal' } },
  });
  return _client;
}

/** Drops the cached client (used on sign-out / token reset). */
export function resetSupabase() { _client = null; }

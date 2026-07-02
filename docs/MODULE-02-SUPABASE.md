# Module 2 — Supabase Setup

Turns the Module 1 schema into a runnable backend and gives the app its connection layer.

## Delivered
**Auth integration** (`supabase/migrations/0022_auth_hooks.sql`)
- `fn_handle_new_user()` trigger on `auth.users` — provisions a `profiles` row on signup and assigns a default role. **First user → `SUPER_ADMIN`** (bootstrap); others → `VIEWER`.
- `fn_grant_role(email, role, plant?)` — admin/service helper to (re)assign roles.
- `fn_me()` — returns the caller's profile + role codes + permission codes (client bootstrap).
- `fn_touch_last_login()` — updates `last_login_at`.
- Guarded to self-skip on a plain PostgreSQL instance.

**Service layer** (`services/`, vanilla ES2024, no bundler)
- `config/supabase.config.js` — singleton client via pinned ESM `createClient` (PKCE, auto-refresh, realtime).
- `services/core/errors.js` — `AppError` + Postgres/PostgREST → friendly-message mapping + `unwrap`.
- `services/core/BaseRepository.js` — generic CRUD, filtering, search, pagination, RPC (Repository pattern).
- `services/auth/authService.js` — email/password + Azure AD SSO, session, remember-me, password reset, `me()`.
- `services/realtime/realtimeService.js` — notification & record channels.
- `services/storage/storageService.js` — upload/download/signed & public URLs, bucket constants.
- `services/workflow/workflowService.js` — available transitions, `fn_execute_transition`, timeline, workflow definition.
- `services/ecm/ecmRepository.js` — example repository over `vw_ecm_overview` + dashboard KPIs.
- `services/index.js` — barrel export.

**Edge Functions** (`supabase/functions/`, Deno/TypeScript)
- `_shared/cors.ts`, `_shared/supabase.ts` (admin + user clients, `requireUser`).
- `me` — returns `fn_me` for the caller.
- `bootstrap-admin` — grant a role by email (secret- or admin-authorized).

**Build/env**
- `scripts/gen-env.js` + `npm run build` — emits client-safe `env.js` (public keys only).
- `vercel.json` — `buildCommand`, output dir, security headers.

## How to run
See [`SETUP-GUIDE.md`](./SETUP-GUIDE.md) sections 2–10. In short: create the Supabase project, set env, `supabase db push` + seed, deploy the two Edge Functions, enable Azure AD, sign in (first user becomes Super Admin), then `npm run dev`.

## Verification
- `node --check` passes on every service/script file.
- `python3 database/validate_schema.py` → **PASS** (now includes migration 0022).
- `select fn_me();` returns roles/permissions once signed in.

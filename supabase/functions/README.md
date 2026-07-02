# Supabase Edge Functions

Deno/TypeScript functions deployed with `supabase functions deploy <name>`.

| Function | Method | Purpose | Auth |
|----------|--------|---------|------|
| `me` | GET | Caller's profile + roles + permissions (`fn_me`) | User JWT |
| `bootstrap-admin` | POST | Grant a role to a user by email | `x-bootstrap-secret` **or** Super/ECM Admin |

Planned in later modules: `email-approval` (M10), `d365-sync-worker` (M12),
`graph-notify` (M13), `powerbi-embed-token` (M14), `ai-assistant` (M15).

## Secrets (set with `supabase secrets set`)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BOOTSTRAP_SECRET`, `APP_BASE_URL`.

## Local dev
```bash
supabase functions serve --env-file ./supabase/.env.local
curl -H "Authorization: Bearer <jwt>" http://localhost:54321/functions/v1/me
```

# Setup Guide — HydraSpecma ECM Portal

End-to-end setup: from a fresh Supabase project to a deployed portal on Vercel with Azure AD SSO. Follow top to bottom the first time.

---

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Node.js | ≥ 20 | `node -v` |
| Supabase CLI | ≥ 1.190 | `npm i -g supabase` |
| Git | any | for GitHub + Vercel |
| A Supabase account | — | https://supabase.com |
| A Vercel account | — | https://vercel.com |
| (Optional) Microsoft Entra tenant | — | for Azure AD / M365 SSO |
| (Optional) D365 F&O, Power BI, an AI key | — | Modules 12/14/15 |

Get the code:
```bash
git clone <your-repo-url> hydraspecma-ecm-portal   # or unzip the delivered archive
cd hydraspecma-ecm-portal
npm install
```

---

## 2. Create the Supabase project

1. Supabase Dashboard → **New project**. Choose a region close to your users; save the database password.
2. **Project Settings → API**: copy **Project URL**, **anon public** key, and **service_role** key.
3. **Project Settings → API → JWT Settings**: copy the **JWT secret**.
4. **Project Settings → Database → Connection string (URI)**: copy the connection string.

---

## 3. Configure environment

```bash
cp .env.example .env.local
```
Fill at least:
```
VITE_SUPABASE_URL=https://<ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
SUPABASE_SERVICE_ROLE_KEY=<service role key>
SUPABASE_DB_URL=postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres
APP_BASE_URL=http://localhost:5173
```

> **How env reaches the browser.** This is a no-bundler app, so `npm run build` runs `scripts/gen-env.js`, which writes a **client-safe** `env.js` (only `VITE_*`/public keys) that pages load via `<script src="/env.js"></script>`. Service-role keys and secrets are **never** written to `env.js`; they live only in Edge Function/Vercel server env.

---

## 4. Apply the database

**Recommended — Supabase CLI:**
```bash
supabase link --project-ref <ref>
supabase db push            # applies supabase/migrations/0001..0022
```
Seed the reference/workflow data (order matters — RBAC → org → workflow → templates):
```bash
# Local stack:
supabase db reset           # re-applies migrations AND runs the ordered seeds (config.toml)

# Remote project (run the bundle once):
psql "$SUPABASE_DB_URL" -f sql/01_seed_full.sql
```

**Alternative — plain psql (any PostgreSQL 15):**
```bash
psql "$SUPABASE_DB_URL" -f sql/00_schema_full.sql
psql "$SUPABASE_DB_URL" -f sql/01_seed_full.sql
```

Sanity-check structure without a DB anytime:
```bash
python3 database/validate_schema.py     # expect: RESULT: PASS
```

---

## 5. Storage

Buckets (`ecm-documents`, `ecm-attachments`, `ecm-exports`, `ecm-avatars`) and their object policies are created by migration `0021_storage_buckets.sql`. Verify under **Storage** in the dashboard. Adjust size limits in that migration if needed.

---

## 6. Edge Functions

Set function secrets, then deploy:
```bash
supabase secrets set \
  SUPABASE_URL=https://<ref>.supabase.co \
  SUPABASE_ANON_KEY=<anon> \
  SUPABASE_SERVICE_ROLE_KEY=<service role> \
  BOOTSTRAP_SECRET=$(openssl rand -hex 24) \
  APP_BASE_URL=https://<your-vercel-domain>

supabase functions deploy me
supabase functions deploy bootstrap-admin
```

---

## 7. Authentication providers

**Email/password** — enabled by default (`config.toml → [auth.email]`).

**Azure AD / Microsoft 365 SSO:**
1. Entra admin center → **App registrations → New registration**.
2. Redirect URI (Web): `https://<ref>.supabase.co/auth/v1/callback`.
3. **Certificates & secrets → New client secret**; copy the value.
4. **API permissions**: add Microsoft Graph delegated `User.Read` (add `Mail.Send`, `Calendars.ReadWrite` for Module 13).
5. Put `AZURE_AD_TENANT_ID`, `AZURE_AD_CLIENT_ID`, `AZURE_AD_CLIENT_SECRET` in your env.
6. Supabase Dashboard → **Authentication → Providers → Azure**: enable, paste client id/secret, set the tenant URL `https://login.microsoftonline.com/<tenant>/v2.0`. (Mirrored in `config.toml → [auth.external.azure]`.)
7. **Authentication → URL Configuration**: add your site + `…/auth/callback` redirect URLs.

---

## 8. Create the first administrator

The `handle_new_user` trigger (migration 0022) provisions a profile for every new auth user and assigns a default role. **The very first user to sign up becomes `SUPER_ADMIN`** automatically; everyone after that starts as `VIEWER`.

To promote someone later:
```bash
curl -X POST "https://<ref>.functions.supabase.co/bootstrap-admin" \
  -H "x-bootstrap-secret: <BOOTSTRAP_SECRET>" \
  -H "content-type: application/json" \
  -d '{"email":"jane@hydraspecma.com","role":"ECM_ADMIN"}'
```
or, as an existing admin, from the Admin Panel (Module 19). Roles can also be granted in SQL: `SELECT fn_grant_role('jane@hydraspecma.com','ENGINEER');`

---

## 9. Run locally

```bash
npm run build          # generates env.js from .env.local
npm run dev            # vercel dev  (or: npx serve .)
```
Open the app, sign in, and confirm the dashboard loads KPI data.

---

## 10. Deploy to Vercel + GitHub

1. Push to GitHub: `git init && git add . && git commit -m "init" && git remote add origin <url> && git push -u origin main`.
2. Vercel → **Add New → Project → import the repo**.
3. Framework preset: **Other**. Build command: `npm run build`. Output directory: `.`.
4. **Environment Variables**: add everything from `.env.local` (the build only exposes public keys via `env.js`; server secrets stay in Vercel env for any serverless routes).
5. Deploy. Add the production domain to Supabase **Auth → URL Configuration** and to the Entra redirect URIs.

Security headers (CSP, HSTS, X-Frame-Options, nosniff) are already defined in `vercel.json`.

---

## 11. Later-module integrations (optional now)
- **D365 F&O (M12):** fill `D365_*`, activate the endpoint row in `integration_endpoints`, deploy the sync worker.
- **Power BI (M14):** fill `POWERBI_*`, register reports in `powerbi_reports`.
- **AI (M15):** set `AI_PROVIDER`/`AI_API_KEY`; the assistant calls an Edge Function so keys never reach the browser.

---

## 12. Verification checklist
- [ ] `supabase db push` applied migrations 0001–0022 with no errors.
- [ ] Seeds loaded: `select count(*) from roles;` → 13, `select count(*) from wf_states;` → 25.
- [ ] `python3 database/validate_schema.py` → **PASS**.
- [ ] First sign-up received `SUPER_ADMIN` (`select * from user_roles`).
- [ ] `GET /functions/v1/me` returns your profile, roles and permissions.
- [ ] Storage buckets exist; a test upload/download works.
- [ ] Vercel deployment loads and authenticates.

---

## 13. Troubleshooting
| Symptom | Fix |
|--------|-----|
| `Missing VITE_SUPABASE_URL…` in console | Run `npm run build` (regenerates `env.js`) and ensure the page includes `<script src="/env.js">`. |
| `permission denied for table …` | User lacks the permission; check `user_roles`/`role_permissions`, or you queried before signing in. |
| Rows return empty despite data | RLS is working — the JWT lacks the needed permission or plant scope. Verify with `select fn_me();`. |
| Azure login loops | Redirect URI mismatch — must be `https://<ref>.supabase.co/auth/v1/callback` and listed in Auth URL config. |
| `auth.users not present` on plain PG | Expected — the auth trigger self-skips; use Supabase for full auth. |
| Seed fails on remote | Ensure migrations ran first (tables must exist before seeds). |

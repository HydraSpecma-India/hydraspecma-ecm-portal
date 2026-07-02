# Module 1 — Database Design

Production-grade PostgreSQL/Supabase foundation for the entire portal.

## What's included
- **55 tables** across 15 functional areas (identity/RBAC, organization, workflow engine, items/BOM, ECM/ECR/ECO, tasks, documents, approvals, collaboration, notifications, audit, integration, AI, analytics/BI, system).
- **13 enumerated types**, **25 functions**, **45 triggers**, **12 analytics views**.
- **Row-Level Security enabled on every table**, driven by a role→permission matrix.
- **Data-driven workflow** imported from `ECM Flow.xlsx` — 4 stages, 25 states, 35 transitions, 32 sequenced task templates. No workflow logic is hardcoded.
- **Field-level audit trail**, append-only **state history** with dwell time, atomic **document numbering** (`ECM-YYYY-#####`), **QR** auto-generation, **global search** (tsvector + trigram), and **Supabase Storage** buckets/policies.
- Idempotent **seed** for roles, permissions, org, workflow and templates.

## File map
```
supabase/
  config.toml                 Supabase project + ordered seed config
  migrations/
    0001_extensions_and_types.sql     extensions, enums, utility fns
    0002_identity_access.sql          roles, permissions, profiles, user_roles
    0003_organization.sql             plants, departments, customers, suppliers
    0004_workflow_engine.sql          wf_* tables + state categories
    0005_items_bom.sql                items, boms, bom_lines
    0006_ecm_core.sql                 ecm_requests, ecr_records, eco_records, links, history
    0007_tasks.sql                    tasks, dependencies, checklist, reminders
    0008_documents.sql                categories, documents, versions, signatures
    0009_comments_attachments.sql     comments, attachments
    0010_approvals.sql                approval requests/assignments/email tokens
    0011_notifications_email.sql      notifications, rules, prefs, templates
    0012_audit.sql                    field-level audit_logs
    0013_integration_api.sql          endpoints, api_logs, sync state, D365 queue
    0014_ai_history.sql               conversations, messages, insights
    0015_powerbi_reports.sql          Power BI, report catalog, dashboards, filters
    0016_qr_search.sql                QR codes + search indexes
    0017_functions.sql                numbering, RBAC helpers, audit, workflow engine
    0018_triggers.sql                 trigger wiring
    0019_views_analytics.sql          dashboard/analytics views
    0020_rls_policies.sql             grants + RLS on every table
    0021_storage_buckets.sql          storage buckets + object policies
  seed/
    10_rbac.sql  20_org.sql  30_workflow.sql (generated)  40_templates.sql
  seed.sql                     psql entrypoint
sql/
  00_schema_full.sql           all migrations concatenated (plain psql / CI)
  01_seed_full.sql             all seeds concatenated
workflow/
  ecm-flow.json                normalized workflow config (source of truth for the import)
  build_workflow.py            Excel -> ecm-flow.json
  build_workflow_seed.py       ecm-flow.json -> 30_workflow.sql
  WORKFLOW.md                  state diagram + tables
database/
  ERD.md  DATA-DICTIONARY.md  validate_schema.py
```

## Apply the database

### Option A — Supabase CLI (recommended)
```bash
supabase init            # if not already
supabase link --project-ref <your-ref>
supabase db push         # applies supabase/migrations/*
supabase db reset        # (local) re-applies migrations + runs ordered seeds
```
Seed order is defined in `supabase/config.toml` → `[db.seed].sql_paths`.

### Option B — Plain PostgreSQL 15
```bash
psql "$DATABASE_URL" -f sql/00_schema_full.sql
psql "$DATABASE_URL" -f sql/01_seed_full.sql
```
> Note: `auth.users` (Supabase) is referenced by `profiles`. On a non-Supabase database, create a compatible `auth` schema/table first, or run against Supabase where it already exists. The storage migration self-skips when the `storage` schema is absent.

## Re-importing the workflow
Edit the flow in the workbook (or `workflow/ecm-flow.json`) and regenerate:
```bash
npm run workflow:build     # build_workflow.py + build_workflow_seed.py
supabase db reset          # re-imports 30_workflow.sql (idempotent upserts)
```

## Access-control model
Each of the 13 roles maps to fine-grained permissions (`ecm.create`, `eco.review`, `audit.read`, …) via `role_permissions`. RLS policies call `fn_has_permission(code)`, `fn_is_admin()` and `fn_can_access_plant(plant_id)`. Super Admin bypasses checks; the `service_role` (Edge Functions) bypasses RLS for trusted server work. See the matrix in `supabase/seed/10_rbac.sql`.

## Numbering
`fn_next_number('ECM'|'ECR'|'ECO')` uses the `number_sequences` table for atomic, per-year, gap-tolerant sequences and returns e.g. `ECM-2026-00001`. Assigned automatically on insert via `BEFORE INSERT` triggers.

## Verification
No live database is required to sanity-check structure:
```bash
python3 database/validate_schema.py
```
Checks dollar-quote/paren balance, foreign-key target existence, seed/schema column drift, and that every workflow-referenced permission and role exists in the RBAC seed. Current result: **PASS**. Runtime tests (pgTAP + RLS matrix) arrive in Module 20.

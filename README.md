# HydraSpecma ECM Portal
### Engineering Change Management System

Enterprise-grade portal for managing engineering changes end to end — pre-request → ECR → CR-board → ECO → implementation → validation → completed — with tasks, documents, approvals, audit, D365 F&O / Microsoft 365 / Power BI integration and an AI assistant.

Built to the standard of commercial PLM (Teamcenter, Windchill, SAP PLM, Autodesk Vault), on an intentionally lightweight, framework-free stack.

---

## Tech stack
**Frontend:** HTML5 · Tailwind CSS · Vanilla JavaScript (ES2024) · Chart.js · Lucide · GSAP · SortableJS · FullCalendar · QRCode.js · PDF.js · Mermaid.js — *no React/Vue/Angular/Next.*
**Backend:** Supabase (PostgreSQL · Auth · Storage · Realtime · Edge Functions).
**Hosting:** Vercel · **VCS:** GitHub.
**Architecture:** component-based · repository pattern · service layer · clean architecture.

## Brand
HydraSpecma — Primary `#003A70` · Secondary `#00A3E0` · Accent `#0EA5E9` · Background `#F8FAFC` · Inter · 16px radius · Fluent-inspired, light/dark.

---

## Project structure
```
pages/         components/     services/       api/            supabase/functions/   (app + edge)
css/           assets/         js/                                                    (front-end assets)
config/        workflow/       database/       sql/            docs/                  (config, workflow, DB, docs)
supabase/      supabase/migrations/  supabase/seed/                                   (DB source of truth)
```

## Quick start
```bash
# 1. Configure environment
cp .env.example .env.local        # fill Supabase + Azure/D365/PowerBI/AI values

# 2. Database (Supabase CLI)
supabase link --project-ref <your-ref>
supabase db push                  # apply migrations
supabase db reset                 # (local) migrations + seeds

# 3. (optional) rebuild workflow from the Excel
npm run workflow:build

# 4. Run locally
npm install
npm run dev                       # vercel dev
```

## Documentation
- [`docs/SETUP-GUIDE.md`](docs/SETUP-GUIDE.md) — **full setup**: Supabase → Edge Functions → Azure AD → Vercel.
- [`docs/USER-GUIDE.md`](docs/USER-GUIDE.md) — **how to use the application** (roles, workflow, tasks, approvals…).
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, C4 diagrams, request lifecycle, security, deployment.
- [`docs/MODULE-ROADMAP.md`](docs/MODULE-ROADMAP.md) — the 22-module delivery plan and status.
- [`docs/MODULE-01-DATABASE.md`](docs/MODULE-01-DATABASE.md) · [`docs/MODULE-02-SUPABASE.md`](docs/MODULE-02-SUPABASE.md) — delivered modules.
- [`workflow/WORKFLOW.md`](workflow/WORKFLOW.md) — the change flow (imported from `ECM Flow.xlsx`).
- [`database/ERD.md`](database/ERD.md) · [`database/DATA-DICTIONARY.md`](database/DATA-DICTIONARY.md) — data model.

## Delivery status
- **Module 1 — Database Design: ✅ delivered.** 55 tables, 25 functions, 45 triggers, 12 analytics views, RLS on every table, storage buckets, data-driven workflow seeded from the HydraSpecma workbook.
- **Module 2 — Supabase Setup: ✅ delivered.** Auth hooks (auto-profile + first-user Super Admin bootstrap), the connection/service layer (client, repositories, auth/realtime/storage/workflow services), Edge Functions (`me`, `bootstrap-admin`), build-time public-env generation, and the setup + user guides.

Static validation passes (`python3 database/validate_schema.py`) and all service files pass `node --check`.

Next up: **Module 3 — Authentication (login UI & route guards).** Modules are delivered one at a time, production-ready, awaiting confirmation between each.

## License
Proprietary — © HydraSpecma. Internal use only.

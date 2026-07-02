# Delivery Roadmap — 22 Modules

Modules are delivered **one at a time**; each is production-grade before the next begins.

| # | Module | Status | Notes |
|---|--------|--------|-------|
| 1 | **Database Design** | ✅ Delivered | 55 tables, 25 functions, 45 triggers, 12 analytics views, RLS on every table, storage buckets, full seed. Workflow imported from `ECM Flow.xlsx`. |
| 2 | **Supabase Setup** | ✅ Delivered | Auth hooks (auto-profile + Super Admin bootstrap), service layer (client, repositories, auth/realtime/storage/workflow), Edge Functions (`me`, `bootstrap-admin`), build-time env, setup + user guides. |
| 3 | Authentication | ⏭ Next | Login UI: animated branded screen, email + Microsoft SSO, remember-me, forgot/reset, session guard & route protection on top of the Module 2 authService. |
| 4 | UI Components | ◻ Planned | Fluent-style component library (cards, tables, modals, toasts, skeletons), theming, dark mode. |
| 5 | Dashboard | ◻ Planned | Executive KPIs + charts, bound to `vw_dashboard_kpis` and analytics views. |
| 6 | Workflow Engine | ◻ Planned | UI + service over `fn_execute_transition`; Mermaid state visualization. |
| 7 | ECM Forms | ◻ Planned | Create/edit ECM, ECR, ECO; timeline; approval history; related records. |
| 8 | Task Management | ◻ Planned | Kanban / list / calendar / timeline / Gantt; drag-drop; dependencies; reminders. |
| 9 | Document Management | ◻ Planned | Upload, version, check-in/out, preview (PDF.js), e-signatures. |
| 10 | Approval Workflow | ◻ Planned | Gates, delegation, escalation, quorum policies. |
| 11 | Notifications | ◻ Planned | Realtime bell, unread counter, preferences, email/Teams fan-out. |
| 12 | D365FO Integration | ◻ Planned | OData sync, `d365_sync_queue` drainer, retry/backoff, API logs. |
| 13 | Microsoft 365 | ◻ Planned | Graph: Outlook, Teams, SharePoint, OneDrive, user sync. |
| 14 | Power BI | ◻ Planned | Embedded reports, SSO, filter-by-ECM. |
| 15 | AI Assistant | ◻ Planned | Summaries, missing-info, approver/doc suggestions, risk, delay prediction, chat. |
| 16 | Analytics | ◻ Planned | Interactive analytics over the views + drill-downs. |
| 17 | Reports | ◻ Planned | Executive/compliance/engineering; export PDF/Excel/CSV. |
| 18 | Audit Trail | ◻ Planned | Timeline viewer + export over `audit_logs`. |
| 19 | Admin Panel | ◻ Planned | Users, roles, workflow, templates, rules, settings. |
| 20 | Testing | ◻ Planned | pgTAP DB tests, unit + E2E (Playwright), RLS test matrix. |
| 21 | Deployment | ◻ Planned | Vercel + GitHub Actions CI/CD, migrations, env promotion. |
| 22 | Documentation | ◻ Planned | End-user + admin + developer docs. |

Legend: ✅ delivered · ⏭ next · ◻ planned

# Developer Documentation — HydraSpecma ECM Portal

This guide provides technical onboarding instructions and design patterns for developers working on the HydraSpecma Engineering Change Management (ECM) Portal.

---

## 1. Directory Structure

```
├── .github/workflows/       # CI/CD Deployment configurations
├── auth/                    # SSO and reset callbacks
├── components/              # Shared UI components (modal, toast, loader)
├── config/                  # Supabase config layers
├── docs/                    # Architectural documents and guides
├── js/                      # Main client routing guards and styles
├── pages/                   # Core portal page views
│   ├── admin.html           # Admin Panel (Module 19)
│   ├── audit-trail.html     # Timeline Audit Logs (Module 18)
│   ├── compliance.html      # FDA Certificates & registries (Module 12)
│   ├── ecm-detail.html      # Detail tracker & workflows (Module 6/7)
│   ├── integrations.html    # ERP sync dashboard (Module 13)
│   ├── reports.html         # Lead Times & SLA reports (Module 16)
│   └── tasks.html           # Kanban task manager (Module 8)
├── sql/                     # Schema migrations and seed scripts
└── vercel.json              # Vercel routing configurations
```

---

## 2. Coding Patterns & Architecture

### Client-Safe Environment Variables (`env.js`)
Since the application uses vanilla Javascript without a bundler, Vercel build runs `node scripts/gen-env.js` which parses the `.env.local` file and outputs `env.js` to the root path containing client-safe variables:
```javascript
window.__ENV__ = {
  VITE_SUPABASE_URL: "...",
  VITE_SUPABASE_ANON_KEY: "..."
};
```
Always load environment variables in HTML pages via `<script src="/env.js"></script>`.

### Authentication Guards (`auth-guard.js`)
To protect pages from guest access, import `auth-guard.js` at the top of the `<head>` section:
```html
<script type="module" src="/js/auth-guard.js"></script>
```
If a session is active, user badges will load profile info. If no session is active, they will be redirected to `/login.html`.

### Toast Alerts System
To issue a global UI alert:
```javascript
import { toast } from '../components/toast.js';

toast.success("ECM Request created successfully!");
toast.error("Operation failed. Try again.");
```

---

## 3. Database Updates (Migrations)
All changes to the database schema must be formulated as new migration files under `supabase/migrations/` or appended to `sql/00_schema_full.sql`. 
Verify structural integrity using:
```bash
python3 database/validate_schema.py
```
This script confirms database and workflow metadata schemas are consistent.

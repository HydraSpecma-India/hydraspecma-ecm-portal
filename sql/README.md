# /sql — Consolidated SQL bundles

The **source of truth** is `../supabase/migrations/*.sql` (run with the Supabase CLI).
These single-file bundles are generated for convenience (plain `psql`, code review, CI):

| File | Purpose |
|------|---------|
| `00_schema_full.sql` | All migrations concatenated in order (schema, functions, triggers, views, RLS, storage). |
| `01_seed_full.sql`   | All seed files concatenated (RBAC → org → workflow → templates). |

Regenerate after changing migrations:

```bash
{ for f in supabase/migrations/0*.sql; do echo "-- >>> $f"; cat "$f"; done; } > sql/00_schema_full.sql
```

Apply to any PostgreSQL 15 database:

```bash
psql "$DATABASE_URL" -f sql/00_schema_full.sql
psql "$DATABASE_URL" -f sql/01_seed_full.sql
```

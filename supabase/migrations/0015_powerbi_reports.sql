-- =============================================================================
-- 0015_powerbi_reports.sql
-- Module 1 / Module 14 & 17: Power BI embed registry, report definitions,
-- and user dashboard layouts / saved filters.
-- =============================================================================

CREATE TABLE IF NOT EXISTS powerbi_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  description  text,
  workspace_id text NOT NULL,
  report_id    text NOT NULL,
  dataset_id   text,
  embed_url    text,
  rls_role     text,                                        -- Power BI RLS role for row filtering
  filter_field text DEFAULT 'ECMNumber',                    -- field used to filter by ECM
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, report_id)
);
COMMENT ON TABLE powerbi_reports IS 'Registry of embeddable Power BI reports (SSO, filter-by-ECM).';

CREATE TABLE IF NOT EXISTS report_definitions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           citext NOT NULL UNIQUE,
  name           text NOT NULL,
  category       text NOT NULL DEFAULT 'executive'
                   CHECK (category IN ('executive','compliance','engineering','department','cycle_time','approval','audit')),
  description    text,
  source_view    text,                                      -- analytics view backing the report
  params         jsonb NOT NULL DEFAULT '{}'::jsonb,
  export_formats text[] NOT NULL DEFAULT ARRAY['pdf','excel','csv'],
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE report_definitions IS 'Built-in report catalog (Executive, Compliance, Engineering, Cycle Time...).';

CREATE TABLE IF NOT EXISTS dashboard_layouts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid REFERENCES profiles(id) ON DELETE CASCADE,   -- NULL = organization default
  name       text NOT NULL DEFAULT 'Default',
  scope      text NOT NULL DEFAULT 'dashboard'
               CHECK (scope IN ('dashboard','ecm_list','tasks','analytics')),
  config     jsonb NOT NULL DEFAULT '{}'::jsonb,               -- widgets, order, sizes
  is_default boolean NOT NULL DEFAULT false,
  is_shared  boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dash_layouts_user ON dashboard_layouts (user_id, scope);

CREATE TABLE IF NOT EXISTS saved_filters (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name       text NOT NULL,
  scope      text NOT NULL DEFAULT 'ecm_list',
  criteria   jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_saved_filters_user ON saved_filters (user_id, scope);

CREATE TRIGGER trg_powerbi_updated  BEFORE UPDATE ON powerbi_reports   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_dashlayout_updated BEFORE UPDATE ON dashboard_layouts FOR EACH ROW EXECUTE FUNCTION set_updated_at();

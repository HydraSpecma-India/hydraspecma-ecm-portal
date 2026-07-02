-- FULL SCHEMA (generated)

-- >>> supabase/migrations/0001_extensions_and_types.sql
-- =============================================================================
-- 0001_extensions_and_types.sql
-- HydraSpecma ECM Portal — Module 1: Database Design
-- Extensions, enumerated types (structural), and generic utility functions.
-- Target: PostgreSQL 15 / Supabase.
-- =============================================================================

-- ---- Extensions -------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;      -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS citext;        -- case-insensitive email/codes
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- fuzzy / global search
CREATE EXTENSION IF NOT EXISTS unaccent;      -- accent-insensitive search
CREATE EXTENSION IF NOT EXISTS btree_gin;     -- composite GIN indexes

-- ---- Enumerated types (fixed, structural — NOT workflow content) ------------
-- Workflow states/categories are DATA (wf_* tables), never enums.
DO $$ BEGIN
  CREATE TYPE priority_level  AS ENUM ('low','medium','high','critical');            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE risk_level      AS ENUM ('low','medium','high','severe');              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE change_source   AS ENUM ('manual','d365','ai','email','import','api'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE entity_type     AS ENUM ('ecm','ecr','eco','task','document','approval','comment','item','bom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE task_status      AS ENUM ('todo','in_progress','blocked','done','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_decision AS ENUM ('pending','approved','rejected','returned','delegated','escalated','abstained'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_status  AS ENUM ('pending','in_progress','approved','rejected','returned','cancelled','escalated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_policy  AS ENUM ('any','all','quorum','sequential'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE notification_channel AS ENUM ('in_app','email','teams','sms'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE document_status  AS ENUM ('draft','in_review','approved','released','obsolete','rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE signature_meaning AS ENUM ('authored','reviewed','approved','released','witnessed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE sync_status      AS ENUM ('pending','processing','success','failed','skipped'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE audit_action     AS ENUM ('INSERT','UPDATE','DELETE'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---- Generic utility functions ---------------------------------------------

-- Maintains updated_at on any table that carries the column.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
COMMENT ON FUNCTION set_updated_at() IS 'BEFORE UPDATE trigger: stamps updated_at = now().';

-- Returns the current authenticated user id (Supabase auth.uid()), or a
-- request-scoped override set via SET LOCAL app.current_user_id (used by API/edge fns).
CREATE OR REPLACE FUNCTION app_current_user_id()
RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE uid uuid;
BEGIN
  BEGIN uid := auth.uid(); EXCEPTION WHEN undefined_function THEN uid := NULL; END;
  IF uid IS NULL THEN
    uid := NULLIF(current_setting('app.current_user_id', true), '')::uuid;
  END IF;
  RETURN uid;
END $$;
COMMENT ON FUNCTION app_current_user_id() IS 'Resolves the acting user id from Supabase auth.uid() or app.current_user_id GUC.';

-- Request context getters (populated by the app layer via set_config for the audit trail).
CREATE OR REPLACE FUNCTION app_context(key text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.' || key, true), '');
$$;
COMMENT ON FUNCTION app_context(text) IS 'Reads request-scoped context (ip, user_agent, browser, device, session_id, request_id) for auditing.';

-- Slugify helper for codes / search keys.
CREATE OR REPLACE FUNCTION app_slugify(txt text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT trim(both '-' from regexp_replace(lower(unaccent(coalesce(txt,''))), '[^a-z0-9]+', '-', 'g'));
$$;

-- >>> supabase/migrations/0002_identity_access.sql
-- =============================================================================
-- 0002_identity_access.sql
-- Module 1: Identity & Role-Based Access Control (RBAC)
-- roles, permissions, role_permissions (matrix), profiles, user_roles.
-- profiles.id is 1:1 with Supabase auth.users(id).
-- =============================================================================

-- ---- Roles ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS roles (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             citext NOT NULL UNIQUE,
  name             text   NOT NULL,
  description      text,
  hierarchy_level  int    NOT NULL DEFAULT 100,           -- lower = more privileged (Super Admin=0)
  is_system        boolean NOT NULL DEFAULT false,        -- system roles cannot be deleted
  is_active        boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE roles IS 'Application roles (Super Admin ... Viewer). Codes mirrored in config/app.config.js ROLES.';
CREATE INDEX IF NOT EXISTS idx_roles_hierarchy ON roles (hierarchy_level);

-- ---- Permissions ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS permissions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         citext NOT NULL UNIQUE,                    -- e.g. 'ecm.create', 'workflow.transition'
  module       text   NOT NULL,                           -- e.g. 'ecm','workflow','document','admin'
  action       text   NOT NULL,                           -- e.g. 'create','read','update','delete','approve'
  description  text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE permissions IS 'Fine-grained permission catalog referenced by RLS via fn_has_permission().';
CREATE INDEX IF NOT EXISTS idx_permissions_module ON permissions (module);

-- ---- Role ↔ Permission matrix ----------------------------------------------
CREATE TABLE IF NOT EXISTS role_permissions (
  role_id        uuid NOT NULL REFERENCES roles(id)        ON DELETE CASCADE,
  permission_id  uuid NOT NULL REFERENCES permissions(id)  ON DELETE CASCADE,
  granted_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission ON role_permissions (permission_id);

-- ---- Profiles (1:1 with auth.users) ----------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
  id                 uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email              citext NOT NULL UNIQUE,
  full_name          text   NOT NULL DEFAULT '',
  employee_no        text   UNIQUE,
  job_title          text,
  phone              text,
  avatar_url         text,
  department_id      uuid,                                  -- FK added in 0003 (org tables)
  plant_id           uuid,                                  -- FK added in 0003
  manager_id         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  azure_ad_object_id text UNIQUE,                           -- Entra ID objectId for SSO mapping
  locale             text NOT NULL DEFAULT 'en',
  theme              text NOT NULL DEFAULT 'system' CHECK (theme IN ('light','dark','system')),
  is_active          boolean NOT NULL DEFAULT true,
  last_login_at      timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE profiles IS 'User profile, 1:1 with auth.users; synchronized from Entra ID (Module 13).';
CREATE INDEX IF NOT EXISTS idx_profiles_department ON profiles (department_id);
CREATE INDEX IF NOT EXISTS idx_profiles_plant      ON profiles (plant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_manager    ON profiles (manager_id);
CREATE INDEX IF NOT EXISTS idx_profiles_active     ON profiles (is_active) WHERE is_active;

-- ---- User ↔ Role assignments (a user may hold several roles, optionally plant-scoped) ----
CREATE TABLE IF NOT EXISTS user_roles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  role_id      uuid NOT NULL REFERENCES roles(id)     ON DELETE CASCADE,
  plant_id     uuid,                                    -- NULL = global; else scoped to a plant (FK in 0003)
  assigned_by  uuid REFERENCES profiles(id) ON DELETE SET NULL,
  assigned_at  timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz,
  UNIQUE (user_id, role_id, plant_id)
);
COMMENT ON TABLE user_roles IS 'Assignment of roles to users, optionally scoped to a plant.';
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles (user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles (role_id);

-- ---- updated_at triggers ----------------------------------------------------
CREATE TRIGGER trg_roles_updated    BEFORE UPDATE ON roles    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0003_organization.sql
-- =============================================================================
-- 0003_organization.sql
-- Module 1: Organization master data — plants, departments, customers, suppliers.
-- Also closes the cross-table FKs deferred from 0002 (profiles/user_roles).
-- =============================================================================

-- ---- Plants -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS plants (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        citext NOT NULL UNIQUE,               -- e.g. 'DK01'
  name        text   NOT NULL,
  address     text,
  city        text,
  country     text,
  timezone    text NOT NULL DEFAULT 'UTC',
  d365_site_id text,                                 -- Dynamics 365 Site/Warehouse mapping
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE plants IS 'Manufacturing plants / sites. Roles and ECMs can be scoped per plant.';

-- ---- Departments (self-referential hierarchy) -------------------------------
CREATE TABLE IF NOT EXISTS departments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          citext NOT NULL UNIQUE,
  name          text   NOT NULL,
  description   text,
  parent_id     uuid REFERENCES departments(id) ON DELETE SET NULL,
  head_user_id  uuid REFERENCES profiles(id)    ON DELETE SET NULL,
  plant_id      uuid REFERENCES plants(id)      ON DELETE SET NULL,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE departments IS 'Organizational units (Quality, Production, Planning, Purchasing, Warehouse, Finance, Engineering...).';
CREATE INDEX IF NOT EXISTS idx_departments_parent ON departments (parent_id);
CREATE INDEX IF NOT EXISTS idx_departments_plant  ON departments (plant_id);

-- ---- Customers --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           citext NOT NULL UNIQUE,
  name           text   NOT NULL,
  d365_account_id text UNIQUE,                        -- Dynamics 365 CustAccount
  country        text,
  contact_name   text,
  contact_email  citext,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE customers IS 'Customers impacted by / requesting changes. Synced from D365 (Module 12).';

-- ---- Suppliers / Vendors ----------------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           citext NOT NULL UNIQUE,
  name           text   NOT NULL,
  d365_vendor_id text UNIQUE,                          -- Dynamics 365 VendAccount
  country        text,
  contact_name   text,
  contact_email  citext,
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE suppliers IS 'Suppliers/vendors affected by changes. Synced from D365 (Module 12).';

-- ---- Close deferred FKs from 0002 ------------------------------------------
ALTER TABLE profiles
  ADD CONSTRAINT fk_profiles_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_profiles_plant      FOREIGN KEY (plant_id)      REFERENCES plants(id)      ON DELETE SET NULL;
ALTER TABLE user_roles
  ADD CONSTRAINT fk_user_roles_plant    FOREIGN KEY (plant_id)      REFERENCES plants(id)      ON DELETE CASCADE;

-- ---- updated_at triggers ----------------------------------------------------
CREATE TRIGGER trg_plants_updated      BEFORE UPDATE ON plants      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_departments_updated BEFORE UPDATE ON departments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_customers_updated   BEFORE UPDATE ON customers   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_suppliers_updated   BEFORE UPDATE ON suppliers   FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0004_workflow_engine.sql
-- =============================================================================
-- 0004_workflow_engine.sql
-- Module 1 / Module 6 foundation: DATA-DRIVEN workflow engine.
-- The change process lives entirely in these tables (imported from ECM Flow.xlsx
-- via supabase/seed/30_workflow.sql). Nothing about the flow is hardcoded.
-- =============================================================================

-- ---- Workflow definitions (versioned) --------------------------------------
CREATE TABLE IF NOT EXISTS wf_workflows (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            citext NOT NULL,
  name            text   NOT NULL,
  version         int    NOT NULL DEFAULT 1,
  description     text,
  source_document text,                                   -- provenance, e.g. 'ECM Flow.xlsx'
  is_active       boolean NOT NULL DEFAULT true,
  effective_from  date   NOT NULL DEFAULT CURRENT_DATE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code, version)
);
COMMENT ON TABLE wf_workflows IS 'Versioned workflow definitions. Multiple versions may coexist; one active per code.';

-- ---- State categories (editable lookup; drives colours/semantics) ----------
CREATE TABLE IF NOT EXISTS wf_state_categories (
  code                citext PRIMARY KEY,
  name                text NOT NULL,
  description         text,
  is_terminal_default boolean NOT NULL DEFAULT false,
  color               text,
  sort_order          int NOT NULL DEFAULT 100
);
COMMENT ON TABLE wf_state_categories IS 'Semantic buckets for states (draft, approval, hold, rejected...). Covers the spec status set.';

INSERT INTO wf_state_categories (code, name, description, is_terminal_default, color, sort_order) VALUES
  ('draft',       'Draft',        'Being prepared by the requestor',           false, '#94A3B8', 10),
  ('screening',   'Screening',    'Under initial review / go-ahead decision',  false, '#F59E0B', 20),
  ('in_progress', 'In Progress',  'Actively being worked',                     false, '#0EA5E9', 30),
  ('review',      'Review',       'Under review / evaluation',                 false, '#6366F1', 35),
  ('approval',    'Approval',     'Awaiting a board / gate decision',          false, '#8B5CF6', 40),
  ('accepted',    'Accepted',     'Accepted; progressing to next stage',       false, '#14B8A6', 50),
  ('hold',        'Hold',         'Temporarily paused',                        false, '#FB923C', 60),
  ('backlog',     'Backlog',      'Deferred, awaiting opportunity',            false, '#64748B', 70),
  ('returned',    'Returned',     'Sent back for rework',                      false, '#EAB308', 80),
  ('support',     'Support',      'Awaiting support / external input',         false, '#06B6D4', 85),
  ('rejected',    'Rejected',     'Rejected — no action',                      true,  '#EF4444', 90),
  ('cancelled',   'Cancelled',    'Cancelled — solved elsewhere',              true,  '#F43F5E', 100),
  ('resolved',    'Resolved',     'Successfully implemented and closed',       true,  '#22C55E', 110),
  ('completed',   'Completed',    'Completed',                                 true,  '#16A34A', 120)
ON CONFLICT (code) DO NOTHING;

-- ---- Stages (major phases of a workflow) -----------------------------------
CREATE TABLE IF NOT EXISTS wf_stages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  code        citext NOT NULL,
  name        text   NOT NULL,
  sequence    int    NOT NULL DEFAULT 0,
  entity_type text   NOT NULL DEFAULT 'ECM' CHECK (entity_type IN ('ECM','ECR','ECO')),
  color       text,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, code)
);
CREATE INDEX IF NOT EXISTS idx_wf_stages_workflow ON wf_stages (workflow_id, sequence);

-- ---- States (nodes of the state machine) -----------------------------------
CREATE TABLE IF NOT EXISTS wf_states (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  stage_id    uuid NOT NULL REFERENCES wf_stages(id)    ON DELETE CASCADE,
  code        citext NOT NULL,
  name        text   NOT NULL,
  sequence    int    NOT NULL DEFAULT 0,
  category    citext NOT NULL REFERENCES wf_state_categories(code),
  is_initial  boolean NOT NULL DEFAULT false,
  is_terminal boolean NOT NULL DEFAULT false,
  sla_hours   int,                                        -- target dwell time; feeds overdue/bottleneck analytics
  color       text,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, code)
);
CREATE INDEX IF NOT EXISTS idx_wf_states_stage    ON wf_states (stage_id, sequence);
CREATE INDEX IF NOT EXISTS idx_wf_states_category ON wf_states (category);
-- At most one initial state per stage.
CREATE UNIQUE INDEX IF NOT EXISTS uq_wf_states_initial_per_stage ON wf_states (stage_id) WHERE is_initial;

-- ---- Transitions (edges; who can move what, and side effects) --------------
CREATE TABLE IF NOT EXISTS wf_transitions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id         uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  from_state_id       uuid REFERENCES wf_states(id) ON DELETE CASCADE,   -- NULL = creation/entry edge
  to_state_id         uuid NOT NULL REFERENCES wf_states(id) ON DELETE CASCADE,
  action_code         citext NOT NULL,
  action_label        text   NOT NULL,
  required_permission citext,                              -- checked by fn_has_permission()
  requires_comment    boolean NOT NULL DEFAULT false,
  requires_approval   boolean NOT NULL DEFAULT false,
  side_effect         text CHECK (side_effect IN ('create_ecr','create_eco','close_ecm')),
  guard_expression    text,                                -- optional SQL boolean guard (evaluated by engine)
  sort_order          int NOT NULL DEFAULT 0,
  is_active           boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, from_state_id, action_code, to_state_id)
);
CREATE INDEX IF NOT EXISTS idx_wf_transitions_from ON wf_transitions (from_state_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_wf_transitions_to   ON wf_transitions (to_state_id);

-- ---- Task templates (checklist per state; seeded with sequence numbers) ----
CREATE TABLE IF NOT EXISTS wf_task_templates (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id              uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  stage_id                 uuid NOT NULL REFERENCES wf_stages(id)    ON DELETE CASCADE,
  state_id                 uuid NOT NULL REFERENCES wf_states(id)    ON DELETE CASCADE,
  seq_number               int  NOT NULL DEFAULT 0,
  title                    text NOT NULL,
  description              text,
  task_type                text NOT NULL DEFAULT 'task'
                             CHECK (task_type IN ('task','decision','review','meeting','approval','implementation','notification','integration')),
  is_mandatory             boolean NOT NULL DEFAULT true,
  default_assignee_role_id uuid REFERENCES roles(id) ON DELETE SET NULL,
  sla_hours                int,
  checklist                jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wf_task_templates_state ON wf_task_templates (state_id, seq_number);
CREATE INDEX IF NOT EXISTS idx_wf_task_templates_wf    ON wf_task_templates (workflow_id, stage_id);

-- ---- updated_at trigger -----------------------------------------------------
CREATE TRIGGER trg_wf_workflows_updated BEFORE UPDATE ON wf_workflows FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0005_items_bom.sql
-- =============================================================================
-- 0005_items_bom.sql
-- Module 1: Item master & Bill of Materials (mirrors D365 F&O released products).
-- =============================================================================

CREATE TABLE IF NOT EXISTS items (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_number    citext NOT NULL UNIQUE,
  name           text   NOT NULL,
  description    text,
  uom            text   NOT NULL DEFAULT 'ea',
  item_type      text   NOT NULL DEFAULT 'manufactured'
                   CHECK (item_type IN ('purchased','manufactured','service','phantom')),
  product_dimension text,
  revision       text   NOT NULL DEFAULT 'A',
  lifecycle_state text  NOT NULL DEFAULT 'active'
                   CHECK (lifecycle_state IN ('draft','active','engineering_hold','obsolete')),
  unit_cost      numeric(14,4),
  currency       text   NOT NULL DEFAULT 'EUR',
  d365_item_id   text   UNIQUE,                         -- D365 released product number
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE items IS 'Item / part master. Synced with D365 released products (Module 12).';
CREATE INDEX IF NOT EXISTS idx_items_type      ON items (item_type);
CREATE INDEX IF NOT EXISTS idx_items_lifecycle ON items (lifecycle_state);

CREATE TABLE IF NOT EXISTS boms (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bom_number   citext NOT NULL UNIQUE,
  item_id      uuid NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  name         text,
  version      int  NOT NULL DEFAULT 1,
  is_active     boolean NOT NULL DEFAULT true,
  approved_at   timestamptz,
  approved_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  d365_bom_id   text UNIQUE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (item_id, version)
);
COMMENT ON TABLE boms IS 'Bill of materials headers, versioned per parent item.';
CREATE INDEX IF NOT EXISTS idx_boms_item ON boms (item_id);

CREATE TABLE IF NOT EXISTS bom_lines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bom_id            uuid NOT NULL REFERENCES boms(id) ON DELETE CASCADE,
  line_no           int  NOT NULL,
  component_item_id uuid NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  quantity          numeric(18,6) NOT NULL DEFAULT 1,
  uom               text NOT NULL DEFAULT 'ea',
  position          text,
  ref_designator    text,
  valid_from        date,
  valid_to          date,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (bom_id, line_no)
);
CREATE INDEX IF NOT EXISTS idx_bom_lines_bom       ON bom_lines (bom_id);
CREATE INDEX IF NOT EXISTS idx_bom_lines_component ON bom_lines (component_item_id);

CREATE TRIGGER trg_items_updated BEFORE UPDATE ON items FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_boms_updated  BEFORE UPDATE ON boms  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0006_ecm_core.sql
-- =============================================================================
-- 0006_ecm_core.sql
-- Module 1: Core change records — ECM master, ECR, ECO, links, affected items,
-- and the append-only state transition history.
-- =============================================================================

-- ---- ECM master request -----------------------------------------------------
CREATE TABLE IF NOT EXISTS ecm_requests (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_number                citext UNIQUE,                       -- generated by trigger (0009)
  title                     text NOT NULL,
  description               text,
  reason                    text,
  change_type               text NOT NULL DEFAULT 'standard'
                              CHECK (change_type IN ('standard','emergency','deviation','pre_series','cost_down')),
  affected_part_number      text,
  affected_bom              text,
  primary_item_id           uuid REFERENCES items(id)     ON DELETE SET NULL,
  customer_id               uuid REFERENCES customers(id) ON DELETE SET NULL,
  supplier_id               uuid REFERENCES suppliers(id) ON DELETE SET NULL,
  department_id             uuid REFERENCES departments(id) ON DELETE SET NULL,
  plant_id                  uuid REFERENCES plants(id)    ON DELETE SET NULL,
  priority                  priority_level NOT NULL DEFAULT 'medium',
  risk_level                risk_level     NOT NULL DEFAULT 'low',
  cost_impact               numeric(14,2),
  cost_currency             text NOT NULL DEFAULT 'EUR',
  owner_id                  uuid REFERENCES profiles(id)  ON DELETE SET NULL,
  requestor_id              uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  -- workflow position (all FKs into the data-driven engine)
  workflow_id               uuid REFERENCES wf_workflows(id) ON DELETE SET NULL,
  current_stage_id          uuid REFERENCES wf_stages(id)    ON DELETE SET NULL,
  current_state_id          uuid REFERENCES wf_states(id)    ON DELETE SET NULL,
  status_category           citext REFERENCES wf_state_categories(code),  -- denormalized cache (trigger-maintained)
  state_entered_at          timestamptz NOT NULL DEFAULT now(),
  source                    change_source NOT NULL DEFAULT 'manual',
  d365_reference            text,
  created_date              date NOT NULL DEFAULT CURRENT_DATE,
  due_date                  date,
  target_implementation_date date,
  closed_at                 timestamptz,
  search_tsv                tsvector,                           -- maintained in 0008
  is_deleted                boolean NOT NULL DEFAULT false,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  created_by                uuid REFERENCES profiles(id) ON DELETE SET NULL,
  updated_by                uuid REFERENCES profiles(id) ON DELETE SET NULL
);
COMMENT ON TABLE ecm_requests IS 'Master engineering change record. Progresses through the data-driven workflow.';
CREATE INDEX IF NOT EXISTS idx_ecm_state       ON ecm_requests (current_state_id);
CREATE INDEX IF NOT EXISTS idx_ecm_stage       ON ecm_requests (current_stage_id);
CREATE INDEX IF NOT EXISTS idx_ecm_status_cat  ON ecm_requests (status_category);
CREATE INDEX IF NOT EXISTS idx_ecm_plant       ON ecm_requests (plant_id);
CREATE INDEX IF NOT EXISTS idx_ecm_department  ON ecm_requests (department_id);
CREATE INDEX IF NOT EXISTS idx_ecm_owner       ON ecm_requests (owner_id);
CREATE INDEX IF NOT EXISTS idx_ecm_requestor   ON ecm_requests (requestor_id);
CREATE INDEX IF NOT EXISTS idx_ecm_priority    ON ecm_requests (priority);
CREATE INDEX IF NOT EXISTS idx_ecm_due         ON ecm_requests (due_date) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS idx_ecm_created     ON ecm_requests (created_at);
CREATE INDEX IF NOT EXISTS idx_ecm_active      ON ecm_requests (is_deleted) WHERE NOT is_deleted;

-- ---- ECR (Engineering Change Request) --------------------------------------
CREATE TABLE IF NOT EXISTS ecr_records (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecr_number        citext UNIQUE,                               -- generated by trigger (0009)
  ecm_request_id    uuid NOT NULL REFERENCES ecm_requests(id) ON DELETE CASCADE,
  title             text NOT NULL,
  solution_description text,
  impact_analysis   text,
  current_state_id  uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  status_category   citext REFERENCES wf_state_categories(code),
  state_entered_at  timestamptz NOT NULL DEFAULT now(),
  crb_meeting_date  date,
  priority          priority_level NOT NULL DEFAULT 'medium',
  risk_level        risk_level     NOT NULL DEFAULT 'low',
  owner_id          uuid REFERENCES profiles(id) ON DELETE SET NULL,
  d365_ecr_id       text UNIQUE,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid REFERENCES profiles(id) ON DELETE SET NULL
);
COMMENT ON TABLE ecr_records IS 'Engineering Change Request spawned from an accepted pre-request.';
CREATE INDEX IF NOT EXISTS idx_ecr_ecm   ON ecr_records (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_ecr_state ON ecr_records (current_state_id);

-- ---- ECO (Engineering Change Order) ----------------------------------------
CREATE TABLE IF NOT EXISTS eco_records (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  eco_number          citext UNIQUE,                             -- generated by trigger (0009)
  ecm_request_id      uuid NOT NULL REFERENCES ecm_requests(id) ON DELETE CASCADE,
  ecr_record_id       uuid REFERENCES ecr_records(id) ON DELETE SET NULL,
  title               text NOT NULL,
  implementation_plan text,
  current_state_id    uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  status_category     citext REFERENCES wf_state_categories(code),
  state_entered_at    timestamptz NOT NULL DEFAULT now(),
  planned_release_date date,
  actual_release_date  date,
  ppap_status         text CHECK (ppap_status IN ('not_required','pending','submitted','approved','rejected')),
  owner_id            uuid REFERENCES profiles(id) ON DELETE SET NULL,
  d365_eco_id         text UNIQUE,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES profiles(id) ON DELETE SET NULL
);
COMMENT ON TABLE eco_records IS 'Engineering Change Order spawned from an accepted ECR; drives implementation.';
CREATE INDEX IF NOT EXISTS idx_eco_ecm   ON eco_records (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_eco_ecr   ON eco_records (ecr_record_id);
CREATE INDEX IF NOT EXISTS idx_eco_state ON eco_records (current_state_id);

-- ---- Generic entity links (Related ECM / ECR / ECO / items) ----------------
CREATE TABLE IF NOT EXISTS ecm_links (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type   entity_type NOT NULL,
  source_id     uuid NOT NULL,
  target_type   entity_type NOT NULL,
  target_id     uuid NOT NULL,
  relation_type text NOT NULL DEFAULT 'related'
                  CHECK (relation_type IN ('related','duplicate','supersedes','superseded_by','blocks','blocked_by','caused_by','derived_from')),
  note          text,
  created_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_type, source_id, target_type, target_id, relation_type),
  CHECK (NOT (source_type = target_type AND source_id = target_id))
);
CREATE INDEX IF NOT EXISTS idx_ecm_links_source ON ecm_links (source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_ecm_links_target ON ecm_links (target_type, target_id);

-- ---- Affected items / BOM ---------------------------------------------------
CREATE TABLE IF NOT EXISTS ecm_affected_items (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_request_id uuid NOT NULL REFERENCES ecm_requests(id) ON DELETE CASCADE,
  item_id        uuid NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  bom_id         uuid REFERENCES boms(id) ON DELETE SET NULL,
  change_kind    text NOT NULL DEFAULT 'modify'
                   CHECK (change_kind IN ('add','modify','remove','replace')),
  from_revision  text,
  to_revision    text,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ecm_request_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_affected_items_item ON ecm_affected_items (item_id);

-- ---- State transition history (append-only; powers timeline + analytics) ---
CREATE TABLE IF NOT EXISTS ecm_state_history (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  entity_type    entity_type NOT NULL,
  entity_id      uuid NOT NULL,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,  -- denormalized for fast joins
  workflow_id    uuid REFERENCES wf_workflows(id) ON DELETE SET NULL,
  from_state_id  uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  to_state_id    uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  transition_id  uuid REFERENCES wf_transitions(id) ON DELETE SET NULL,
  action_code    citext,
  performed_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  performed_at   timestamptz NOT NULL DEFAULT now(),
  comment        text,
  dwell_seconds  bigint                                            -- time spent in from_state
);
CREATE INDEX IF NOT EXISTS idx_state_history_entity ON ecm_state_history (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_state_history_ecm    ON ecm_state_history (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_state_history_to     ON ecm_state_history (to_state_id);
CREATE INDEX IF NOT EXISTS idx_state_history_when   ON ecm_state_history (performed_at);

-- ---- updated_at triggers ----------------------------------------------------
CREATE TRIGGER trg_ecm_updated BEFORE UPDATE ON ecm_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ecr_updated BEFORE UPDATE ON ecr_records  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_eco_updated BEFORE UPDATE ON eco_records  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0007_tasks.sql
-- =============================================================================
-- 0007_tasks.sql
-- Module 1 / Module 8: Task management — Kanban / List / Calendar / Gantt.
-- Tasks are instantiated from wf_task_templates on state entry (see 0017 engine).
-- =============================================================================

CREATE TABLE IF NOT EXISTS ecm_tasks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_request_id  uuid NOT NULL REFERENCES ecm_requests(id) ON DELETE CASCADE,
  entity_type     entity_type NOT NULL DEFAULT 'ecm',        -- ecm | ecr | eco this task belongs to
  entity_id       uuid NOT NULL,
  template_id     uuid REFERENCES wf_task_templates(id) ON DELETE SET NULL,  -- NULL = ad-hoc
  stage_id        uuid REFERENCES wf_stages(id) ON DELETE SET NULL,
  state_id        uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  parent_task_id  uuid REFERENCES ecm_tasks(id) ON DELETE CASCADE,           -- subtasks
  seq_number      int  NOT NULL DEFAULT 0,
  title           text NOT NULL,
  description     text,
  task_type       text NOT NULL DEFAULT 'task'
                    CHECK (task_type IN ('task','decision','review','meeting','approval','implementation','notification','integration')),
  status          task_status NOT NULL DEFAULT 'todo',
  progress_pct    int NOT NULL DEFAULT 0 CHECK (progress_pct BETWEEN 0 AND 100),
  priority        priority_level NOT NULL DEFAULT 'medium',
  assignee_id     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  assignee_role_id uuid REFERENCES roles(id)   ON DELETE SET NULL,
  is_mandatory    boolean NOT NULL DEFAULT true,
  sort_order      int NOT NULL DEFAULT 0,                    -- board / gantt ordering
  start_date      date,
  due_date        date,
  started_at      timestamptz,
  completed_at    timestamptz,
  completed_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  checklist       jsonb NOT NULL DEFAULT '[]'::jsonb,        -- lightweight inline checklist mirror
  created_by      uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ecm_tasks IS 'Work items for a change record; support Kanban, list, calendar, timeline and Gantt views.';
CREATE INDEX IF NOT EXISTS idx_tasks_ecm       ON ecm_tasks (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_tasks_entity    ON ecm_tasks (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee  ON ecm_tasks (assignee_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status    ON ecm_tasks (status);
CREATE INDEX IF NOT EXISTS idx_tasks_state     ON ecm_tasks (state_id);
CREATE INDEX IF NOT EXISTS idx_tasks_due       ON ecm_tasks (due_date) WHERE status <> 'done';
CREATE INDEX IF NOT EXISTS idx_tasks_parent    ON ecm_tasks (parent_task_id);

-- ---- Task dependencies (Gantt links) ---------------------------------------
CREATE TABLE IF NOT EXISTS ecm_task_dependencies (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id           uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  depends_on_task_id uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  dependency_type   text NOT NULL DEFAULT 'finish_to_start'
                      CHECK (dependency_type IN ('finish_to_start','start_to_start','finish_to_finish','start_to_finish')),
  lag_hours         int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, depends_on_task_id),
  CHECK (task_id <> depends_on_task_id)
);
CREATE INDEX IF NOT EXISTS idx_task_deps_task    ON ecm_task_dependencies (task_id);
CREATE INDEX IF NOT EXISTS idx_task_deps_depends ON ecm_task_dependencies (depends_on_task_id);

-- ---- Normalized checklist items (per task) ---------------------------------
CREATE TABLE IF NOT EXISTS task_checklist_items (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id    uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  position   int  NOT NULL DEFAULT 0,
  label      text NOT NULL,
  is_done    boolean NOT NULL DEFAULT false,
  done_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  done_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_checklist_task ON task_checklist_items (task_id, position);

-- ---- Reminders --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_reminders (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id    uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  remind_at  timestamptz NOT NULL,
  channel    notification_channel NOT NULL DEFAULT 'in_app',
  is_sent    boolean NOT NULL DEFAULT false,
  sent_at    timestamptz,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reminders_due ON task_reminders (remind_at) WHERE NOT is_sent;

CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON ecm_tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0008_documents.sql
-- =============================================================================
-- 0008_documents.sql
-- Module 1 / Module 9: Document management — versioning, check-in/out, e-signatures.
-- Binary content lives in Supabase Storage; these tables hold metadata + pointers.
-- =============================================================================

CREATE TABLE IF NOT EXISTS document_categories (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code               citext NOT NULL UNIQUE,
  name               text NOT NULL,
  description        text,
  allowed_extensions text[] NOT NULL DEFAULT '{}',
  requires_approval  boolean NOT NULL DEFAULT false,
  retention_months   int,
  created_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE document_categories IS 'Engineering drawings, CAD, specs, work instructions, etc.';

CREATE TABLE IF NOT EXISTS documents (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_number         citext UNIQUE,
  entity_type        entity_type NOT NULL DEFAULT 'ecm',
  entity_id          uuid NOT NULL,
  ecm_request_id     uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,   -- denormalized rollup
  category_id        uuid REFERENCES document_categories(id) ON DELETE SET NULL,
  name               text NOT NULL,
  description        text,
  doc_type           text NOT NULL DEFAULT 'other'
                       CHECK (doc_type IN ('drawing','cad','pdf','word','excel','image','specification','work_instruction','other')),
  status             document_status NOT NULL DEFAULT 'draft',
  current_version_id uuid,                                    -- FK added after document_versions
  is_checked_out     boolean NOT NULL DEFAULT false,
  checked_out_by     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  checked_out_at     timestamptz,
  created_by         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE documents IS 'Controlled documents attached to a change record; one row per logical document.';
CREATE INDEX IF NOT EXISTS idx_documents_entity ON documents (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_documents_ecm    ON documents (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents (status);

CREATE TABLE IF NOT EXISTS document_versions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id    uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  version_no     int  NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'ecm-documents',
  storage_path   text NOT NULL,
  file_name      text,
  file_size      bigint,
  mime_type      text,
  checksum       text,                                      -- sha256 for integrity
  status         document_status NOT NULL DEFAULT 'draft',
  change_note    text,
  is_current     boolean NOT NULL DEFAULT false,
  uploaded_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  uploaded_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, version_no)
);
CREATE INDEX IF NOT EXISTS idx_doc_versions_document ON document_versions (document_id, version_no DESC);
-- exactly one current version per document
CREATE UNIQUE INDEX IF NOT EXISTS uq_doc_versions_current ON document_versions (document_id) WHERE is_current;

ALTER TABLE documents
  ADD CONSTRAINT fk_documents_current_version
  FOREIGN KEY (current_version_id) REFERENCES document_versions(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS document_signatures (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_version_id uuid NOT NULL REFERENCES document_versions(id) ON DELETE CASCADE,
  signer_id           uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  meaning             signature_meaning NOT NULL DEFAULT 'approved',
  signature_hash      text NOT NULL,                        -- HMAC over version checksum + signer + timestamp
  method              text NOT NULL DEFAULT 'password' CHECK (method IN ('password','azure_ad','otp')),
  ip_address          inet,
  comment             text,
  signed_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_version_id, signer_id, meaning)
);
COMMENT ON TABLE document_signatures IS '21 CFR Part 11-style e-signatures bound to a specific document version.';
CREATE INDEX IF NOT EXISTS idx_signatures_version ON document_signatures (document_version_id);

CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0009_comments_attachments.sql
-- =============================================================================
-- 0009_comments_attachments.sql
-- Module 1: Collaboration — threaded comments with @mentions, generic attachments.
-- Polymorphic (entity_type/entity_id) so any record can be discussed / annotated.
-- =============================================================================

CREATE TABLE IF NOT EXISTS comments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type       entity_type NOT NULL,
  entity_id         uuid NOT NULL,
  parent_comment_id uuid REFERENCES comments(id) ON DELETE CASCADE,
  author_id         uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  body              text NOT NULL,
  mentions          uuid[] NOT NULL DEFAULT '{}',            -- profile ids @-mentioned
  is_internal       boolean NOT NULL DEFAULT false,          -- hidden from external/viewer roles
  is_deleted        boolean NOT NULL DEFAULT false,
  edited_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE comments IS 'Threaded discussion attached to any entity; mentions drive notifications.';
CREATE INDEX IF NOT EXISTS idx_comments_entity   ON comments (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent   ON comments (parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_comments_author   ON comments (author_id);
CREATE INDEX IF NOT EXISTS idx_comments_mentions ON comments USING gin (mentions);

CREATE TABLE IF NOT EXISTS attachments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type    entity_type NOT NULL,
  entity_id      uuid NOT NULL,
  name           text NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'ecm-attachments',
  storage_path   text NOT NULL,
  file_size      bigint,
  mime_type      text,
  uploaded_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_attachments_entity ON attachments (entity_type, entity_id);

CREATE TRIGGER trg_comments_updated BEFORE UPDATE ON comments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0010_approvals.sql
-- =============================================================================
-- 0010_approvals.sql
-- Module 1 / Module 10: Approval workflow + email approval (Approve/Reject/Return).
-- Approvals gate wf_transitions where requires_approval = true.
-- =============================================================================

CREATE TABLE IF NOT EXISTS approval_requests (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type    entity_type NOT NULL,
  entity_id      uuid NOT NULL,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  stage_id       uuid REFERENCES wf_stages(id) ON DELETE SET NULL,
  state_id       uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  transition_id  uuid REFERENCES wf_transitions(id) ON DELETE SET NULL,
  title          text NOT NULL,
  description    text,
  policy         approval_policy NOT NULL DEFAULT 'any',
  quorum         int,                                          -- required approvals when policy = 'quorum'
  status         approval_status NOT NULL DEFAULT 'pending',
  requested_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  due_at         timestamptz,
  decided_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE approval_requests IS 'A gate awaiting one or more approvers before a transition may fire.';
CREATE INDEX IF NOT EXISTS idx_approvals_entity ON approval_requests (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_approvals_ecm    ON approval_requests (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON approval_requests (status);

CREATE TABLE IF NOT EXISTS approval_assignments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_request_id uuid NOT NULL REFERENCES approval_requests(id) ON DELETE CASCADE,
  sequence            int NOT NULL DEFAULT 1,                  -- ordering for sequential policy
  approver_id         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  approver_role_id    uuid REFERENCES roles(id) ON DELETE SET NULL,
  decision            approval_decision NOT NULL DEFAULT 'pending',
  decision_at         timestamptz,
  comment             text,
  delegated_to        uuid REFERENCES profiles(id) ON DELETE SET NULL,
  escalated_to        uuid REFERENCES profiles(id) ON DELETE SET NULL,
  notified_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (approver_id IS NOT NULL OR approver_role_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_appr_assign_request  ON approval_assignments (approval_request_id, sequence);
CREATE INDEX IF NOT EXISTS idx_appr_assign_approver ON approval_assignments (approver_id);
CREATE INDEX IF NOT EXISTS idx_appr_assign_pending  ON approval_assignments (decision) WHERE decision = 'pending';

-- ---- Email approval tokens (single-use, signed, expiring) ------------------
CREATE TABLE IF NOT EXISTS approval_email_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES approval_assignments(id) ON DELETE CASCADE,
  token         text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  action_scope  text[] NOT NULL DEFAULT ARRAY['approve','reject','return','comment'],
  expires_at    timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  used_at       timestamptz,
  used_action   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_appr_tokens_assignment ON approval_email_tokens (assignment_id);

CREATE TRIGGER trg_approvals_updated BEFORE UPDATE ON approval_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0011_notifications_email.sql
-- =============================================================================
-- 0011_notifications_email.sql
-- Module 1 / Module 11: Notifications (realtime bell), notification rules,
-- per-user preferences, and email templates.
-- =============================================================================

CREATE TABLE IF NOT EXISTS email_templates (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       citext NOT NULL UNIQUE,
  name       text NOT NULL,
  subject    text NOT NULL,
  body_html  text NOT NULL,
  body_text  text,
  variables  jsonb NOT NULL DEFAULT '[]'::jsonb,               -- documented merge fields
  channel    notification_channel NOT NULL DEFAULT 'email',
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE email_templates IS 'Reusable templates for approval, reminder, escalation and assignment emails.';

CREATE TABLE IF NOT EXISTS notification_rules (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 citext NOT NULL UNIQUE,
  event_type           text NOT NULL,                          -- e.g. 'ecm.transition','task.assigned','approval.pending'
  description          text,
  channel              notification_channel NOT NULL DEFAULT 'in_app',
  template_id          uuid REFERENCES email_templates(id) ON DELETE SET NULL,
  recipient_expression text NOT NULL DEFAULT 'owner',          -- owner|requestor|assignee|role:CODE|mentions|manager
  is_active            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notification_rules IS 'Declarative mapping of events to channels, templates and recipients (Admin-editable).';
CREATE INDEX IF NOT EXISTS idx_notif_rules_event ON notification_rules (event_type) WHERE is_active;

CREATE TABLE IF NOT EXISTS notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type         text NOT NULL,
  title        text NOT NULL,
  body         text,
  entity_type  entity_type,
  entity_id    uuid,
  priority     priority_level NOT NULL DEFAULT 'medium',
  channel      notification_channel NOT NULL DEFAULT 'in_app',
  action_url   text,
  meta         jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_read      boolean NOT NULL DEFAULT false,
  read_at      timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notifications IS 'In-app / multi-channel notifications; realtime via Supabase (Module 11).';
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications (recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_unread    ON notifications (recipient_id) WHERE NOT is_read;

CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id    uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  channel    notification_channel NOT NULL,
  enabled    boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, event_type, channel)
);

CREATE TRIGGER trg_email_templates_updated BEFORE UPDATE ON email_templates    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_notif_rules_updated     BEFORE UPDATE ON notification_rules FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0012_audit.sql
-- =============================================================================
-- 0012_audit.sql
-- Module 1 / Module 18: Field-level audit trail.
-- Generic trigger (0017) writes ONE row per changed field on UPDATE, plus
-- row snapshots on INSERT/DELETE. Context (ip/browser/device) comes from GUCs.
-- =============================================================================

CREATE TABLE IF NOT EXISTS audit_logs (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_name   text NOT NULL,
  record_id    uuid,
  entity_type  entity_type,
  action       audit_action NOT NULL,
  field_name   text,                                         -- populated per-field on UPDATE
  old_value    text,
  new_value    text,
  row_snapshot jsonb,                                        -- full row for INSERT / DELETE
  changed_by   uuid,                                         -- profile id (no FK: audit must survive user deletion)
  changed_at   timestamptz NOT NULL DEFAULT now(),
  ip_address   inet,
  user_agent   text,
  browser      text,
  device       text,
  session_id   text,
  request_id   text
);
COMMENT ON TABLE audit_logs IS 'Immutable field-level audit trail. Never updated/deleted by the app (enforced via RLS).';
CREATE INDEX IF NOT EXISTS idx_audit_record  ON audit_logs (table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_changed ON audit_logs (changed_by);
CREATE INDEX IF NOT EXISTS idx_audit_when    ON audit_logs (changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity  ON audit_logs (entity_type, record_id);

-- >>> supabase/migrations/0013_integration_api.sql
-- =============================================================================
-- 0013_integration_api.sql
-- Module 1 / Module 12: Integration plumbing — endpoints, API logs, sync state,
-- and a retryable D365 F&O outbound queue.
-- =============================================================================

CREATE TABLE IF NOT EXISTS integration_endpoints (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  system     text NOT NULL CHECK (system IN ('D365FO','GRAPH','POWERBI','SUPABASE','CUSTOM')),
  name       text NOT NULL,
  base_url   text,
  odata_path text,
  auth_type  text NOT NULL DEFAULT 'oauth2_client_credentials'
               CHECK (auth_type IN ('oauth2_client_credentials','oauth2_auth_code','api_key','none')),
  config     jsonb NOT NULL DEFAULT '{}'::jsonb,             -- non-secret settings; secrets live in env
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (system, name)
);
COMMENT ON TABLE integration_endpoints IS 'Configured external systems (D365 F&O, MS Graph, Power BI). Secrets are never stored here.';

CREATE TABLE IF NOT EXISTS api_logs (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  system          text NOT NULL,
  endpoint        text NOT NULL,
  method          text NOT NULL DEFAULT 'GET',
  direction       text NOT NULL DEFAULT 'outbound' CHECK (direction IN ('outbound','inbound')),
  entity_type     entity_type,
  entity_id       uuid,
  correlation_id  text,
  request_headers jsonb,
  request_payload jsonb,
  response_status int,
  response_payload jsonb,
  is_success      boolean NOT NULL DEFAULT false,
  error_message   text,
  duration_ms     int,
  retry_count     int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE api_logs IS 'Full request/response log for every integration call (Admin > API Logs).';
CREATE INDEX IF NOT EXISTS idx_api_logs_system  ON api_logs (system, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_logs_success ON api_logs (is_success);
CREATE INDEX IF NOT EXISTS idx_api_logs_corr    ON api_logs (correlation_id);

CREATE TABLE IF NOT EXISTS integration_sync_state (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  system         text NOT NULL,
  entity_type    entity_type NOT NULL,
  external_id    text NOT NULL,
  internal_id    uuid,
  direction      text NOT NULL DEFAULT 'inbound' CHECK (direction IN ('inbound','outbound','bidirectional')),
  last_synced_at timestamptz,
  sync_status    sync_status NOT NULL DEFAULT 'pending',
  checksum       text,
  message        text,
  UNIQUE (system, entity_type, external_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_state_internal ON integration_sync_state (internal_id);

CREATE TABLE IF NOT EXISTS d365_sync_queue (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation      text NOT NULL
                   CHECK (operation IN ('create_ecr','create_eco','update_item','update_bom',
                                        'update_product_version','attach_ecm','link_record','sync_status')),
  entity_type    entity_type,
  entity_id      uuid,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  status         sync_status NOT NULL DEFAULT 'pending',
  attempts       int NOT NULL DEFAULT 0,
  max_attempts   int NOT NULL DEFAULT 5,
  next_retry_at  timestamptz NOT NULL DEFAULT now(),
  last_error     text,
  correlation_id text,
  processed_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE d365_sync_queue IS 'Outbound operations to D365 F&O with retry/backoff; drained by an Edge Function (Module 12).';
CREATE INDEX IF NOT EXISTS idx_d365_queue_pending ON d365_sync_queue (status, next_retry_at) WHERE status IN ('pending','failed');

CREATE TRIGGER trg_endpoints_updated  BEFORE UPDATE ON integration_endpoints FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_d365_queue_updated BEFORE UPDATE ON d365_sync_queue        FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0014_ai_history.sql
-- =============================================================================
-- 0014_ai_history.sql
-- Module 1 / Module 15: AI Assistant history — conversations, messages, insights.
-- =============================================================================

CREATE TABLE IF NOT EXISTS ai_conversations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE SET NULL,
  title          text,
  context        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_conv_user ON ai_conversations (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_conv_ecm  ON ai_conversations (ecm_request_id);

CREATE TABLE IF NOT EXISTS ai_messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('system','user','assistant','tool')),
  content         text NOT NULL,
  tokens          int,
  model           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages (conversation_id, created_at);

CREATE TABLE IF NOT EXISTS ai_insights (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  entity_type    entity_type NOT NULL DEFAULT 'ecm',
  entity_id      uuid,
  insight_type   text NOT NULL
                   CHECK (insight_type IN ('summary','missing_info','suggested_docs','suggested_approvers',
                          'risk','priority','lead_time','similar','delay_prediction','tasks',
                          'exec_summary','meeting_minutes')),
  summary        text,
  content        jsonb NOT NULL DEFAULT '{}'::jsonb,
  model          text,
  confidence     numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),
  created_by     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai_insights IS 'Persisted AI outputs (summaries, risk, suggested approvers/docs, predictions).';
CREATE INDEX IF NOT EXISTS idx_ai_insights_ecm  ON ai_insights (ecm_request_id, insight_type);

CREATE TRIGGER trg_ai_conv_updated BEFORE UPDATE ON ai_conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- >>> supabase/migrations/0015_powerbi_reports.sql
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

-- >>> supabase/migrations/0016_qr_search.sql
-- =============================================================================
-- 0016_qr_search.sql
-- Module 1: QR codes for ECM/ECR/ECO and global search indexes (pg_trgm + tsvector).
-- =============================================================================

CREATE TABLE IF NOT EXISTS qr_codes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type entity_type NOT NULL,
  entity_id   uuid NOT NULL,
  code        text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(9), 'hex'),  -- short scan slug
  target_url  text,
  created_by  uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entity_type, entity_id)
);
COMMENT ON TABLE qr_codes IS 'Resolvable short codes for QR scanning; open the related record in the portal.';
CREATE INDEX IF NOT EXISTS idx_qr_entity ON qr_codes (entity_type, entity_id);

-- ---- Full-text search index on the ECM master ------------------------------
-- search_tsv is maintained by trg_ecm_search (see 0018).
CREATE INDEX IF NOT EXISTS idx_ecm_search_tsv ON ecm_requests USING gin (search_tsv);

-- ---- Trigram indexes powering the global search (ECM/ECR/ECO/part/customer) --
CREATE INDEX IF NOT EXISTS idx_trgm_ecm_number  ON ecm_requests USING gin (ecm_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_ecm_title   ON ecm_requests USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_ecm_part    ON ecm_requests USING gin (affected_part_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_ecr_number  ON ecr_records  USING gin (ecr_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_eco_number  ON eco_records  USING gin (eco_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_item_number ON items        USING gin (item_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_item_name   ON items        USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_customer    ON customers    USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_trgm_supplier    ON suppliers    USING gin (name gin_trgm_ops);

-- >>> supabase/migrations/0017_functions.sql
-- =============================================================================
-- 0017_functions.sql
-- Module 1 / Module 6: Business logic — numbering, RBAC helpers (used by RLS),
-- audit trigger fn, search vector, task instantiation, and the workflow engine.
-- All SECURITY DEFINER helpers pin search_path per Supabase hardening guidance.
-- =============================================================================

-- ---- Atomic number sequences (per entity, per year) ------------------------
CREATE TABLE IF NOT EXISTS number_sequences (
  scope         text PRIMARY KEY,          -- e.g. 'ECM:2026'
  current_value bigint NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION fn_next_number(p_prefix text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  yr  text := to_char(now(), 'YYYY');
  key text := upper(p_prefix) || ':' || yr;
  n   bigint;
BEGIN
  INSERT INTO number_sequences (scope, current_value)
  VALUES (key, 1)
  ON CONFLICT (scope) DO UPDATE SET current_value = number_sequences.current_value + 1
  RETURNING current_value INTO n;
  RETURN upper(p_prefix) || '-' || yr || '-' || lpad(n::text, 5, '0');
END $$;
COMMENT ON FUNCTION fn_next_number(text) IS 'Returns next document number, e.g. ECM-2026-00001 (atomic, per year).';

-- ---- RBAC helpers (SECURITY DEFINER so RLS can call regardless of caller) ---
CREATE OR REPLACE FUNCTION fn_has_role(p_role citext, p_user uuid DEFAULT app_current_user_id())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles ur
    JOIN roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user
      AND r.code = p_role
      AND (ur.expires_at IS NULL OR ur.expires_at > now())
  );
$$;

CREATE OR REPLACE FUNCTION fn_is_admin(p_user uuid DEFAULT app_current_user_id())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT fn_has_role('SUPER_ADMIN', p_user) OR fn_has_role('ECM_ADMIN', p_user);
$$;

CREATE OR REPLACE FUNCTION fn_has_permission(p_perm citext, p_user uuid DEFAULT app_current_user_id())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT
    fn_has_role('SUPER_ADMIN', p_user)               -- super admin bypass
    OR EXISTS (
      SELECT 1
      FROM user_roles ur
      JOIN role_permissions rp ON rp.role_id = ur.role_id
      JOIN permissions p       ON p.id = rp.permission_id
      WHERE ur.user_id = p_user
        AND p.code = p_perm
        AND (ur.expires_at IS NULL OR ur.expires_at > now())
    );
$$;
COMMENT ON FUNCTION fn_has_permission(citext, uuid) IS 'True if the user holds a role granting the permission (Super Admin bypass).';

-- Plants a user is scoped to. Empty set == unscoped (global) access.
CREATE OR REPLACE FUNCTION fn_user_plants(p_user uuid DEFAULT app_current_user_id())
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT DISTINCT ur.plant_id FROM user_roles ur
  WHERE ur.user_id = p_user AND ur.plant_id IS NOT NULL
    AND (ur.expires_at IS NULL OR ur.expires_at > now());
$$;

-- True if the user may see rows belonging to p_plant (global roles see all).
CREATE OR REPLACE FUNCTION fn_can_access_plant(p_plant uuid, p_user uuid DEFAULT app_current_user_id())
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT fn_is_admin(p_user)
      OR NOT EXISTS (SELECT 1 FROM fn_user_plants(p_user))          -- no plant scoping => global
      OR p_plant IS NULL
      OR p_plant IN (SELECT fn_user_plants(p_user));
$$;

-- ---- Search vector maintenance ---------------------------------------------
CREATE OR REPLACE FUNCTION fn_ecm_search_tsv()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.search_tsv :=
      setweight(to_tsvector('simple', unaccent(coalesce(NEW.ecm_number, ''))), 'A')
    || setweight(to_tsvector('simple', unaccent(coalesce(NEW.title, ''))), 'A')
    || setweight(to_tsvector('simple', unaccent(coalesce(NEW.affected_part_number, ''))), 'B')
    || setweight(to_tsvector('simple', unaccent(coalesce(NEW.description, ''))), 'C')
    || setweight(to_tsvector('simple', unaccent(coalesce(NEW.reason, ''))), 'D');
  RETURN NEW;
END $$;

-- ---- Generic field-level audit ---------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_key text;
  v_rid uuid;
  v_etype entity_type;
  v_actor uuid := app_current_user_id();
  v_ip inet;
BEGIN
  BEGIN v_ip := nullif(app_context('ip_address'), '')::inet; EXCEPTION WHEN others THEN v_ip := NULL; END;
  v_etype := CASE TG_TABLE_NAME
               WHEN 'ecm_requests' THEN 'ecm'::entity_type
               WHEN 'ecr_records'  THEN 'ecr'::entity_type
               WHEN 'eco_records'  THEN 'eco'::entity_type
               WHEN 'ecm_tasks'    THEN 'task'::entity_type
               WHEN 'documents'    THEN 'document'::entity_type
               WHEN 'approval_requests' THEN 'approval'::entity_type
               ELSE NULL END;

  IF TG_OP = 'INSERT' THEN
    v_new := to_jsonb(NEW);
    BEGIN v_rid := (v_new->>'id')::uuid; EXCEPTION WHEN others THEN v_rid := NULL; END;
    INSERT INTO audit_logs(table_name, record_id, entity_type, action, row_snapshot, changed_by,
                           ip_address, user_agent, browser, device, session_id, request_id)
    VALUES (TG_TABLE_NAME, v_rid, v_etype, 'INSERT', v_new, v_actor,
            v_ip, app_context('user_agent'), app_context('browser'), app_context('device'),
            app_context('session_id'), app_context('request_id'));
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    v_old := to_jsonb(OLD);
    BEGIN v_rid := (v_old->>'id')::uuid; EXCEPTION WHEN others THEN v_rid := NULL; END;
    INSERT INTO audit_logs(table_name, record_id, entity_type, action, row_snapshot, changed_by,
                           ip_address, user_agent, browser, device, session_id, request_id)
    VALUES (TG_TABLE_NAME, v_rid, v_etype, 'DELETE', v_old, v_actor,
            v_ip, app_context('user_agent'), app_context('browser'), app_context('device'),
            app_context('session_id'), app_context('request_id'));
    RETURN OLD;

  ELSE  -- UPDATE : one row per changed field
    v_old := to_jsonb(OLD);
    v_new := to_jsonb(NEW);
    BEGIN v_rid := (v_new->>'id')::uuid; EXCEPTION WHEN others THEN v_rid := NULL; END;
    FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
      IF v_key NOT IN ('updated_at','search_tsv','state_entered_at')
         AND (v_old -> v_key) IS DISTINCT FROM (v_new -> v_key) THEN
        INSERT INTO audit_logs(table_name, record_id, entity_type, action, field_name,
                               old_value, new_value, changed_by,
                               ip_address, user_agent, browser, device, session_id, request_id)
        VALUES (TG_TABLE_NAME, v_rid, v_etype, 'UPDATE', v_key,
                v_old->>v_key, v_new->>v_key, v_actor,
                v_ip, app_context('user_agent'), app_context('browser'), app_context('device'),
                app_context('session_id'), app_context('request_id'));
      END IF;
    END LOOP;
    RETURN NEW;
  END IF;
END $$;
COMMENT ON FUNCTION fn_audit() IS 'Generic trigger: writes field-level audit rows with request context.';

-- ---- Workflow bootstrap helpers --------------------------------------------
CREATE OR REPLACE FUNCTION fn_default_workflow_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT id FROM wf_workflows WHERE is_active ORDER BY version DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_initial_state(p_workflow uuid, p_stage_code citext)
RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT s.id
  FROM wf_states s JOIN wf_stages g ON g.id = s.stage_id
  WHERE s.workflow_id = p_workflow AND g.code = p_stage_code AND s.is_initial
  ORDER BY s.sequence LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_state_category(p_state uuid)
RETURNS citext LANGUAGE sql STABLE AS $$
  SELECT category FROM wf_states WHERE id = p_state;
$$;

-- ---- Number + workflow initialization (BEFORE INSERT) ----------------------
CREATE OR REPLACE FUNCTION fn_ecm_before_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_state uuid;
BEGIN
  IF NEW.ecm_number IS NULL THEN NEW.ecm_number := fn_next_number('ECM'); END IF;
  IF NEW.workflow_id IS NULL THEN NEW.workflow_id := fn_default_workflow_id(); END IF;
  IF NEW.current_state_id IS NULL AND NEW.workflow_id IS NOT NULL THEN
    v_state := fn_initial_state(NEW.workflow_id, 'PRE');
    NEW.current_state_id := v_state;
  END IF;
  IF NEW.current_state_id IS NOT NULL THEN
    SELECT stage_id, category INTO NEW.current_stage_id, NEW.status_category
    FROM wf_states WHERE id = NEW.current_state_id;
  END IF;
  NEW.requestor_id := COALESCE(NEW.requestor_id, app_current_user_id());
  NEW.created_by   := COALESCE(NEW.created_by, app_current_user_id());
  NEW.owner_id     := COALESCE(NEW.owner_id, NEW.requestor_id);
  NEW.state_entered_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION fn_ecr_before_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_wf uuid;
BEGIN
  IF NEW.ecr_number IS NULL THEN NEW.ecr_number := fn_next_number('ECR'); END IF;
  SELECT workflow_id INTO v_wf FROM ecm_requests WHERE id = NEW.ecm_request_id;
  IF NEW.current_state_id IS NULL THEN
    NEW.current_state_id := fn_initial_state(COALESCE(v_wf, fn_default_workflow_id()), 'ECR');
  END IF;
  NEW.status_category := fn_state_category(NEW.current_state_id);
  NEW.created_by := COALESCE(NEW.created_by, app_current_user_id());
  NEW.state_entered_at := now();
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION fn_eco_before_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_wf uuid;
BEGIN
  IF NEW.eco_number IS NULL THEN NEW.eco_number := fn_next_number('ECO'); END IF;
  SELECT workflow_id INTO v_wf FROM ecm_requests WHERE id = NEW.ecm_request_id;
  IF NEW.current_state_id IS NULL THEN
    NEW.current_state_id := fn_initial_state(COALESCE(v_wf, fn_default_workflow_id()), 'ECO');
  END IF;
  NEW.status_category := fn_state_category(NEW.current_state_id);
  NEW.created_by := COALESCE(NEW.created_by, app_current_user_id());
  NEW.state_entered_at := now();
  RETURN NEW;
END $$;

-- ---- Keep status_category / stage / entered_at in sync on state change -----
CREATE OR REPLACE FUNCTION fn_sync_state_meta_ecm()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.current_state_id IS DISTINCT FROM OLD.current_state_id THEN
    SELECT stage_id, category INTO NEW.current_stage_id, NEW.status_category
    FROM wf_states WHERE id = NEW.current_state_id;
    NEW.state_entered_at := now();
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION fn_sync_state_meta_child()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.current_state_id IS DISTINCT FROM OLD.current_state_id THEN
    NEW.status_category := fn_state_category(NEW.current_state_id);
    NEW.state_entered_at := now();
  END IF;
  RETURN NEW;
END $$;

-- ---- Append-only state history (AFTER UPDATE), enriched via GUCs ------------
CREATE OR REPLACE FUNCTION fn_log_state_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_etype entity_type;
  v_ecm uuid;
  v_wf uuid;
  v_tid uuid;
  v_new jsonb;
BEGIN
  IF NEW.current_state_id IS DISTINCT FROM OLD.current_state_id THEN
    v_new := to_jsonb(NEW);
    v_etype := CASE TG_TABLE_NAME WHEN 'ecm_requests' THEN 'ecm'
                                  WHEN 'ecr_records' THEN 'ecr'
                                  WHEN 'eco_records' THEN 'eco' END::entity_type;
    -- NEW.ecm_request_id does not exist on ecm_requests; resolve via jsonb to stay row-type agnostic
    v_ecm := CASE WHEN TG_TABLE_NAME = 'ecm_requests' THEN NEW.id ELSE (v_new->>'ecm_request_id')::uuid END;
    SELECT workflow_id INTO v_wf FROM wf_states WHERE id = NEW.current_state_id;
    BEGIN v_tid := nullif(app_context('wf_transition_id'), '')::uuid; EXCEPTION WHEN others THEN v_tid := NULL; END;
    INSERT INTO ecm_state_history(entity_type, entity_id, ecm_request_id, workflow_id,
      from_state_id, to_state_id, transition_id, action_code, performed_by, comment, dwell_seconds)
    VALUES (v_etype, NEW.id, v_ecm, v_wf,
      OLD.current_state_id, NEW.current_state_id, v_tid, app_context('wf_action_code'),
      app_current_user_id(), app_context('wf_comment'),
      GREATEST(0, EXTRACT(EPOCH FROM (now() - OLD.state_entered_at))::bigint));
  END IF;
  RETURN NEW;
END $$;

-- ---- Auto-generate QR codes for ECM/ECR/ECO --------------------------------
CREATE OR REPLACE FUNCTION fn_create_qr()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_etype entity_type;
BEGIN
  v_etype := CASE TG_TABLE_NAME WHEN 'ecm_requests' THEN 'ecm'
                                WHEN 'ecr_records' THEN 'ecr'
                                WHEN 'eco_records' THEN 'eco' END::entity_type;
  INSERT INTO qr_codes(entity_type, entity_id, target_url, created_by)
  VALUES (v_etype, NEW.id, '/' || v_etype::text || '/' || NEW.id::text, app_current_user_id())
  ON CONFLICT (entity_type, entity_id) DO NOTHING;
  RETURN NEW;
END $$;

-- ---- Instantiate the checklist for a state from its templates --------------
CREATE OR REPLACE FUNCTION fn_instantiate_state_tasks(
  p_entity_type entity_type, p_entity_id uuid, p_state_id uuid, p_ecm_request_id uuid)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_count int;
BEGIN
  INSERT INTO ecm_tasks (ecm_request_id, entity_type, entity_id, template_id, stage_id, state_id,
                         seq_number, title, description, task_type, is_mandatory, assignee_role_id, created_by)
  SELECT p_ecm_request_id, p_entity_type, p_entity_id, t.id, t.stage_id, t.state_id,
         t.seq_number, t.title, t.description, t.task_type, t.is_mandatory, t.default_assignee_role_id,
         app_current_user_id()
  FROM wf_task_templates t
  WHERE t.state_id = p_state_id
    AND NOT EXISTS (
      SELECT 1 FROM ecm_tasks e
      WHERE e.template_id = t.id AND e.entity_type = p_entity_type AND e.entity_id = p_entity_id
    );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $$;
COMMENT ON FUNCTION fn_instantiate_state_tasks(entity_type, uuid, uuid, uuid) IS 'Creates task-list items for a state from wf_task_templates (idempotent).';

-- ---- Workflow engine: validate + fire a transition -------------------------
CREATE OR REPLACE FUNCTION fn_execute_transition(
  p_entity_type entity_type, p_entity_id uuid, p_transition_id uuid, p_comment text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  t          wf_transitions%ROWTYPE;
  v_current  uuid;
  v_ecm      uuid;
  v_stage    uuid;
BEGIN
  SELECT * INTO t FROM wf_transitions WHERE id = p_transition_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transition % not found or inactive', p_transition_id; END IF;

  -- current state of the target entity
  IF    p_entity_type = 'ecm' THEN SELECT current_state_id, id            INTO v_current, v_ecm FROM ecm_requests WHERE id = p_entity_id;
  ELSIF p_entity_type = 'ecr' THEN SELECT current_state_id, ecm_request_id INTO v_current, v_ecm FROM ecr_records  WHERE id = p_entity_id;
  ELSIF p_entity_type = 'eco' THEN SELECT current_state_id, ecm_request_id INTO v_current, v_ecm FROM eco_records  WHERE id = p_entity_id;
  ELSE  RAISE EXCEPTION 'Unsupported entity_type % for transition', p_entity_type;
  END IF;
  IF v_ecm IS NULL THEN RAISE EXCEPTION 'Entity %/% not found', p_entity_type, p_entity_id; END IF;

  -- guards
  IF t.from_state_id IS NOT NULL AND t.from_state_id IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'Invalid transition: entity is not in the expected source state';
  END IF;
  IF t.required_permission IS NOT NULL AND NOT fn_has_permission(t.required_permission) THEN
    RAISE EXCEPTION 'Insufficient privilege for action % (requires %)', t.action_code, t.required_permission
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF t.requires_comment AND coalesce(btrim(p_comment), '') = '' THEN
    RAISE EXCEPTION 'A comment is required for action %', t.action_code;
  END IF;

  -- expose context so the history trigger records who/why
  PERFORM set_config('app.wf_transition_id', t.id::text, true);
  PERFORM set_config('app.wf_action_code',  t.action_code::text, true);
  PERFORM set_config('app.wf_comment',      coalesce(p_comment, ''), true);

  SELECT stage_id INTO v_stage FROM wf_states WHERE id = t.to_state_id;

  IF    p_entity_type = 'ecm' THEN
    UPDATE ecm_requests SET current_state_id = t.to_state_id WHERE id = p_entity_id;
  ELSIF p_entity_type = 'ecr' THEN
    UPDATE ecr_records  SET current_state_id = t.to_state_id WHERE id = p_entity_id;
  ELSIF p_entity_type = 'eco' THEN
    UPDATE eco_records  SET current_state_id = t.to_state_id WHERE id = p_entity_id;
  END IF;

  -- side effects
  IF t.side_effect = 'create_ecr' THEN
    INSERT INTO ecr_records (ecm_request_id, title, current_state_id, owner_id, created_by)
    SELECT id, title, t.to_state_id, owner_id, app_current_user_id() FROM ecm_requests WHERE id = v_ecm
    ON CONFLICT DO NOTHING;
  ELSIF t.side_effect = 'create_eco' THEN
    INSERT INTO eco_records (ecm_request_id, ecr_record_id, title, current_state_id, owner_id, created_by)
    SELECT e.id, (SELECT id FROM ecr_records WHERE ecm_request_id = e.id ORDER BY created_at DESC LIMIT 1),
           e.title, t.to_state_id, e.owner_id, app_current_user_id()
    FROM ecm_requests e WHERE e.id = v_ecm
    ON CONFLICT DO NOTHING;
  ELSIF t.side_effect = 'close_ecm' THEN
    UPDATE ecm_requests SET closed_at = now() WHERE id = v_ecm;
  END IF;

  -- build the checklist for the new state
  PERFORM fn_instantiate_state_tasks(p_entity_type, p_entity_id, t.to_state_id, v_ecm);

  RETURN t.to_state_id;
END $$;
COMMENT ON FUNCTION fn_execute_transition(entity_type, uuid, uuid, text) IS 'Validates permissions/guards and fires a workflow transition, logging history and spawning tasks + child records.';

-- >>> supabase/migrations/0018_triggers.sql
-- =============================================================================
-- 0018_triggers.sql
-- Module 1: Wire the business-logic functions (0017) onto their tables.
-- =============================================================================

-- Seed the checklist for the initial state when a change record is created.
CREATE OR REPLACE FUNCTION fn_seed_initial_tasks()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_etype entity_type; v_ecm uuid; v_new jsonb := to_jsonb(NEW);
BEGIN
  v_etype := CASE TG_TABLE_NAME WHEN 'ecm_requests' THEN 'ecm'
                                WHEN 'ecr_records' THEN 'ecr'
                                WHEN 'eco_records' THEN 'eco' END::entity_type;
  -- resolve ecm_request_id via jsonb (absent on ecm_requests row type)
  v_ecm := CASE WHEN TG_TABLE_NAME = 'ecm_requests' THEN NEW.id ELSE (v_new->>'ecm_request_id')::uuid END;
  IF NEW.current_state_id IS NOT NULL THEN
    PERFORM fn_instantiate_state_tasks(v_etype, NEW.id, NEW.current_state_id, v_ecm);
  END IF;
  RETURN NEW;
END $$;

-- ---- ecm_requests -----------------------------------------------------------
CREATE TRIGGER trg_ecm_before_ins BEFORE INSERT ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_ecm_before_insert();
CREATE TRIGGER trg_ecm_search     BEFORE INSERT OR UPDATE ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_ecm_search_tsv();
CREATE TRIGGER trg_ecm_state_meta BEFORE UPDATE ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_sync_state_meta_ecm();
CREATE TRIGGER trg_ecm_after_ins  AFTER INSERT ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_seed_initial_tasks();
CREATE TRIGGER trg_ecm_qr         AFTER INSERT ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_create_qr();
CREATE TRIGGER trg_ecm_state_log  AFTER UPDATE ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_log_state_change();
CREATE TRIGGER trg_ecm_audit      AFTER INSERT OR UPDATE OR DELETE ON ecm_requests
  FOR EACH ROW EXECUTE FUNCTION fn_audit();

-- ---- ecr_records ------------------------------------------------------------
CREATE TRIGGER trg_ecr_before_ins BEFORE INSERT ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_ecr_before_insert();
CREATE TRIGGER trg_ecr_state_meta BEFORE UPDATE ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_sync_state_meta_child();
CREATE TRIGGER trg_ecr_after_ins  AFTER INSERT ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_seed_initial_tasks();
CREATE TRIGGER trg_ecr_qr         AFTER INSERT ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_create_qr();
CREATE TRIGGER trg_ecr_state_log  AFTER UPDATE ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_log_state_change();
CREATE TRIGGER trg_ecr_audit      AFTER INSERT OR UPDATE OR DELETE ON ecr_records
  FOR EACH ROW EXECUTE FUNCTION fn_audit();

-- ---- eco_records ------------------------------------------------------------
CREATE TRIGGER trg_eco_before_ins BEFORE INSERT ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_eco_before_insert();
CREATE TRIGGER trg_eco_state_meta BEFORE UPDATE ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_sync_state_meta_child();
CREATE TRIGGER trg_eco_after_ins  AFTER INSERT ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_seed_initial_tasks();
CREATE TRIGGER trg_eco_qr         AFTER INSERT ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_create_qr();
CREATE TRIGGER trg_eco_state_log  AFTER UPDATE ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_log_state_change();
CREATE TRIGGER trg_eco_audit      AFTER INSERT OR UPDATE OR DELETE ON eco_records
  FOR EACH ROW EXECUTE FUNCTION fn_audit();

-- ---- Field-level audit on other key tables ---------------------------------
CREATE TRIGGER trg_tasks_audit     AFTER INSERT OR UPDATE OR DELETE ON ecm_tasks
  FOR EACH ROW EXECUTE FUNCTION fn_audit();
CREATE TRIGGER trg_documents_audit AFTER INSERT OR UPDATE OR DELETE ON documents
  FOR EACH ROW EXECUTE FUNCTION fn_audit();
CREATE TRIGGER trg_approvals_audit AFTER INSERT OR UPDATE OR DELETE ON approval_requests
  FOR EACH ROW EXECUTE FUNCTION fn_audit();

-- >>> supabase/migrations/0019_views_analytics.sql
-- =============================================================================
-- 0019_views_analytics.sql
-- Module 1 / Module 5 & 16: Analytics views powering the dashboard & reports.
-- Views run with the querying user's privileges (security_invoker) so RLS applies.
-- =============================================================================

-- ---- Enriched ECM overview (labels resolved) -------------------------------
CREATE OR REPLACE VIEW vw_ecm_overview
WITH (security_invoker = true) AS
SELECT
  e.id, e.ecm_number, e.title, e.change_type, e.priority, e.risk_level,
  e.cost_impact, e.cost_currency, e.created_date, e.due_date, e.closed_at, e.is_deleted,
  st.code  AS state_code,  st.name  AS state_name,  st.category AS status_category,
  sg.code  AS stage_code,  sg.name  AS stage_name,
  cat.name AS status_label, cat.color AS status_color,
  d.name   AS department, pl.name AS plant, c.name AS customer, sup.name AS supplier,
  ow.full_name AS owner_name, rq.full_name AS requestor_name,
  e.state_entered_at,
  (e.due_date IS NOT NULL AND e.due_date < CURRENT_DATE
     AND st.category NOT IN ('resolved','completed','rejected','cancelled')) AS is_overdue,
  EXTRACT(EPOCH FROM (COALESCE(e.closed_at, now()) - e.created_at))/86400.0 AS age_days
FROM ecm_requests e
LEFT JOIN wf_states st           ON st.id = e.current_state_id
LEFT JOIN wf_stages sg           ON sg.id = e.current_stage_id
LEFT JOIN wf_state_categories cat ON cat.code = e.status_category
LEFT JOIN departments d          ON d.id = e.department_id
LEFT JOIN plants pl              ON pl.id = e.plant_id
LEFT JOIN customers c            ON c.id = e.customer_id
LEFT JOIN suppliers sup          ON sup.id = e.supplier_id
LEFT JOIN profiles ow            ON ow.id = e.owner_id
LEFT JOIN profiles rq            ON rq.id = e.requestor_id;

-- ---- Executive KPI card values (single row) --------------------------------
CREATE OR REPLACE VIEW vw_dashboard_kpis
WITH (security_invoker = true) AS
SELECT
  count(*) FILTER (WHERE NOT is_deleted)                                                          AS total_ecm,
  count(*) FILTER (WHERE NOT is_deleted AND status_category NOT IN ('resolved','completed','rejected','cancelled')) AS open_ecm,
  count(*) FILTER (WHERE NOT is_deleted AND status_category IN ('approval','screening'))          AS pending_approval,
  count(*) FILTER (WHERE NOT is_deleted AND status_category = 'rejected')                         AS rejected,
  count(*) FILTER (WHERE NOT is_deleted AND status_category = 'cancelled')                        AS cancelled,
  count(*) FILTER (WHERE NOT is_deleted AND status_category IN ('resolved','completed'))          AS completed,
  round(avg(EXTRACT(EPOCH FROM (closed_at - created_at))/86400.0)
        FILTER (WHERE closed_at IS NOT NULL), 1)                                                  AS avg_lead_time_days,
  (SELECT round(avg(EXTRACT(EPOCH FROM (decided_at - created_at))/3600.0), 1)
     FROM approval_requests WHERE status IN ('approved','rejected') AND decided_at IS NOT NULL)   AS avg_approval_hours,
  round(100.0 * count(*) FILTER (WHERE status_category IN ('resolved','completed'))
        / NULLIF(count(*) FILTER (WHERE status_category IN ('resolved','completed','rejected','cancelled')), 0), 1) AS implementation_success_rate,
  (SELECT count(*) FROM ecm_tasks WHERE status <> 'done' AND due_date IS NOT NULL AND due_date < CURRENT_DATE) AS overdue_tasks,
  (SELECT count(*) FROM ecm_tasks WHERE status IN ('todo','in_progress','blocked'))               AS open_actions
FROM ecm_requests;

-- ---- Monthly trends (created vs completed) ---------------------------------
CREATE OR REPLACE VIEW vw_monthly_trends
WITH (security_invoker = true) AS
WITH months AS (
  SELECT date_trunc('month', created_at) AS m, count(*) AS created
  FROM ecm_requests WHERE NOT is_deleted GROUP BY 1),
completed AS (
  SELECT date_trunc('month', closed_at) AS m, count(*) AS completed
  FROM ecm_requests WHERE closed_at IS NOT NULL GROUP BY 1)
SELECT COALESCE(mo.m, co.m) AS month,
       COALESCE(mo.created, 0)   AS created,
       COALESCE(co.completed, 0) AS completed
FROM months mo FULL OUTER JOIN completed co ON mo.m = co.m
ORDER BY 1;

-- ---- Requests per department -----------------------------------------------
CREATE OR REPLACE VIEW vw_department_requests
WITH (security_invoker = true) AS
SELECT COALESCE(d.name, 'Unassigned') AS department,
       count(*) FILTER (WHERE NOT e.is_deleted) AS total,
       count(*) FILTER (WHERE e.status_category NOT IN ('resolved','completed','rejected','cancelled') AND NOT e.is_deleted) AS open
FROM ecm_requests e LEFT JOIN departments d ON d.id = e.department_id
GROUP BY 1 ORDER BY 2 DESC;

-- ---- Priority distribution --------------------------------------------------
CREATE OR REPLACE VIEW vw_priority_distribution
WITH (security_invoker = true) AS
SELECT priority, count(*) AS total
FROM ecm_requests WHERE NOT is_deleted GROUP BY priority;

-- ---- Workflow funnel (count by stage, in flow order) -----------------------
CREATE OR REPLACE VIEW vw_workflow_funnel
WITH (security_invoker = true) AS
SELECT sg.code AS stage_code, sg.name AS stage_name, sg.sequence,
       count(e.id) FILTER (WHERE NOT e.is_deleted) AS in_stage
FROM wf_stages sg
LEFT JOIN ecm_requests e ON e.current_stage_id = sg.id
GROUP BY sg.code, sg.name, sg.sequence
ORDER BY sg.sequence;

-- ---- Approval duration by stage --------------------------------------------
CREATE OR REPLACE VIEW vw_approval_duration
WITH (security_invoker = true) AS
SELECT COALESCE(sg.name, 'Unknown') AS stage_name,
       count(*)                                                              AS decisions,
       round(avg(EXTRACT(EPOCH FROM (ar.decided_at - ar.created_at))/3600.0), 1) AS avg_hours
FROM approval_requests ar
LEFT JOIN wf_stages sg ON sg.id = ar.stage_id
WHERE ar.decided_at IS NOT NULL
GROUP BY 1 ORDER BY 3 DESC NULLS LAST;

-- ---- Bottleneck analysis (avg dwell per state vs SLA) ----------------------
CREATE OR REPLACE VIEW vw_bottleneck_analysis
WITH (security_invoker = true) AS
SELECT s.code AS state_code, s.name AS state_name, sg.name AS stage_name, s.sla_hours,
       count(h.id)                                       AS transitions_out,
       round(avg(h.dwell_seconds)/3600.0, 1)             AS avg_dwell_hours,
       round(max(h.dwell_seconds)/3600.0, 1)             AS max_dwell_hours,
       (s.sla_hours IS NOT NULL AND avg(h.dwell_seconds)/3600.0 > s.sla_hours) AS breaches_sla
FROM ecm_state_history h
JOIN wf_states s  ON s.id = h.from_state_id
JOIN wf_stages sg ON sg.id = s.stage_id
GROUP BY s.code, s.name, sg.name, s.sla_hours
ORDER BY avg_dwell_hours DESC NULLS LAST;

-- ---- Workload per user (open tasks) ----------------------------------------
CREATE OR REPLACE VIEW vw_workload_per_user
WITH (security_invoker = true) AS
SELECT p.id AS user_id, p.full_name,
       count(*) FILTER (WHERE t.status IN ('todo','in_progress','blocked')) AS open_tasks,
       count(*) FILTER (WHERE t.status <> 'done' AND t.due_date < CURRENT_DATE) AS overdue_tasks,
       count(*) FILTER (WHERE t.status = 'done')                            AS done_tasks
FROM profiles p LEFT JOIN ecm_tasks t ON t.assignee_id = p.id
GROUP BY p.id, p.full_name
HAVING count(t.id) > 0
ORDER BY open_tasks DESC;

-- ---- Engineer performance (throughput + speed) -----------------------------
CREATE OR REPLACE VIEW vw_engineer_performance
WITH (security_invoker = true) AS
SELECT p.id AS user_id, p.full_name,
       count(*) FILTER (WHERE t.status = 'done')                            AS completed_tasks,
       round(avg(EXTRACT(EPOCH FROM (t.completed_at - t.started_at))/3600.0)
             FILTER (WHERE t.completed_at IS NOT NULL AND t.started_at IS NOT NULL), 1) AS avg_completion_hours,
       count(*) FILTER (WHERE t.status <> 'done' AND t.due_date < CURRENT_DATE) AS overdue_tasks
FROM profiles p JOIN ecm_tasks t ON t.assignee_id = p.id
GROUP BY p.id, p.full_name ORDER BY completed_tasks DESC;

-- ---- CR-board performance (throughput + speed of board decisions) ----------
CREATE OR REPLACE VIEW vw_crboard_performance
WITH (security_invoker = true) AS
SELECT date_trunc('month', aa.decision_at) AS month,
       count(*)                            AS decisions,
       count(*) FILTER (WHERE aa.decision = 'approved') AS approved,
       count(*) FILTER (WHERE aa.decision = 'rejected') AS rejected,
       round(avg(EXTRACT(EPOCH FROM (aa.decision_at - ar.created_at))/3600.0), 1) AS avg_decision_hours
FROM approval_assignments aa
JOIN approval_requests ar ON ar.id = aa.approval_request_id
WHERE aa.decision_at IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- ---- Cycle time per completed ECM ------------------------------------------
CREATE OR REPLACE VIEW vw_cycle_time
WITH (security_invoker = true) AS
SELECT e.ecm_number, e.title,
       e.created_at, e.closed_at,
       round(EXTRACT(EPOCH FROM (e.closed_at - e.created_at))/86400.0, 1) AS cycle_days
FROM ecm_requests e
WHERE e.closed_at IS NOT NULL
ORDER BY e.closed_at DESC;

-- >>> supabase/migrations/0020_rls_policies.sql
-- =============================================================================
-- 0020_rls_policies.sql
-- Module 1: Row-Level Security. RLS is enabled on EVERY table.
-- Access is driven by fn_has_permission()/fn_is_admin()/fn_can_access_plant().
-- The service_role and table owner (SECURITY DEFINER triggers) bypass RLS.
-- =============================================================================

-- ---- Base privileges (PostgREST needs table grants in addition to RLS) -----
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT                 ON ALL SEQUENCES  IN SCHEMA public TO authenticated;
GRANT EXECUTE                       ON ALL FUNCTIONS  IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- ---- Reference / config tables: read = all authenticated, write = admin ----
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'roles','permissions','role_permissions','plants','departments','customers','suppliers',
    'wf_workflows','wf_state_categories','wf_stages','wf_states','wf_transitions','wf_task_templates',
    'items','boms','bom_lines','document_categories','email_templates','notification_rules',
    'report_definitions','powerbi_reports','qr_codes','ecm_task_dependencies','task_checklist_items',
    'task_reminders'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_read', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (true)', t||'_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_admin_write', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR ALL TO authenticated USING (fn_is_admin() OR fn_has_permission(''admin.manage'')) WITH CHECK (fn_is_admin() OR fn_has_permission(''admin.manage''))',
      t||'_admin_write', t);
  END LOOP;
END $$;

-- ---- profiles ---------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_read        ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY profiles_update_self ON profiles FOR UPDATE TO authenticated
  USING (id = app_current_user_id() OR fn_is_admin())
  WITH CHECK (id = app_current_user_id() OR fn_is_admin());
CREATE POLICY profiles_admin_write ON profiles FOR ALL TO authenticated
  USING (fn_is_admin()) WITH CHECK (fn_is_admin());

-- ---- user_roles -------------------------------------------------------------
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_roles_read  ON user_roles FOR SELECT TO authenticated
  USING (user_id = app_current_user_id() OR fn_is_admin());
CREATE POLICY user_roles_admin ON user_roles FOR ALL TO authenticated
  USING (fn_is_admin()) WITH CHECK (fn_is_admin());

-- ---- ecm_requests (plant-scoped) -------------------------------------------
ALTER TABLE ecm_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY ecm_read   ON ecm_requests FOR SELECT TO authenticated
  USING ((NOT is_deleted AND fn_has_permission('ecm.read') AND fn_can_access_plant(plant_id)) OR fn_is_admin());
CREATE POLICY ecm_insert ON ecm_requests FOR INSERT TO authenticated
  WITH CHECK (fn_has_permission('ecm.create'));
CREATE POLICY ecm_update ON ecm_requests FOR UPDATE TO authenticated
  USING ((fn_has_permission('ecm.update') AND fn_can_access_plant(plant_id)) OR fn_is_admin())
  WITH CHECK ((fn_has_permission('ecm.update') AND fn_can_access_plant(plant_id)) OR fn_is_admin());
CREATE POLICY ecm_delete ON ecm_requests FOR DELETE TO authenticated USING (fn_is_admin());

-- ---- ecr_records / eco_records ---------------------------------------------
ALTER TABLE ecr_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY ecr_read   ON ecr_records FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY ecr_insert ON ecr_records FOR INSERT TO authenticated WITH CHECK (fn_has_permission('ecr.create') OR fn_is_admin());
CREATE POLICY ecr_update ON ecr_records FOR UPDATE TO authenticated USING (fn_has_permission('ecm.update') OR fn_is_admin()) WITH CHECK (fn_has_permission('ecm.update') OR fn_is_admin());
CREATE POLICY ecr_delete ON ecr_records FOR DELETE TO authenticated USING (fn_is_admin());

ALTER TABLE eco_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY eco_read   ON eco_records FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY eco_insert ON eco_records FOR INSERT TO authenticated WITH CHECK (fn_has_permission('eco.create') OR fn_is_admin());
CREATE POLICY eco_update ON eco_records FOR UPDATE TO authenticated USING (fn_has_permission('ecm.update') OR fn_is_admin()) WITH CHECK (fn_has_permission('ecm.update') OR fn_is_admin());
CREATE POLICY eco_delete ON eco_records FOR DELETE TO authenticated USING (fn_is_admin());

-- ---- ecm_links / affected items --------------------------------------------
ALTER TABLE ecm_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY links_read  ON ecm_links FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY links_write ON ecm_links FOR ALL TO authenticated USING (fn_has_permission('ecm.update') OR fn_is_admin()) WITH CHECK (fn_has_permission('ecm.update') OR fn_is_admin());

ALTER TABLE ecm_affected_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY affected_read  ON ecm_affected_items FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY affected_write ON ecm_affected_items FOR ALL TO authenticated USING (fn_has_permission('ecm.update') OR fn_is_admin()) WITH CHECK (fn_has_permission('ecm.update') OR fn_is_admin());

-- ---- ecm_state_history (read-only to clients; written by definer triggers) -
ALTER TABLE ecm_state_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY history_read ON ecm_state_history FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());

-- ---- ecm_tasks --------------------------------------------------------------
ALTER TABLE ecm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY tasks_read   ON ecm_tasks FOR SELECT TO authenticated
  USING (fn_has_permission('ecm.read') OR assignee_id = app_current_user_id() OR fn_is_admin());
CREATE POLICY tasks_insert ON ecm_tasks FOR INSERT TO authenticated
  WITH CHECK (fn_has_permission('task.manage') OR fn_is_admin());
CREATE POLICY tasks_update ON ecm_tasks FOR UPDATE TO authenticated
  USING (fn_has_permission('task.manage') OR assignee_id = app_current_user_id() OR fn_is_admin())
  WITH CHECK (fn_has_permission('task.manage') OR assignee_id = app_current_user_id() OR fn_is_admin());
CREATE POLICY tasks_delete ON ecm_tasks FOR DELETE TO authenticated USING (fn_has_permission('task.manage') OR fn_is_admin());

-- ---- documents / versions / signatures -------------------------------------
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY docs_read  ON documents FOR SELECT TO authenticated USING (fn_has_permission('document.read') OR fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY docs_write ON documents FOR ALL TO authenticated USING (fn_has_permission('document.manage') OR fn_is_admin()) WITH CHECK (fn_has_permission('document.manage') OR fn_is_admin());

ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY docver_read  ON document_versions FOR SELECT TO authenticated USING (fn_has_permission('document.read') OR fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY docver_write ON document_versions FOR ALL TO authenticated USING (fn_has_permission('document.manage') OR fn_is_admin()) WITH CHECK (fn_has_permission('document.manage') OR fn_is_admin());

ALTER TABLE document_signatures ENABLE ROW LEVEL SECURITY;
CREATE POLICY docsig_read   ON document_signatures FOR SELECT TO authenticated USING (fn_has_permission('document.read') OR fn_is_admin());
CREATE POLICY docsig_insert ON document_signatures FOR INSERT TO authenticated WITH CHECK (signer_id = app_current_user_id());

-- ---- comments / attachments ------------------------------------------------
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY comments_read   ON comments FOR SELECT TO authenticated USING (NOT is_deleted AND (fn_has_permission('ecm.read') OR fn_is_admin()));
CREATE POLICY comments_insert ON comments FOR INSERT TO authenticated WITH CHECK (author_id = app_current_user_id());
CREATE POLICY comments_update ON comments FOR UPDATE TO authenticated USING (author_id = app_current_user_id() OR fn_is_admin()) WITH CHECK (author_id = app_current_user_id() OR fn_is_admin());
CREATE POLICY comments_delete ON comments FOR DELETE TO authenticated USING (author_id = app_current_user_id() OR fn_is_admin());

ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY attach_read   ON attachments FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY attach_insert ON attachments FOR INSERT TO authenticated WITH CHECK (uploaded_by = app_current_user_id());
CREATE POLICY attach_delete ON attachments FOR DELETE TO authenticated USING (uploaded_by = app_current_user_id() OR fn_is_admin());

-- ---- approvals --------------------------------------------------------------
ALTER TABLE approval_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY appr_read  ON approval_requests FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY appr_write ON approval_requests FOR ALL TO authenticated USING (fn_has_permission('approval.manage') OR fn_is_admin()) WITH CHECK (fn_has_permission('approval.manage') OR fn_is_admin());

ALTER TABLE approval_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY apprasg_read   ON approval_assignments FOR SELECT TO authenticated
  USING (approver_id = app_current_user_id() OR fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY apprasg_update ON approval_assignments FOR UPDATE TO authenticated
  USING (approver_id = app_current_user_id() OR fn_is_admin())
  WITH CHECK (approver_id = app_current_user_id() OR fn_is_admin());
CREATE POLICY apprasg_admin  ON approval_assignments FOR ALL TO authenticated
  USING (fn_has_permission('approval.manage') OR fn_is_admin())
  WITH CHECK (fn_has_permission('approval.manage') OR fn_is_admin());

ALTER TABLE approval_email_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY apprtok_admin ON approval_email_tokens FOR SELECT TO authenticated USING (fn_is_admin());

-- ---- audit_logs (immutable; read for auditors/admins only) ------------------
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_read ON audit_logs FOR SELECT TO authenticated USING (fn_has_permission('audit.read') OR fn_is_admin());

-- ---- integration (admins/integration readers; writes via service_role) -----
ALTER TABLE integration_endpoints ENABLE ROW LEVEL SECURITY;
CREATE POLICY intep_read  ON integration_endpoints FOR SELECT TO authenticated USING (fn_is_admin() OR fn_has_permission('integration.read'));
CREATE POLICY intep_write ON integration_endpoints FOR ALL TO authenticated USING (fn_is_admin()) WITH CHECK (fn_is_admin());

ALTER TABLE api_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY apilog_read ON api_logs FOR SELECT TO authenticated USING (fn_is_admin() OR fn_has_permission('integration.read'));

ALTER TABLE integration_sync_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY syncstate_read ON integration_sync_state FOR SELECT TO authenticated USING (fn_is_admin() OR fn_has_permission('integration.read'));

ALTER TABLE d365_sync_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY syncq_read ON d365_sync_queue FOR SELECT TO authenticated USING (fn_is_admin() OR fn_has_permission('integration.read'));

-- ---- AI history (own data) --------------------------------------------------
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY aiconv_all ON ai_conversations FOR ALL TO authenticated
  USING (user_id = app_current_user_id() OR fn_is_admin())
  WITH CHECK (user_id = app_current_user_id());

ALTER TABLE ai_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY aimsg_all ON ai_messages FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM ai_conversations c WHERE c.id = conversation_id AND (c.user_id = app_current_user_id() OR fn_is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM ai_conversations c WHERE c.id = conversation_id AND c.user_id = app_current_user_id()));

ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
CREATE POLICY aiins_read   ON ai_insights FOR SELECT TO authenticated USING (fn_has_permission('ecm.read') OR fn_is_admin());
CREATE POLICY aiins_insert ON ai_insights FOR INSERT TO authenticated WITH CHECK (created_by = app_current_user_id() OR fn_is_admin());

-- ---- notifications / preferences (own) -------------------------------------
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_read   ON notifications FOR SELECT TO authenticated USING (recipient_id = app_current_user_id());
CREATE POLICY notif_update ON notifications FOR UPDATE TO authenticated USING (recipient_id = app_current_user_id()) WITH CHECK (recipient_id = app_current_user_id());
CREATE POLICY notif_delete ON notifications FOR DELETE TO authenticated USING (recipient_id = app_current_user_id());

ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY notifpref_all ON notification_preferences FOR ALL TO authenticated
  USING (user_id = app_current_user_id()) WITH CHECK (user_id = app_current_user_id());

-- ---- dashboards / saved filters (own) --------------------------------------
ALTER TABLE dashboard_layouts ENABLE ROW LEVEL SECURITY;
CREATE POLICY dash_read  ON dashboard_layouts FOR SELECT TO authenticated USING (user_id = app_current_user_id() OR user_id IS NULL OR is_shared);
CREATE POLICY dash_write ON dashboard_layouts FOR ALL TO authenticated USING (user_id = app_current_user_id() OR fn_is_admin()) WITH CHECK (user_id = app_current_user_id() OR fn_is_admin());

ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;
CREATE POLICY savedfilt_all ON saved_filters FOR ALL TO authenticated USING (user_id = app_current_user_id()) WITH CHECK (user_id = app_current_user_id());

-- ---- number_sequences (no client access; used only by SECURITY DEFINER fns) -
ALTER TABLE number_sequences ENABLE ROW LEVEL SECURITY;

-- >>> supabase/migrations/0021_storage_buckets.sql
-- =============================================================================
-- 0021_storage_buckets.sql
-- Module 1 / Module 9: Supabase Storage buckets + object policies.
-- Guarded so it is a no-op on a plain PostgreSQL instance (no storage schema).
-- =============================================================================
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'storage schema not present — skipping bucket setup (non-Supabase environment).';
    RETURN;
  END IF;

  -- Buckets (private by default; avatars public for direct rendering).
  INSERT INTO storage.buckets (id, name, public, file_size_limit) VALUES
    ('ecm-documents',   'ecm-documents',   false, 262144000),   -- 250 MB (CAD/drawings)
    ('ecm-attachments', 'ecm-attachments', false, 52428800),    -- 50 MB
    ('ecm-exports',     'ecm-exports',     false, 104857600),   -- 100 MB (reports/packages)
    ('ecm-avatars',     'ecm-avatars',     true,  5242880)      -- 5 MB
  ON CONFLICT (id) DO NOTHING;

  -- Object policies: authenticated users operate within the ECM buckets.
  EXECUTE $p$
    CREATE POLICY "ecm_objects_read" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_insert" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_update" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars'))
    WITH CHECK (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_delete" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE 'storage object policies already exist — skipping.';
END $$;

-- >>> supabase/migrations/0022_auth_hooks.sql
-- =============================================================================
-- 0022_auth_hooks.sql
-- Module 2: Supabase Auth integration.
--   * Auto-provision a profile row when an auth user is created.
--   * Bootstrap: the very first user becomes SUPER_ADMIN; everyone else VIEWER.
--   * Admin helper to (re)assign a role by email.
-- Guarded so this file is a no-op on a plain PostgreSQL instance (no auth schema).
-- =============================================================================

-- ---- Assign a role to a user by email (admin/service use) ------------------
CREATE OR REPLACE FUNCTION fn_grant_role(p_email citext, p_role citext, p_plant uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  SELECT id INTO v_user FROM profiles WHERE email = p_email;
  IF v_user IS NULL THEN RAISE EXCEPTION 'No profile for email %', p_email; END IF;
  SELECT id INTO v_role FROM roles WHERE code = p_role;
  IF v_role IS NULL THEN RAISE EXCEPTION 'No role %', p_role; END IF;
  INSERT INTO user_roles (user_id, role_id, plant_id, assigned_by)
  VALUES (v_user, v_role, p_plant, app_current_user_id())
  ON CONFLICT (user_id, role_id, plant_id) DO NOTHING;
END $$;
COMMENT ON FUNCTION fn_grant_role(citext, citext, uuid) IS 'Assigns a role to a user by email; used by the bootstrap-admin Edge Function and Admin Panel.';

-- ---- New-user handler: create profile + assign default/bootstrap role ------
CREATE OR REPLACE FUNCTION fn_handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_first boolean;
  v_role_code citext;
  v_full_name text;
BEGIN
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name',
                          NEW.raw_user_meta_data->>'name',
                          split_part(NEW.email, '@', 1));

  INSERT INTO profiles (id, email, full_name, avatar_url, azure_ad_object_id)
  VALUES (
    NEW.id,
    NEW.email,
    v_full_name,
    NEW.raw_user_meta_data->>'avatar_url',
    COALESCE(NEW.raw_user_meta_data->>'provider_id', NEW.raw_user_meta_data->>'sub')
  )
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  -- Bootstrap: first ever user gets SUPER_ADMIN; subsequent users get VIEWER.
  SELECT NOT EXISTS (
    SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE r.code = 'SUPER_ADMIN'
  ) INTO v_is_first;
  v_role_code := CASE WHEN v_is_first THEN 'SUPER_ADMIN' ELSE 'VIEWER' END;

  INSERT INTO user_roles (user_id, role_id)
  SELECT NEW.id, r.id FROM roles r WHERE r.code = v_role_code
  ON CONFLICT (user_id, role_id, plant_id) DO NOTHING;

  RETURN NEW;
END $$;
COMMENT ON FUNCTION fn_handle_new_user() IS 'AFTER INSERT on auth.users: provisions profile and default role (first user = Super Admin).';

-- ---- Wire the trigger onto auth.users (Supabase only) ----------------------
DO $$
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users not present — skipping auth trigger (non-Supabase environment).';
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
  CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION fn_handle_new_user();
END $$;

-- Keep profiles.last_login_at fresh from a lightweight RPC the client calls post-login.
CREATE OR REPLACE FUNCTION fn_touch_last_login()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE profiles SET last_login_at = now() WHERE id = app_current_user_id();
$$;

-- Convenience RPC: the signed-in user's profile + roles + permissions (for the app bootstrap).
CREATE OR REPLACE FUNCTION fn_me()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'profile', to_jsonb(p),
    'roles',       COALESCE((SELECT jsonb_agg(r.code) FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id = p.id), '[]'::jsonb),
    'permissions', COALESCE((SELECT jsonb_agg(DISTINCT pm.code)
                             FROM user_roles ur
                             JOIN role_permissions rp ON rp.role_id = ur.role_id
                             JOIN permissions pm ON pm.id = rp.permission_id
                             WHERE ur.user_id = p.id), '[]'::jsonb)
  )
  FROM profiles p WHERE p.id = app_current_user_id();
$$;
COMMENT ON FUNCTION fn_me() IS 'Returns the current user profile, role codes and permission codes as JSON for client bootstrap.';

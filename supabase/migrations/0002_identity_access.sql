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

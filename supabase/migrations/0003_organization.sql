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

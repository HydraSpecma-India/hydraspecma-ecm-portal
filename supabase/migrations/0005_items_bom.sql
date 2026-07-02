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

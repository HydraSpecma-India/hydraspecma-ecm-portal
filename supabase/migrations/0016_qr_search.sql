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

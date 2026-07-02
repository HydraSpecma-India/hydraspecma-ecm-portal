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

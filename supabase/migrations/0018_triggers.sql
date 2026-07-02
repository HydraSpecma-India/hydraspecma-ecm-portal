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

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

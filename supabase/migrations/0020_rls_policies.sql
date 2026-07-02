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

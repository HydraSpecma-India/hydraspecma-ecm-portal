-- =============================================================================
-- 40_templates.sql — Document categories, email templates, notification rules,
-- report catalog, and integration endpoints. Idempotent.
-- =============================================================================
BEGIN;

-- ---- Document categories ----------------------------------------------------
INSERT INTO document_categories (code, name, description, allowed_extensions, requires_approval) VALUES
  ('DRAWING','Engineering Drawing','2D/3D drawings',        ARRAY['pdf','dwg','dxf','tiff','png'], true),
  ('CAD','CAD File','Native CAD models',                    ARRAY['sldprt','sldasm','step','stp','iges','igs','catpart','prt'], true),
  ('SPEC','Specification','Technical specifications',        ARRAY['pdf','docx','xlsx'], true),
  ('WORK_INSTR','Work Instruction','Shop-floor instructions',ARRAY['pdf','docx'], true),
  ('PDF','PDF Document','General PDF',                        ARRAY['pdf'], false),
  ('IMAGE','Image','Photos & images',                        ARRAY['png','jpg','jpeg','gif','webp'], false),
  ('REPORT','Report','Generated reports & packages',         ARRAY['pdf','xlsx','csv','docx'], false)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, allowed_extensions = EXCLUDED.allowed_extensions, requires_approval = EXCLUDED.requires_approval;

-- ---- Email templates --------------------------------------------------------
INSERT INTO email_templates (code, name, subject, body_html, body_text, variables) VALUES
  ('APPROVAL_REQUEST','Approval Request','Action required: {{ecm_number}} - {{title}}',
   '<h2>Approval requested</h2><p>{{requestor_name}} requests your decision on <b>{{ecm_number}}</b> - {{title}}.</p><p><a href="{{approve_url}}">Approve</a> &middot; <a href="{{reject_url}}">Reject</a> &middot; <a href="{{return_url}}">Return</a></p><p>Due: {{due_date}}</p>',
   'Approval requested for {{ecm_number}} - {{title}}. Approve: {{approve_url}} Reject: {{reject_url}} Return: {{return_url}}',
   '["ecm_number","title","requestor_name","approve_url","reject_url","return_url","due_date"]'::jsonb),
  ('APPROVAL_REMINDER','Approval Reminder','Reminder: {{ecm_number}} awaits your approval',
   '<p>This is a reminder that <b>{{ecm_number}}</b> - {{title}} is awaiting your approval since {{requested_at}}.</p><p><a href="{{approve_url}}">Open request</a></p>',
   'Reminder: {{ecm_number}} - {{title}} awaits your approval. {{approve_url}}',
   '["ecm_number","title","requested_at","approve_url"]'::jsonb),
  ('APPROVAL_ESCALATION','Approval Escalation','Escalation: {{ecm_number}} overdue for approval',
   '<p><b>{{ecm_number}}</b> - {{title}} has exceeded its approval SLA and has been escalated to you.</p><p><a href="{{approve_url}}">Review now</a></p>',
   'Escalation: {{ecm_number}} - {{title}} overdue. {{approve_url}}',
   '["ecm_number","title","approve_url"]'::jsonb),
  ('TASK_ASSIGNED','Task Assigned','New task on {{ecm_number}}: {{task_title}}',
   '<p>You have been assigned a task on <b>{{ecm_number}}</b>: {{task_title}}.</p><p>Due: {{due_date}} &middot; <a href="{{task_url}}">Open task</a></p>',
   'New task on {{ecm_number}}: {{task_title}} (due {{due_date}}). {{task_url}}',
   '["ecm_number","task_title","due_date","task_url"]'::jsonb),
  ('ECM_STATUS_CHANGED','Status Changed','{{ecm_number}} moved to {{state_name}}',
   '<p><b>{{ecm_number}}</b> - {{title}} moved from {{from_state}} to <b>{{state_name}}</b> by {{actor_name}}.</p><p><a href="{{ecm_url}}">View</a></p>',
   '{{ecm_number}} moved to {{state_name}} by {{actor_name}}. {{ecm_url}}',
   '["ecm_number","title","from_state","state_name","actor_name","ecm_url"]'::jsonb)
ON CONFLICT (code) DO UPDATE SET subject = EXCLUDED.subject, body_html = EXCLUDED.body_html, body_text = EXCLUDED.body_text, variables = EXCLUDED.variables;

-- ---- Notification rules -----------------------------------------------------
INSERT INTO notification_rules (code, event_type, description, channel, template_id, recipient_expression) VALUES
  ('RULE_APPROVAL_PENDING','approval.pending','Notify approvers when a gate opens','email',(SELECT id FROM email_templates WHERE code='APPROVAL_REQUEST'),'assignee'),
  ('RULE_APPROVAL_REMINDER','approval.reminder','Remind pending approvers','email',(SELECT id FROM email_templates WHERE code='APPROVAL_REMINDER'),'assignee'),
  ('RULE_APPROVAL_ESCALATION','approval.escalation','Escalate overdue approvals','email',(SELECT id FROM email_templates WHERE code='APPROVAL_ESCALATION'),'manager'),
  ('RULE_TASK_ASSIGNED','task.assigned','Notify assignee of a new task','in_app',(SELECT id FROM email_templates WHERE code='TASK_ASSIGNED'),'assignee'),
  ('RULE_STATUS_CHANGED','ecm.transition','Notify owner on status change','in_app',(SELECT id FROM email_templates WHERE code='ECM_STATUS_CHANGED'),'owner'),
  ('RULE_MENTION','comment.mention','Notify mentioned users','in_app',NULL,'mentions')
ON CONFLICT (code) DO UPDATE SET event_type = EXCLUDED.event_type, channel = EXCLUDED.channel, recipient_expression = EXCLUDED.recipient_expression;

-- ---- Report catalog ---------------------------------------------------------
INSERT INTO report_definitions (code, name, category, description, source_view) VALUES
  ('EXEC_SUMMARY','Executive Summary','executive','Portfolio KPIs & trends','vw_dashboard_kpis'),
  ('CYCLE_TIME','Cycle Time Report','cycle_time','Lead & cycle time per ECM','vw_cycle_time'),
  ('APPROVAL_PERF','Approval Performance','approval','Approval durations & bottlenecks','vw_approval_duration'),
  ('DEPT_PERF','Department Performance','department','Requests & throughput per department','vw_department_requests'),
  ('BOTTLENECK','Bottleneck Analysis','engineering','Dwell time vs SLA per state','vw_bottleneck_analysis'),
  ('COMPLIANCE','Compliance Report','compliance','Audit trail & e-signature coverage','audit_logs')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, category = EXCLUDED.category, source_view = EXCLUDED.source_view;

-- ---- Integration endpoints (inactive until configured with secrets) --------
INSERT INTO integration_endpoints (system, name, odata_path, auth_type, is_active, config) VALUES
  ('D365FO','Dynamics 365 F&O','/data','oauth2_client_credentials', false, '{"entities":["ReleasedProducts","BillOfMaterials","Routes","Customers","Vendors","PurchaseOrders","ProductionOrders","InventOnhand"]}'::jsonb),
  ('GRAPH','Microsoft Graph', NULL,'oauth2_auth_code', false, '{"scopes":["User.Read","Mail.Send","Calendars.ReadWrite"]}'::jsonb),
  ('POWERBI','Power BI Embedded', NULL,'oauth2_client_credentials', false, '{}'::jsonb)
ON CONFLICT (system, name) DO UPDATE SET odata_path = EXCLUDED.odata_path, config = EXCLUDED.config;

COMMIT;

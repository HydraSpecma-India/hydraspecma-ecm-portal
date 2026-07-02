-- HydraSpecma ECM Portal — FULL SEED (generated)

-- >>> supabase/seed/10_rbac.sql
-- =============================================================================
-- 10_rbac.sql — Roles, permission catalog, and the role→permission matrix.
-- Idempotent. Codes align with config/app.config.js and wf transition permissions.
-- =============================================================================
BEGIN;

-- ---- Roles (13) -------------------------------------------------------------
INSERT INTO roles (code, name, description, hierarchy_level, is_system) VALUES
  ('SUPER_ADMIN','Super Admin','Platform owner; unrestricted access',            0,  true),
  ('ECM_ADMIN','ECM Administrator','Administers the ECM portal & configuration', 10, true),
  ('ENG_MANAGER','Engineering Manager','Owns engineering decisions & approvals', 20, true),
  ('CR_BOARD','CR Board','Change Review Board member',                            25, true),
  ('DEPT_HEAD','Department Head','Leads a department',                            30, true),
  ('QUALITY','Quality','Quality department',                                     40, true),
  ('PRODUCTION','Production','Production department',                            40, true),
  ('PLANNING','Planning','Planning department',                                 40, true),
  ('PURCHASING','Purchasing','Purchasing department',                           40, true),
  ('WAREHOUSE','Warehouse','Warehouse department',                              40, true),
  ('FINANCE','Finance','Finance department',                                    40, true),
  ('ENGINEER','Engineer','Creates and executes changes',                        50, true),
  ('VIEWER','Viewer','Read-only access',                                        90, true)
ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name, description = EXCLUDED.description,
      hierarchy_level = EXCLUDED.hierarchy_level, is_system = EXCLUDED.is_system;

-- ---- Permission catalog -----------------------------------------------------
INSERT INTO permissions (code, module, action, description) VALUES
  ('ecm.read','ecm','read','View change records'),
  ('ecm.create','ecm','create','Create pre-requests / ECMs'),
  ('ecm.update','ecm','update','Edit change records'),
  ('ecm.submit','ecm','submit','Submit pre-request for screening'),
  ('ecm.screen','ecm','screen','Screen / decide go-ahead'),
  ('ecm.delete','ecm','delete','Delete change records'),
  ('ecr.create','ecr','create','Create ECRs'),
  ('ecr.submit','ecr','submit','Submit ECR to CR-board'),
  ('ecr.crb_decide','ecr','approve','CR-board decision'),
  ('ecr.customer_decide','ecr','approve','Customer decision on ECR'),
  ('eco.create','eco','create','Create ECOs'),
  ('eco.manage','eco','update','Manage ECO implementation'),
  ('eco.review','eco','review','Review implementation'),
  ('eco.release','eco','release','Release for production'),
  ('eco.close','eco','close','Resolve / close change'),
  ('workflow.transition','workflow','transition','Fire workflow transitions'),
  ('workflow.manage','workflow','manage','Edit workflow definitions'),
  ('task.manage','task','manage','Manage tasks'),
  ('document.read','document','read','View controlled documents'),
  ('document.manage','document','manage','Manage documents & versions'),
  ('approval.manage','approval','manage','Manage approvals'),
  ('audit.read','audit','read','View the audit trail'),
  ('integration.read','integration','read','View integration logs'),
  ('integration.manage','integration','manage','Manage integrations'),
  ('report.view','report','view','View reports & analytics'),
  ('ai.use','ai','use','Use the AI assistant'),
  ('admin.manage','admin','manage','Administer users, roles & settings')
ON CONFLICT (code) DO UPDATE SET module = EXCLUDED.module, action = EXCLUDED.action, description = EXCLUDED.description;

-- ---- Full access for SUPER_ADMIN and ECM_ADMIN ------------------------------
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.code IN ('SUPER_ADMIN','ECM_ADMIN')
ON CONFLICT DO NOTHING;

-- ---- Scoped matrix for the remaining roles ---------------------------------
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM (VALUES
  -- Engineering Manager
  ('ENG_MANAGER','ecm.read'),('ENG_MANAGER','ecm.create'),('ENG_MANAGER','ecm.update'),
  ('ENG_MANAGER','ecm.submit'),('ENG_MANAGER','ecm.screen'),('ENG_MANAGER','ecr.create'),
  ('ENG_MANAGER','ecr.submit'),('ENG_MANAGER','ecr.crb_decide'),('ENG_MANAGER','ecr.customer_decide'),
  ('ENG_MANAGER','eco.create'),('ENG_MANAGER','eco.manage'),('ENG_MANAGER','eco.review'),
  ('ENG_MANAGER','eco.release'),('ENG_MANAGER','eco.close'),('ENG_MANAGER','workflow.transition'),
  ('ENG_MANAGER','task.manage'),('ENG_MANAGER','document.read'),('ENG_MANAGER','document.manage'),
  ('ENG_MANAGER','approval.manage'),('ENG_MANAGER','report.view'),('ENG_MANAGER','ai.use'),
  -- CR Board
  ('CR_BOARD','ecm.read'),('CR_BOARD','ecr.crb_decide'),('CR_BOARD','workflow.transition'),
  ('CR_BOARD','approval.manage'),('CR_BOARD','document.read'),('CR_BOARD','report.view'),('CR_BOARD','ai.use'),
  -- Department Head
  ('DEPT_HEAD','ecm.read'),('DEPT_HEAD','ecm.create'),('DEPT_HEAD','ecm.update'),('DEPT_HEAD','ecm.submit'),
  ('DEPT_HEAD','task.manage'),('DEPT_HEAD','document.read'),('DEPT_HEAD','approval.manage'),
  ('DEPT_HEAD','report.view'),('DEPT_HEAD','ai.use'),
  -- Engineer
  ('ENGINEER','ecm.read'),('ENGINEER','ecm.create'),('ENGINEER','ecm.update'),('ENGINEER','ecm.submit'),
  ('ENGINEER','workflow.transition'),('ENGINEER','task.manage'),('ENGINEER','document.read'),
  ('ENGINEER','document.manage'),('ENGINEER','report.view'),('ENGINEER','ai.use'),
  -- Functional departments (Quality/Production/Planning/Purchasing/Warehouse)
  ('QUALITY','ecm.read'),('QUALITY','ecm.update'),('QUALITY','task.manage'),('QUALITY','document.read'),('QUALITY','document.manage'),('QUALITY','report.view'),('QUALITY','ai.use'),
  ('PRODUCTION','ecm.read'),('PRODUCTION','ecm.update'),('PRODUCTION','task.manage'),('PRODUCTION','document.read'),('PRODUCTION','report.view'),('PRODUCTION','ai.use'),
  ('PLANNING','ecm.read'),('PLANNING','ecm.update'),('PLANNING','task.manage'),('PLANNING','document.read'),('PLANNING','report.view'),('PLANNING','ai.use'),
  ('PURCHASING','ecm.read'),('PURCHASING','ecm.update'),('PURCHASING','task.manage'),('PURCHASING','document.read'),('PURCHASING','report.view'),('PURCHASING','ai.use'),
  ('WAREHOUSE','ecm.read'),('WAREHOUSE','ecm.update'),('WAREHOUSE','task.manage'),('WAREHOUSE','document.read'),('WAREHOUSE','report.view'),('WAREHOUSE','ai.use'),
  -- Finance
  ('FINANCE','ecm.read'),('FINANCE','ecm.update'),('FINANCE','document.read'),('FINANCE','approval.manage'),('FINANCE','report.view'),('FINANCE','ai.use'),
  -- Viewer
  ('VIEWER','ecm.read'),('VIEWER','document.read'),('VIEWER','report.view')
) AS map(role_code, perm_code)
JOIN roles r       ON r.code = map.role_code
JOIN permissions p ON p.code = map.perm_code
ON CONFLICT DO NOTHING;

COMMIT;

-- >>> supabase/seed/20_org.sql
-- =============================================================================
-- 20_org.sql — Organization master data (plants, departments, sample partners).
-- Sample values are editable in the Admin Panel. Idempotent.
-- =============================================================================
BEGIN;

INSERT INTO plants (code, name, city, country, timezone) VALUES
  ('DK01','HydraSpecma Denmark','Svendborg','Denmark','Europe/Copenhagen'),
  ('SE01','HydraSpecma Sweden','Gothenburg','Sweden','Europe/Stockholm'),
  ('CN01','HydraSpecma China','Suzhou','China','Asia/Shanghai'),
  ('IN01','HydraSpecma India','Chennai','India','Asia/Kolkata'),
  ('US01','HydraSpecma USA','Charlotte','United States','America/New_York')
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, city = EXCLUDED.city, country = EXCLUDED.country;

INSERT INTO departments (code, name, description, plant_id)
SELECT d.code, d.name, d.description, (SELECT id FROM plants WHERE code = 'DK01')
FROM (VALUES
  ('ENG','Engineering','Design & engineering'),
  ('QA','Quality','Quality assurance & PPAP'),
  ('PROD','Production','Manufacturing & assembly'),
  ('PLAN','Planning','Production planning & scheduling'),
  ('PURCH','Purchasing','Procurement & supplier management'),
  ('WH','Warehouse','Inventory & logistics'),
  ('FIN','Finance','Finance & controlling')
) AS d(code, name, description)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, description = EXCLUDED.description;

INSERT INTO customers (code, name, country) VALUES
  ('CUST-DEMO-01','Demo Customer A','Germany'),
  ('CUST-DEMO-02','Demo Customer B','Denmark')
ON CONFLICT (code) DO NOTHING;

INSERT INTO suppliers (code, name, country) VALUES
  ('SUP-DEMO-01','Demo Supplier X','Poland'),
  ('SUP-DEMO-02','Demo Supplier Y','Italy')
ON CONFLICT (code) DO NOTHING;

COMMIT;

-- >>> supabase/seed/30_workflow.sql
-- =============================================================================
-- 30_workflow.sql  —  Workflow import (GENERATED from workflow/ecm-flow.json)
-- Source: ECM Flow.xlsx  |  DO NOT EDIT BY HAND — re-run workflow/build_workflow_seed.py
-- Idempotent: safe to run repeatedly (ON CONFLICT upserts).
-- =============================================================================
BEGIN;

-- 1) Workflow definition -----------------------------------------------------
INSERT INTO wf_workflows (id, code, name, version, description, source_document, is_active, effective_from)
VALUES ('dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'HYDRA-ECM-STD', 'HydraSpecma Standard Engineering Change Flow', 1, 'Pre-request -> ECR -> ECO -> Resolved. Derived from HydraSpecma ECM Flow workbook.', 'ECM Flow.xlsx', true, CURRENT_DATE)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description,
  source_document=EXCLUDED.source_document, is_active=EXCLUDED.is_active, updated_at=now();

-- 2) Stages ------------------------------------------------------------------
INSERT INTO wf_stages (id, workflow_id, code, name, sequence, entity_type, color, description) VALUES
  ('b2764a0f-1120-5566-9b36-1afc3778d8d1', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'PRE', 'Pre-request', 10, 'ECM', '#64748B', 'Idea capture, information gathering and screening/go-ahead decision.'),
  ('5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'ECR', 'ECR', 20, 'ECR', '#0EA5E9', 'Engineering Change Request: impact analysis, solution, CR-board and customer decision.'),
  ('d99503b9-a032-573c-b1eb-6fa44e60d384', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'ECO', 'ECO', 30, 'ECO', '#00A3E0', 'Engineering Change Order: implementation planning, execution, review and release.'),
  ('999382a5-909d-5915-a452-3fc6a0338baa', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'CLOSED', 'Closed', 40, 'ECM', '#16A34A', 'Terminal grouping for resolved / rejected / cancelled changes.')
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, sequence=EXCLUDED.sequence,
  entity_type=EXCLUDED.entity_type, color=EXCLUDED.color, description=EXCLUDED.description;

-- 3) States ------------------------------------------------------------------
INSERT INTO wf_states (id, workflow_id, stage_id, code, name, sequence, category, is_initial, is_terminal, sla_hours, color, description) VALUES
  ('eb77c94c-7aa6-5688-a7e5-78f9fbeaf35c', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_DRAFT', 'Draft', 10, 'draft', true, false, 72, NULL, 'Requestor fills in the pre-request.'),
  ('6531cfd9-7569-5461-b4a3-32969e63b364', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_SCREENING', 'Screening', 20, 'screening', false, false, 48, NULL, 'Under review; go-ahead decision is taken.'),
  ('9197ea3c-18d2-5f19-b2ba-51a5f61f27ed', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_ACCEPTED', 'Accepted', 30, 'accepted', false, false, NULL, NULL, 'Pre-request accepted; linked to an ECR.'),
  ('98a37ebb-95f8-5683-8f41-3f5920b35699', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_HOLD', 'Hold', 40, 'hold', false, false, NULL, NULL, 'Temporarily paused.'),
  ('d87c1632-f042-567f-8d3a-ba9d96e92bca', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_BACKLOG', 'Backlog', 50, 'backlog', false, false, NULL, NULL, 'Waiting for an implementation opportunity.'),
  ('754e6a5d-4d95-5b58-8e46-2ffee11b57f0', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_REJECTED', 'Rejected', 60, 'rejected', false, true, NULL, NULL, 'No action will be taken.'),
  ('f0387007-0b86-5629-90b7-6c52f52ae105', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'PRE_CANCELLED', 'Cancelled', 70, 'cancelled', false, true, NULL, NULL, 'Solved by another change.'),
  ('40c16489-836d-5f82-b6b4-e544b528de61', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_PREP', 'Implementation preparation', 10, 'in_progress', true, false, 120, NULL, 'ECR number shared; impact analysed; solution prepared and reviewed.'),
  ('93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_CRB', 'CR-board', 20, 'approval', false, false, 72, NULL, 'Change Review Board meeting and go-ahead decision.'),
  ('794519d7-a59a-5d81-a644-39eaabf6cbbf', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_PRELIM', 'Preliminary accepted', 30, 'in_progress', false, false, 120, NULL, 'Preliminary accepted; customer discussion and decision.'),
  ('a98c93c8-2c2a-570d-8736-331c06a769d3', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_ACCEPTED', 'Accepted', 40, 'accepted', false, false, NULL, NULL, 'ECR accepted; linked to an ECO.'),
  ('0887a83d-05ee-5f98-9d8a-d0134010b9fd', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_HOLD', 'Hold', 50, 'hold', false, false, NULL, NULL, 'Temporarily paused.'),
  ('5c5b9831-7cdb-53ea-8ee2-7e7f46250274', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_BACKLOG', 'Backlog', 60, 'backlog', false, false, NULL, NULL, 'Waiting for an implementation opportunity.'),
  ('fe3df65e-3db8-5440-8f22-87c39c07d355', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_REJECTED', 'Rejected', 70, 'rejected', false, true, NULL, NULL, 'No action will be taken.'),
  ('f1fea313-0658-5f2f-b11a-7d7f006cb420', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', 'ECR_CANCELLED', 'Cancelled', 80, 'cancelled', false, true, NULL, NULL, 'Solved by another change.'),
  ('ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_TASKLIST', 'Task list', 10, 'in_progress', true, false, 72, NULL, 'ECO created, stakeholders informed and implementation task list built.'),
  ('72172731-384f-596b-a4a4-34b2ac1548e9', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_REVIEW_TASKS', 'Review task list', 20, 'review', false, false, 48, NULL, 'Implementation task list reviewed/evaluated.'),
  ('37b55478-5440-5a02-ade3-0fc6c4c45a95', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_IMPL', 'Implementation', 30, 'in_progress', false, false, 240, NULL, 'Execute implementation plan (items, BOM, docs, purchasing, PPAP).'),
  ('e0034bb4-dfb9-5852-b5c9-1cd574945ca0', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_IMPL_REVIEW', 'Implementation review', 40, 'review', false, false, 48, NULL, 'Review implementation; accept or rework.'),
  ('5ee57271-8c5e-5479-a875-a1cca0d8e0f3', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_REL_SCHED', 'Released for scheduling', 50, 'in_progress', false, false, 72, NULL, 'Local scheduling and customer agreement.'),
  ('28dbca06-fab1-5613-b0c2-df481c05a3e8', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_REL_PROD', 'Released for production', 60, 'in_progress', false, false, 240, NULL, 'Update ECO/component data, PPAP follow-up, orders, stock clean-up, quality.'),
  ('68c86e15-a528-55eb-b385-f972c92ddda2', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_FINAL_REVIEW', 'Final review', 70, 'review', false, false, 48, NULL, 'Final review/evaluation of the implementation.'),
  ('9f534976-f4a8-50a9-a381-b4884ca66660', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_REJECTED', 'Rejected', 80, 'rejected', false, true, NULL, NULL, 'No action will be taken.'),
  ('616ef3e8-6a37-57b1-9187-8aea57e88b79', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ECO_CANCELLED', 'Cancelled', 90, 'cancelled', false, true, NULL, NULL, 'Solved by another change.'),
  ('b10b8bde-840c-50fb-999e-85207e736ef9', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '999382a5-909d-5915-a452-3fc6a0338baa', 'RESOLVED', 'Resolved', 10, 'resolved', false, true, NULL, '#16A34A', 'Change successfully implemented and closed.')
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, sequence=EXCLUDED.sequence, category=EXCLUDED.category,
  is_initial=EXCLUDED.is_initial, is_terminal=EXCLUDED.is_terminal, sla_hours=EXCLUDED.sla_hours,
  color=EXCLUDED.color, description=EXCLUDED.description;

-- 4) Transitions -------------------------------------------------------------
INSERT INTO wf_transitions (id, workflow_id, from_state_id, to_state_id, action_code, action_label, required_permission, requires_comment, requires_approval, side_effect, sort_order) VALUES
  ('88bfefe1-c0b0-5f70-ac38-35aa2b699b82', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'eb77c94c-7aa6-5688-a7e5-78f9fbeaf35c', '6531cfd9-7569-5461-b4a3-32969e63b364', 'submit', 'Submit pre-request for screening', 'ecm.submit', false, false, NULL, 10),
  ('25d646f6-cfc6-58d6-a62b-3a1079e68792', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', '9197ea3c-18d2-5f19-b2ba-51a5f61f27ed', 'accept', 'Accept pre-request', 'ecm.screen', true, false, NULL, 10),
  ('858649f2-c1b6-569d-a65f-48bf3e3cae5f', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', 'eb77c94c-7aa6-5688-a7e5-78f9fbeaf35c', 'return', 'Return pre-request', 'ecm.screen', true, false, NULL, 20),
  ('4e1d31e9-b7fa-5ee2-be47-6569bef9e9d9', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', '98a37ebb-95f8-5683-8f41-3f5920b35699', 'hold', 'Hold pre-request', 'ecm.screen', true, false, NULL, 30),
  ('86ffec61-d97d-5f9b-877e-36fa3566d959', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', 'd87c1632-f042-567f-8d3a-ba9d96e92bca', 'backlog', 'Move to backlog', 'ecm.screen', false, false, NULL, 40),
  ('4e6e4c70-8541-5fb1-babe-1180890bd145', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', '754e6a5d-4d95-5b58-8e46-2ffee11b57f0', 'reject', 'Reject pre-request', 'ecm.screen', true, false, NULL, 50),
  ('01808506-4f7c-52b2-a7fb-830b65b3d6f3', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '6531cfd9-7569-5461-b4a3-32969e63b364', 'f0387007-0b86-5629-90b7-6c52f52ae105', 'cancel', 'Cancel pre-request', 'ecm.screen', true, false, NULL, 60),
  ('1e9f7ed8-ecb2-5cf3-949c-2630667282ed', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '98a37ebb-95f8-5683-8f41-3f5920b35699', '6531cfd9-7569-5461-b4a3-32969e63b364', 'resume', 'Resume screening', 'ecm.screen', false, false, NULL, 10),
  ('d0ba968b-3544-5788-bb67-3f5697cf73fa', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd87c1632-f042-567f-8d3a-ba9d96e92bca', '6531cfd9-7569-5461-b4a3-32969e63b364', 'reactivate', 'Reactivate from backlog', 'ecm.screen', false, false, NULL, 10),
  ('045e19ab-8708-527b-9404-82f87bde5c4f', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '9197ea3c-18d2-5f19-b2ba-51a5f61f27ed', '40c16489-836d-5f82-b6b4-e544b528de61', 'link_to_ecr', 'Create ECR & share number', 'ecr.create', false, false, 'create_ecr', 10),
  ('8e90b589-366a-51f1-8ea6-5cc4aaa710f7', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '40c16489-836d-5f82-b6b4-e544b528de61', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'submit_to_crb', 'Submit solution to CR-board', 'ecr.submit', false, false, NULL, 10),
  ('82b8db28-9198-5b11-a00d-535990121273', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 'prelim_accept', 'Preliminary accept (CRB)', 'ecr.crb_decide', true, true, NULL, 10),
  ('f8693b5d-6999-5fcf-b3e1-542d75cc9210', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', '40c16489-836d-5f82-b6b4-e544b528de61', 'return', 'Return solution', 'ecr.crb_decide', true, false, NULL, 20),
  ('6cf03118-1d2c-5739-b26f-0a11ed03d944', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', '0887a83d-05ee-5f98-9d8a-d0134010b9fd', 'hold', 'Hold solution', 'ecr.crb_decide', true, false, NULL, 30),
  ('63e0125b-ea31-59d2-9bf7-966cf246c1e9', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', '5c5b9831-7cdb-53ea-8ee2-7e7f46250274', 'backlog', 'Move to backlog', 'ecr.crb_decide', false, false, NULL, 40),
  ('a1001d43-e661-5dbc-b6c5-14a791bb0313', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'fe3df65e-3db8-5440-8f22-87c39c07d355', 'reject', 'Reject solution', 'ecr.crb_decide', true, true, NULL, 50),
  ('301be081-a703-5cd3-9fac-1fe69087d2fa', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'f1fea313-0658-5f2f-b11a-7d7f006cb420', 'cancel', 'Cancel ECR', 'ecr.crb_decide', true, false, NULL, 60),
  ('3f1d0d6e-7e66-53dd-9a6f-4a73e4905ee0', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '0887a83d-05ee-5f98-9d8a-d0134010b9fd', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'resume', 'Resume at CR-board', 'ecr.crb_decide', false, false, NULL, 10),
  ('02f4304a-aae1-5e8f-b46a-e9291d0bc7a1', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c5b9831-7cdb-53ea-8ee2-7e7f46250274', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 'reactivate', 'Reactivate from backlog', 'ecr.crb_decide', false, false, NULL, 10),
  ('eaf6d615-5b5d-5985-ad89-17e44a2aea02', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 'a98c93c8-2c2a-570d-8736-331c06a769d3', 'customer_accept', 'Customer accepts ECR', 'ecr.customer_decide', true, false, NULL, 10),
  ('2144a949-b198-51d2-bb26-9ad077e481df', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 'fe3df65e-3db8-5440-8f22-87c39c07d355', 'customer_reject', 'Customer rejects ECR', 'ecr.customer_decide', true, false, NULL, 20),
  ('788f1e05-2a48-5594-9524-5fbcbe7d1ac4', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 'f1fea313-0658-5f2f-b11a-7d7f006cb420', 'cancel', 'Cancel ECR', 'ecr.customer_decide', true, false, NULL, 30),
  ('39013026-3149-5f26-ac96-ae9633414d6e', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'a98c93c8-2c2a-570d-8736-331c06a769d3', 'ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', 'link_to_eco', 'Create ECO & inform stakeholders', 'eco.create', false, false, 'create_eco', 10),
  ('08bb1d6e-28a8-537e-8f8a-e24e2252b307', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', '72172731-384f-596b-a4a4-34b2ac1548e9', 'submit_tasklist', 'Submit task list for review', 'eco.manage', false, false, NULL, 10),
  ('799f8f96-1498-557e-8338-85eab2a33384', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '72172731-384f-596b-a4a4-34b2ac1548e9', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 'accept', 'Accept task list', 'eco.review', true, false, NULL, 10),
  ('5b223132-82a7-54d9-8108-0574d42c9387', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '72172731-384f-596b-a4a4-34b2ac1548e9', 'ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', 'rework', 'Rework task list', 'eco.review', true, false, NULL, 20),
  ('82e15f3e-35f8-5f02-929f-884c7faa38fc', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 'e0034bb4-dfb9-5852-b5c9-1cd574945ca0', 'submit_review', 'Submit implementation for review', 'eco.manage', false, false, NULL, 10),
  ('9b706281-3081-5bf0-8209-2c545d46f015', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'e0034bb4-dfb9-5852-b5c9-1cd574945ca0', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', 'accept', 'Accept implementation', 'eco.review', true, true, NULL, 10),
  ('4578afb7-273e-5552-b872-4ab18d54e57e', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'e0034bb4-dfb9-5852-b5c9-1cd574945ca0', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 'rework', 'Rework implementation', 'eco.review', true, false, NULL, 20),
  ('4ed89e1c-1e27-5ace-9809-896a66153eab', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 'release_prod', 'Release for production', 'eco.release', true, true, NULL, 10),
  ('1639a0ed-e266-5f31-96a0-4994736411d0', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', '9f534976-f4a8-50a9-a381-b4884ca66660', 'reject', 'Reject (customer)', 'eco.review', true, false, NULL, 20),
  ('24fc5e16-06ec-5958-834d-d82baa956019', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', '616ef3e8-6a37-57b1-9187-8aea57e88b79', 'cancel', 'Cancel ECO', 'eco.review', true, false, NULL, 30),
  ('660ca452-2b5e-52c6-a489-b7a75733d5f5', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '28dbca06-fab1-5613-b0c2-df481c05a3e8', '68c86e15-a528-55eb-b385-f972c92ddda2', 'submit_final', 'Submit for final review', 'eco.manage', false, false, NULL, 10),
  ('34135668-a330-52f7-ab20-87f5718feb3d', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '68c86e15-a528-55eb-b385-f972c92ddda2', 'b10b8bde-840c-50fb-999e-85207e736ef9', 'resolve', 'Resolve & close', 'eco.close', true, true, 'close_ecm', 10),
  ('94ebead8-6bfd-53eb-bd92-15a4f75eb248', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '68c86e15-a528-55eb-b385-f972c92ddda2', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 'rework', 'Rework (production)', 'eco.review', true, false, NULL, 20)
ON CONFLICT (id) DO UPDATE SET action_label=EXCLUDED.action_label, required_permission=EXCLUDED.required_permission,
  requires_comment=EXCLUDED.requires_comment, requires_approval=EXCLUDED.requires_approval,
  side_effect=EXCLUDED.side_effect, sort_order=EXCLUDED.sort_order;

-- 5) Task templates (default role resolved by code) --------------------------
INSERT INTO wf_task_templates (id, workflow_id, stage_id, state_id, seq_number, title, description, task_type, is_mandatory, default_assignee_role_id, sla_hours) VALUES
  ('069a2994-d7e6-5c21-b105-11180b3d0f17', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'eb77c94c-7aa6-5688-a7e5-78f9fbeaf35c', 10, 'Fill in information in the pre-request', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('a9297f11-5b7c-5af1-b392-5d2cb2ad06ae', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', 'eb77c94c-7aa6-5688-a7e5-78f9fbeaf35c', 20, 'Submit pre-request for screening', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('f26d668a-d97d-540c-8ab0-19e5e1276f14', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'b2764a0f-1120-5566-9b36-1afc3778d8d1', '6531cfd9-7569-5461-b4a3-32969e63b364', 30, 'Decide on go-ahead (accept / reject / return / hold)', '', 'decision', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('6fb2722a-ec0e-5db1-9d11-7ac5bed23d68', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '40c16489-836d-5f82-b6b4-e544b528de61', 10, 'ECR created and ECR number shared with requestor', '', 'task', true, (SELECT id FROM roles WHERE code='ECM_ADMIN'), NULL),
  ('b2a958d2-ee28-5e3b-a006-495633dcd73d', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '40c16489-836d-5f82-b6b4-e544b528de61', 20, 'Analyse impact & prepare solution', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('f6778d67-1688-5f15-b00c-e3ebb0d2d361', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '40c16489-836d-5f82-b6b4-e544b528de61', 30, 'Review solution', '', 'review', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('b9369043-c3d6-5aeb-b1bd-49abe5f6bb21', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 10, 'CRB meeting', '', 'meeting', true, (SELECT id FROM roles WHERE code='CR_BOARD'), NULL),
  ('2056fc17-ab35-5134-8464-81a39b7251a5', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '93afe9f5-fd75-5d4f-97f8-d3af7cb3be59', 20, 'Decide on go-ahead', '', 'decision', true, (SELECT id FROM roles WHERE code='CR_BOARD'), NULL),
  ('58348183-9576-5182-81ed-8c198e5515cd', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 10, 'Discussion with customer', '', 'task', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('c16cc499-12c7-5918-a599-332c239ebc3f', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', '5c1e32b3-5d59-505a-a23f-5796f7a7e184', '794519d7-a59a-5d81-a644-39eaabf6cbbf', 20, 'Customer decision', '', 'decision', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('5dd0b290-d0ee-53e8-a202-f5745e0b1a46', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', 10, 'Create ECO & inform stakeholders', '', 'task', true, (SELECT id FROM roles WHERE code='ECM_ADMIN'), NULL),
  ('d6b3daef-3170-5a4a-8b94-85af06e60efa', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'ab24b0f1-1d0b-5768-afb6-4b3e36f1a76e', 20, 'Create implementation task list', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('6a5b462a-0ec2-5eb2-a338-abaaef8f6d9f', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '72172731-384f-596b-a4a4-34b2ac1548e9', 10, 'Review / evaluate implementation task list', '', 'review', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('e799bf0a-c61f-5867-9d4f-9d6de70eab80', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 10, 'Execute implementation plan', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('c53e823d-a08f-5f69-a486-fbf3c1e26419', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 20, 'Create new item number', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('722da890-22e7-5c8c-b226-99e53c5349cf', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 30, 'Create / update BOM', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('b001c38a-c268-52bd-a78e-7e9eada610e4', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 40, 'Create / update documents', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('21d826d1-71a7-54d9-8e00-c4d7fe6fa609', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 50, 'Release BOM to site', '', 'task', true, (SELECT id FROM roles WHERE code='PLANNING'), NULL),
  ('f476bc00-fcd5-5b3e-ad47-e0cdaa5e42c2', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 60, 'Prepare components for purchase', '', 'task', true, (SELECT id FROM roles WHERE code='PURCHASING'), NULL),
  ('91e0d3af-24ad-59cb-9a35-febf3bbdf679', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '37b55478-5440-5a02-ade3-0fc6c4c45a95', 70, 'Define PPAP', '', 'task', true, (SELECT id FROM roles WHERE code='QUALITY'), NULL),
  ('9978fd4a-4145-52b3-8921-a984611f20e7', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', 'e0034bb4-dfb9-5852-b5c9-1cd574945ca0', 10, 'Review implementation (accept / rework)', '', 'review', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('c8e1336e-8096-5c4f-9e11-b6732addf63a', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', 10, 'Local schedule', '', 'task', true, (SELECT id FROM roles WHERE code='PLANNING'), NULL),
  ('05bfb1ef-5fc0-510c-828e-87b312b407c2', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '5ee57271-8c5e-5479-a875-a1cca0d8e0f3', 20, 'Agreement with customer', '', 'task', false, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('61431e57-fe62-5a2c-a43e-e6310d00a912', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 10, 'Update ECO', '', 'task', true, (SELECT id FROM roles WHERE code='ECM_ADMIN'), NULL),
  ('cf3ca11b-7d7c-5850-96b7-9f42ef69da73', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 20, 'Update component data', '', 'task', true, (SELECT id FROM roles WHERE code='ENGINEER'), NULL),
  ('7335f697-b2b7-51ac-8d4f-d5571370bc3c', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 30, 'Follow up on PPAP', '', 'task', true, (SELECT id FROM roles WHERE code='QUALITY'), NULL),
  ('e1b3a8c7-2560-58e4-a98a-ea5565e7b2f7', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 40, 'Inform customer', '', 'task', false, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL),
  ('97aa2a26-6d37-598e-bbef-c242a9736568', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 50, 'Plan orders', '', 'task', true, (SELECT id FROM roles WHERE code='PLANNING'), NULL),
  ('e75ca172-43ea-59f4-9bde-49408894bf8b', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 60, 'Update production documents (projects & serial)', '', 'task', true, (SELECT id FROM roles WHERE code='PRODUCTION'), NULL),
  ('9f2c1f4f-93cf-5025-aa2c-b406d176ea1d', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 70, 'Clear up stock', '', 'task', true, (SELECT id FROM roles WHERE code='WAREHOUSE'), NULL),
  ('8a62a0a0-2797-5e79-afda-9fbfa73a7f86', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '28dbca06-fab1-5613-b0c2-df481c05a3e8', 80, 'Follow up on quality', '', 'task', true, (SELECT id FROM roles WHERE code='QUALITY'), NULL),
  ('51911a9e-9c90-566b-b656-43b7fe79a7fe', 'dbe999b6-fcf3-5401-8a57-95c33ea5be3f', 'd99503b9-a032-573c-b1eb-6fa44e60d384', '68c86e15-a528-55eb-b385-f972c92ddda2', 10, 'Review / evaluate implementation', '', 'review', true, (SELECT id FROM roles WHERE code='ENG_MANAGER'), NULL)
ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title, task_type=EXCLUDED.task_type,
  is_mandatory=EXCLUDED.is_mandatory, default_assignee_role_id=EXCLUDED.default_assignee_role_id,
  seq_number=EXCLUDED.seq_number, sla_hours=EXCLUDED.sla_hours;

COMMIT;

-- >>> supabase/seed/40_templates.sql
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

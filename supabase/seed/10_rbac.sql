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

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

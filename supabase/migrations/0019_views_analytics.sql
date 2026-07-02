-- =============================================================================
-- 0019_views_analytics.sql
-- Module 1 / Module 5 & 16: Analytics views powering the dashboard & reports.
-- Views run with the querying user's privileges (security_invoker) so RLS applies.
-- =============================================================================

-- ---- Enriched ECM overview (labels resolved) -------------------------------
CREATE OR REPLACE VIEW vw_ecm_overview
WITH (security_invoker = true) AS
SELECT
  e.id, e.ecm_number, e.title, e.change_type, e.priority, e.risk_level,
  e.cost_impact, e.cost_currency, e.created_date, e.due_date, e.closed_at, e.is_deleted,
  st.code  AS state_code,  st.name  AS state_name,  st.category AS status_category,
  sg.code  AS stage_code,  sg.name  AS stage_name,
  cat.name AS status_label, cat.color AS status_color,
  d.name   AS department, pl.name AS plant, c.name AS customer, sup.name AS supplier,
  ow.full_name AS owner_name, rq.full_name AS requestor_name,
  e.state_entered_at,
  (e.due_date IS NOT NULL AND e.due_date < CURRENT_DATE
     AND st.category NOT IN ('resolved','completed','rejected','cancelled')) AS is_overdue,
  EXTRACT(EPOCH FROM (COALESCE(e.closed_at, now()) - e.created_at))/86400.0 AS age_days
FROM ecm_requests e
LEFT JOIN wf_states st           ON st.id = e.current_state_id
LEFT JOIN wf_stages sg           ON sg.id = e.current_stage_id
LEFT JOIN wf_state_categories cat ON cat.code = e.status_category
LEFT JOIN departments d          ON d.id = e.department_id
LEFT JOIN plants pl              ON pl.id = e.plant_id
LEFT JOIN customers c            ON c.id = e.customer_id
LEFT JOIN suppliers sup          ON sup.id = e.supplier_id
LEFT JOIN profiles ow            ON ow.id = e.owner_id
LEFT JOIN profiles rq            ON rq.id = e.requestor_id;

-- ---- Executive KPI card values (single row) --------------------------------
CREATE OR REPLACE VIEW vw_dashboard_kpis
WITH (security_invoker = true) AS
SELECT
  count(*) FILTER (WHERE NOT is_deleted)                                                          AS total_ecm,
  count(*) FILTER (WHERE NOT is_deleted AND status_category NOT IN ('resolved','completed','rejected','cancelled')) AS open_ecm,
  count(*) FILTER (WHERE NOT is_deleted AND status_category IN ('approval','screening'))          AS pending_approval,
  count(*) FILTER (WHERE NOT is_deleted AND status_category = 'rejected')                         AS rejected,
  count(*) FILTER (WHERE NOT is_deleted AND status_category = 'cancelled')                        AS cancelled,
  count(*) FILTER (WHERE NOT is_deleted AND status_category IN ('resolved','completed'))          AS completed,
  round(avg(EXTRACT(EPOCH FROM (closed_at - created_at))/86400.0)
        FILTER (WHERE closed_at IS NOT NULL), 1)                                                  AS avg_lead_time_days,
  (SELECT round(avg(EXTRACT(EPOCH FROM (decided_at - created_at))/3600.0), 1)
     FROM approval_requests WHERE status IN ('approved','rejected') AND decided_at IS NOT NULL)   AS avg_approval_hours,
  round(100.0 * count(*) FILTER (WHERE status_category IN ('resolved','completed'))
        / NULLIF(count(*) FILTER (WHERE status_category IN ('resolved','completed','rejected','cancelled')), 0), 1) AS implementation_success_rate,
  (SELECT count(*) FROM ecm_tasks WHERE status <> 'done' AND due_date IS NOT NULL AND due_date < CURRENT_DATE) AS overdue_tasks,
  (SELECT count(*) FROM ecm_tasks WHERE status IN ('todo','in_progress','blocked'))               AS open_actions
FROM ecm_requests;

-- ---- Monthly trends (created vs completed) ---------------------------------
CREATE OR REPLACE VIEW vw_monthly_trends
WITH (security_invoker = true) AS
WITH months AS (
  SELECT date_trunc('month', created_at) AS m, count(*) AS created
  FROM ecm_requests WHERE NOT is_deleted GROUP BY 1),
completed AS (
  SELECT date_trunc('month', closed_at) AS m, count(*) AS completed
  FROM ecm_requests WHERE closed_at IS NOT NULL GROUP BY 1)
SELECT COALESCE(mo.m, co.m) AS month,
       COALESCE(mo.created, 0)   AS created,
       COALESCE(co.completed, 0) AS completed
FROM months mo FULL OUTER JOIN completed co ON mo.m = co.m
ORDER BY 1;

-- ---- Requests per department -----------------------------------------------
CREATE OR REPLACE VIEW vw_department_requests
WITH (security_invoker = true) AS
SELECT COALESCE(d.name, 'Unassigned') AS department,
       count(*) FILTER (WHERE NOT e.is_deleted) AS total,
       count(*) FILTER (WHERE e.status_category NOT IN ('resolved','completed','rejected','cancelled') AND NOT e.is_deleted) AS open
FROM ecm_requests e LEFT JOIN departments d ON d.id = e.department_id
GROUP BY 1 ORDER BY 2 DESC;

-- ---- Priority distribution --------------------------------------------------
CREATE OR REPLACE VIEW vw_priority_distribution
WITH (security_invoker = true) AS
SELECT priority, count(*) AS total
FROM ecm_requests WHERE NOT is_deleted GROUP BY priority;

-- ---- Workflow funnel (count by stage, in flow order) -----------------------
CREATE OR REPLACE VIEW vw_workflow_funnel
WITH (security_invoker = true) AS
SELECT sg.code AS stage_code, sg.name AS stage_name, sg.sequence,
       count(e.id) FILTER (WHERE NOT e.is_deleted) AS in_stage
FROM wf_stages sg
LEFT JOIN ecm_requests e ON e.current_stage_id = sg.id
GROUP BY sg.code, sg.name, sg.sequence
ORDER BY sg.sequence;

-- ---- Approval duration by stage --------------------------------------------
CREATE OR REPLACE VIEW vw_approval_duration
WITH (security_invoker = true) AS
SELECT COALESCE(sg.name, 'Unknown') AS stage_name,
       count(*)                                                              AS decisions,
       round(avg(EXTRACT(EPOCH FROM (ar.decided_at - ar.created_at))/3600.0), 1) AS avg_hours
FROM approval_requests ar
LEFT JOIN wf_stages sg ON sg.id = ar.stage_id
WHERE ar.decided_at IS NOT NULL
GROUP BY 1 ORDER BY 3 DESC NULLS LAST;

-- ---- Bottleneck analysis (avg dwell per state vs SLA) ----------------------
CREATE OR REPLACE VIEW vw_bottleneck_analysis
WITH (security_invoker = true) AS
SELECT s.code AS state_code, s.name AS state_name, sg.name AS stage_name, s.sla_hours,
       count(h.id)                                       AS transitions_out,
       round(avg(h.dwell_seconds)/3600.0, 1)             AS avg_dwell_hours,
       round(max(h.dwell_seconds)/3600.0, 1)             AS max_dwell_hours,
       (s.sla_hours IS NOT NULL AND avg(h.dwell_seconds)/3600.0 > s.sla_hours) AS breaches_sla
FROM ecm_state_history h
JOIN wf_states s  ON s.id = h.from_state_id
JOIN wf_stages sg ON sg.id = s.stage_id
GROUP BY s.code, s.name, sg.name, s.sla_hours
ORDER BY avg_dwell_hours DESC NULLS LAST;

-- ---- Workload per user (open tasks) ----------------------------------------
CREATE OR REPLACE VIEW vw_workload_per_user
WITH (security_invoker = true) AS
SELECT p.id AS user_id, p.full_name,
       count(*) FILTER (WHERE t.status IN ('todo','in_progress','blocked')) AS open_tasks,
       count(*) FILTER (WHERE t.status <> 'done' AND t.due_date < CURRENT_DATE) AS overdue_tasks,
       count(*) FILTER (WHERE t.status = 'done')                            AS done_tasks
FROM profiles p LEFT JOIN ecm_tasks t ON t.assignee_id = p.id
GROUP BY p.id, p.full_name
HAVING count(t.id) > 0
ORDER BY open_tasks DESC;

-- ---- Engineer performance (throughput + speed) -----------------------------
CREATE OR REPLACE VIEW vw_engineer_performance
WITH (security_invoker = true) AS
SELECT p.id AS user_id, p.full_name,
       count(*) FILTER (WHERE t.status = 'done')                            AS completed_tasks,
       round(avg(EXTRACT(EPOCH FROM (t.completed_at - t.started_at))/3600.0)
             FILTER (WHERE t.completed_at IS NOT NULL AND t.started_at IS NOT NULL), 1) AS avg_completion_hours,
       count(*) FILTER (WHERE t.status <> 'done' AND t.due_date < CURRENT_DATE) AS overdue_tasks
FROM profiles p JOIN ecm_tasks t ON t.assignee_id = p.id
GROUP BY p.id, p.full_name ORDER BY completed_tasks DESC;

-- ---- CR-board performance (throughput + speed of board decisions) ----------
CREATE OR REPLACE VIEW vw_crboard_performance
WITH (security_invoker = true) AS
SELECT date_trunc('month', aa.decision_at) AS month,
       count(*)                            AS decisions,
       count(*) FILTER (WHERE aa.decision = 'approved') AS approved,
       count(*) FILTER (WHERE aa.decision = 'rejected') AS rejected,
       round(avg(EXTRACT(EPOCH FROM (aa.decision_at - ar.created_at))/3600.0), 1) AS avg_decision_hours
FROM approval_assignments aa
JOIN approval_requests ar ON ar.id = aa.approval_request_id
WHERE aa.decision_at IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- ---- Cycle time per completed ECM ------------------------------------------
CREATE OR REPLACE VIEW vw_cycle_time
WITH (security_invoker = true) AS
SELECT e.ecm_number, e.title,
       e.created_at, e.closed_at,
       round(EXTRACT(EPOCH FROM (e.closed_at - e.created_at))/86400.0, 1) AS cycle_days
FROM ecm_requests e
WHERE e.closed_at IS NOT NULL
ORDER BY e.closed_at DESC;

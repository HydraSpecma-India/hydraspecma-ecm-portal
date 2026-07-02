-- =============================================================================
-- 0004_workflow_engine.sql
-- Module 1 / Module 6 foundation: DATA-DRIVEN workflow engine.
-- The change process lives entirely in these tables (imported from ECM Flow.xlsx
-- via supabase/seed/30_workflow.sql). Nothing about the flow is hardcoded.
-- =============================================================================

-- ---- Workflow definitions (versioned) --------------------------------------
CREATE TABLE IF NOT EXISTS wf_workflows (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            citext NOT NULL,
  name            text   NOT NULL,
  version         int    NOT NULL DEFAULT 1,
  description     text,
  source_document text,                                   -- provenance, e.g. 'ECM Flow.xlsx'
  is_active       boolean NOT NULL DEFAULT true,
  effective_from  date   NOT NULL DEFAULT CURRENT_DATE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (code, version)
);
COMMENT ON TABLE wf_workflows IS 'Versioned workflow definitions. Multiple versions may coexist; one active per code.';

-- ---- State categories (editable lookup; drives colours/semantics) ----------
CREATE TABLE IF NOT EXISTS wf_state_categories (
  code                citext PRIMARY KEY,
  name                text NOT NULL,
  description         text,
  is_terminal_default boolean NOT NULL DEFAULT false,
  color               text,
  sort_order          int NOT NULL DEFAULT 100
);
COMMENT ON TABLE wf_state_categories IS 'Semantic buckets for states (draft, approval, hold, rejected...). Covers the spec status set.';

INSERT INTO wf_state_categories (code, name, description, is_terminal_default, color, sort_order) VALUES
  ('draft',       'Draft',        'Being prepared by the requestor',           false, '#94A3B8', 10),
  ('screening',   'Screening',    'Under initial review / go-ahead decision',  false, '#F59E0B', 20),
  ('in_progress', 'In Progress',  'Actively being worked',                     false, '#0EA5E9', 30),
  ('review',      'Review',       'Under review / evaluation',                 false, '#6366F1', 35),
  ('approval',    'Approval',     'Awaiting a board / gate decision',          false, '#8B5CF6', 40),
  ('accepted',    'Accepted',     'Accepted; progressing to next stage',       false, '#14B8A6', 50),
  ('hold',        'Hold',         'Temporarily paused',                        false, '#FB923C', 60),
  ('backlog',     'Backlog',      'Deferred, awaiting opportunity',            false, '#64748B', 70),
  ('returned',    'Returned',     'Sent back for rework',                      false, '#EAB308', 80),
  ('support',     'Support',      'Awaiting support / external input',         false, '#06B6D4', 85),
  ('rejected',    'Rejected',     'Rejected — no action',                      true,  '#EF4444', 90),
  ('cancelled',   'Cancelled',    'Cancelled — solved elsewhere',              true,  '#F43F5E', 100),
  ('resolved',    'Resolved',     'Successfully implemented and closed',       true,  '#22C55E', 110),
  ('completed',   'Completed',    'Completed',                                 true,  '#16A34A', 120)
ON CONFLICT (code) DO NOTHING;

-- ---- Stages (major phases of a workflow) -----------------------------------
CREATE TABLE IF NOT EXISTS wf_stages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  code        citext NOT NULL,
  name        text   NOT NULL,
  sequence    int    NOT NULL DEFAULT 0,
  entity_type text   NOT NULL DEFAULT 'ECM' CHECK (entity_type IN ('ECM','ECR','ECO')),
  color       text,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, code)
);
CREATE INDEX IF NOT EXISTS idx_wf_stages_workflow ON wf_stages (workflow_id, sequence);

-- ---- States (nodes of the state machine) -----------------------------------
CREATE TABLE IF NOT EXISTS wf_states (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  stage_id    uuid NOT NULL REFERENCES wf_stages(id)    ON DELETE CASCADE,
  code        citext NOT NULL,
  name        text   NOT NULL,
  sequence    int    NOT NULL DEFAULT 0,
  category    citext NOT NULL REFERENCES wf_state_categories(code),
  is_initial  boolean NOT NULL DEFAULT false,
  is_terminal boolean NOT NULL DEFAULT false,
  sla_hours   int,                                        -- target dwell time; feeds overdue/bottleneck analytics
  color       text,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, code)
);
CREATE INDEX IF NOT EXISTS idx_wf_states_stage    ON wf_states (stage_id, sequence);
CREATE INDEX IF NOT EXISTS idx_wf_states_category ON wf_states (category);
-- At most one initial state per stage.
CREATE UNIQUE INDEX IF NOT EXISTS uq_wf_states_initial_per_stage ON wf_states (stage_id) WHERE is_initial;

-- ---- Transitions (edges; who can move what, and side effects) --------------
CREATE TABLE IF NOT EXISTS wf_transitions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id         uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  from_state_id       uuid REFERENCES wf_states(id) ON DELETE CASCADE,   -- NULL = creation/entry edge
  to_state_id         uuid NOT NULL REFERENCES wf_states(id) ON DELETE CASCADE,
  action_code         citext NOT NULL,
  action_label        text   NOT NULL,
  required_permission citext,                              -- checked by fn_has_permission()
  requires_comment    boolean NOT NULL DEFAULT false,
  requires_approval   boolean NOT NULL DEFAULT false,
  side_effect         text CHECK (side_effect IN ('create_ecr','create_eco','close_ecm')),
  guard_expression    text,                                -- optional SQL boolean guard (evaluated by engine)
  sort_order          int NOT NULL DEFAULT 0,
  is_active           boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_id, from_state_id, action_code, to_state_id)
);
CREATE INDEX IF NOT EXISTS idx_wf_transitions_from ON wf_transitions (from_state_id, sort_order);
CREATE INDEX IF NOT EXISTS idx_wf_transitions_to   ON wf_transitions (to_state_id);

-- ---- Task templates (checklist per state; seeded with sequence numbers) ----
CREATE TABLE IF NOT EXISTS wf_task_templates (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id              uuid NOT NULL REFERENCES wf_workflows(id) ON DELETE CASCADE,
  stage_id                 uuid NOT NULL REFERENCES wf_stages(id)    ON DELETE CASCADE,
  state_id                 uuid NOT NULL REFERENCES wf_states(id)    ON DELETE CASCADE,
  seq_number               int  NOT NULL DEFAULT 0,
  title                    text NOT NULL,
  description              text,
  task_type                text NOT NULL DEFAULT 'task'
                             CHECK (task_type IN ('task','decision','review','meeting','approval','implementation','notification','integration')),
  is_mandatory             boolean NOT NULL DEFAULT true,
  default_assignee_role_id uuid REFERENCES roles(id) ON DELETE SET NULL,
  sla_hours                int,
  checklist                jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wf_task_templates_state ON wf_task_templates (state_id, seq_number);
CREATE INDEX IF NOT EXISTS idx_wf_task_templates_wf    ON wf_task_templates (workflow_id, stage_id);

-- ---- updated_at trigger -----------------------------------------------------
CREATE TRIGGER trg_wf_workflows_updated BEFORE UPDATE ON wf_workflows FOR EACH ROW EXECUTE FUNCTION set_updated_at();

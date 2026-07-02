-- =============================================================================
-- 0007_tasks.sql
-- Module 1 / Module 8: Task management — Kanban / List / Calendar / Gantt.
-- Tasks are instantiated from wf_task_templates on state entry (see 0017 engine).
-- =============================================================================

CREATE TABLE IF NOT EXISTS ecm_tasks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_request_id  uuid NOT NULL REFERENCES ecm_requests(id) ON DELETE CASCADE,
  entity_type     entity_type NOT NULL DEFAULT 'ecm',        -- ecm | ecr | eco this task belongs to
  entity_id       uuid NOT NULL,
  template_id     uuid REFERENCES wf_task_templates(id) ON DELETE SET NULL,  -- NULL = ad-hoc
  stage_id        uuid REFERENCES wf_stages(id) ON DELETE SET NULL,
  state_id        uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  parent_task_id  uuid REFERENCES ecm_tasks(id) ON DELETE CASCADE,           -- subtasks
  seq_number      int  NOT NULL DEFAULT 0,
  title           text NOT NULL,
  description     text,
  task_type       text NOT NULL DEFAULT 'task'
                    CHECK (task_type IN ('task','decision','review','meeting','approval','implementation','notification','integration')),
  status          task_status NOT NULL DEFAULT 'todo',
  progress_pct    int NOT NULL DEFAULT 0 CHECK (progress_pct BETWEEN 0 AND 100),
  priority        priority_level NOT NULL DEFAULT 'medium',
  assignee_id     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  assignee_role_id uuid REFERENCES roles(id)   ON DELETE SET NULL,
  is_mandatory    boolean NOT NULL DEFAULT true,
  sort_order      int NOT NULL DEFAULT 0,                    -- board / gantt ordering
  start_date      date,
  due_date        date,
  started_at      timestamptz,
  completed_at    timestamptz,
  completed_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  checklist       jsonb NOT NULL DEFAULT '[]'::jsonb,        -- lightweight inline checklist mirror
  created_by      uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ecm_tasks IS 'Work items for a change record; support Kanban, list, calendar, timeline and Gantt views.';
CREATE INDEX IF NOT EXISTS idx_tasks_ecm       ON ecm_tasks (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_tasks_entity    ON ecm_tasks (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee  ON ecm_tasks (assignee_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status    ON ecm_tasks (status);
CREATE INDEX IF NOT EXISTS idx_tasks_state     ON ecm_tasks (state_id);
CREATE INDEX IF NOT EXISTS idx_tasks_due       ON ecm_tasks (due_date) WHERE status <> 'done';
CREATE INDEX IF NOT EXISTS idx_tasks_parent    ON ecm_tasks (parent_task_id);

-- ---- Task dependencies (Gantt links) ---------------------------------------
CREATE TABLE IF NOT EXISTS ecm_task_dependencies (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id           uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  depends_on_task_id uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  dependency_type   text NOT NULL DEFAULT 'finish_to_start'
                      CHECK (dependency_type IN ('finish_to_start','start_to_start','finish_to_finish','start_to_finish')),
  lag_hours         int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, depends_on_task_id),
  CHECK (task_id <> depends_on_task_id)
);
CREATE INDEX IF NOT EXISTS idx_task_deps_task    ON ecm_task_dependencies (task_id);
CREATE INDEX IF NOT EXISTS idx_task_deps_depends ON ecm_task_dependencies (depends_on_task_id);

-- ---- Normalized checklist items (per task) ---------------------------------
CREATE TABLE IF NOT EXISTS task_checklist_items (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id    uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  position   int  NOT NULL DEFAULT 0,
  label      text NOT NULL,
  is_done    boolean NOT NULL DEFAULT false,
  done_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  done_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_checklist_task ON task_checklist_items (task_id, position);

-- ---- Reminders --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_reminders (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id    uuid NOT NULL REFERENCES ecm_tasks(id) ON DELETE CASCADE,
  remind_at  timestamptz NOT NULL,
  channel    notification_channel NOT NULL DEFAULT 'in_app',
  is_sent    boolean NOT NULL DEFAULT false,
  sent_at    timestamptz,
  created_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_reminders_due ON task_reminders (remind_at) WHERE NOT is_sent;

CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON ecm_tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();

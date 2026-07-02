-- =============================================================================
-- 0010_approvals.sql
-- Module 1 / Module 10: Approval workflow + email approval (Approve/Reject/Return).
-- Approvals gate wf_transitions where requires_approval = true.
-- =============================================================================

CREATE TABLE IF NOT EXISTS approval_requests (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type    entity_type NOT NULL,
  entity_id      uuid NOT NULL,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  stage_id       uuid REFERENCES wf_stages(id) ON DELETE SET NULL,
  state_id       uuid REFERENCES wf_states(id) ON DELETE SET NULL,
  transition_id  uuid REFERENCES wf_transitions(id) ON DELETE SET NULL,
  title          text NOT NULL,
  description    text,
  policy         approval_policy NOT NULL DEFAULT 'any',
  quorum         int,                                          -- required approvals when policy = 'quorum'
  status         approval_status NOT NULL DEFAULT 'pending',
  requested_by   uuid REFERENCES profiles(id) ON DELETE SET NULL,
  due_at         timestamptz,
  decided_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE approval_requests IS 'A gate awaiting one or more approvers before a transition may fire.';
CREATE INDEX IF NOT EXISTS idx_approvals_entity ON approval_requests (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_approvals_ecm    ON approval_requests (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON approval_requests (status);

CREATE TABLE IF NOT EXISTS approval_assignments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_request_id uuid NOT NULL REFERENCES approval_requests(id) ON DELETE CASCADE,
  sequence            int NOT NULL DEFAULT 1,                  -- ordering for sequential policy
  approver_id         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  approver_role_id    uuid REFERENCES roles(id) ON DELETE SET NULL,
  decision            approval_decision NOT NULL DEFAULT 'pending',
  decision_at         timestamptz,
  comment             text,
  delegated_to        uuid REFERENCES profiles(id) ON DELETE SET NULL,
  escalated_to        uuid REFERENCES profiles(id) ON DELETE SET NULL,
  notified_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (approver_id IS NOT NULL OR approver_role_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_appr_assign_request  ON approval_assignments (approval_request_id, sequence);
CREATE INDEX IF NOT EXISTS idx_appr_assign_approver ON approval_assignments (approver_id);
CREATE INDEX IF NOT EXISTS idx_appr_assign_pending  ON approval_assignments (decision) WHERE decision = 'pending';

-- ---- Email approval tokens (single-use, signed, expiring) ------------------
CREATE TABLE IF NOT EXISTS approval_email_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES approval_assignments(id) ON DELETE CASCADE,
  token         text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  action_scope  text[] NOT NULL DEFAULT ARRAY['approve','reject','return','comment'],
  expires_at    timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  used_at       timestamptz,
  used_action   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_appr_tokens_assignment ON approval_email_tokens (assignment_id);

CREATE TRIGGER trg_approvals_updated BEFORE UPDATE ON approval_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- 0014_ai_history.sql
-- Module 1 / Module 15: AI Assistant history — conversations, messages, insights.
-- =============================================================================

CREATE TABLE IF NOT EXISTS ai_conversations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE SET NULL,
  title          text,
  context        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_conv_user ON ai_conversations (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_conv_ecm  ON ai_conversations (ecm_request_id);

CREATE TABLE IF NOT EXISTS ai_messages (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('system','user','assistant','tool')),
  content         text NOT NULL,
  tokens          int,
  model           text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages (conversation_id, created_at);

CREATE TABLE IF NOT EXISTS ai_insights (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  entity_type    entity_type NOT NULL DEFAULT 'ecm',
  entity_id      uuid,
  insight_type   text NOT NULL
                   CHECK (insight_type IN ('summary','missing_info','suggested_docs','suggested_approvers',
                          'risk','priority','lead_time','similar','delay_prediction','tasks',
                          'exec_summary','meeting_minutes')),
  summary        text,
  content        jsonb NOT NULL DEFAULT '{}'::jsonb,
  model          text,
  confidence     numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),
  created_by     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai_insights IS 'Persisted AI outputs (summaries, risk, suggested approvers/docs, predictions).';
CREATE INDEX IF NOT EXISTS idx_ai_insights_ecm  ON ai_insights (ecm_request_id, insight_type);

CREATE TRIGGER trg_ai_conv_updated BEFORE UPDATE ON ai_conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =============================================================================
-- 0013_integration_api.sql
-- Module 1 / Module 12: Integration plumbing — endpoints, API logs, sync state,
-- and a retryable D365 F&O outbound queue.
-- =============================================================================

CREATE TABLE IF NOT EXISTS integration_endpoints (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  system     text NOT NULL CHECK (system IN ('D365FO','GRAPH','POWERBI','SUPABASE','CUSTOM')),
  name       text NOT NULL,
  base_url   text,
  odata_path text,
  auth_type  text NOT NULL DEFAULT 'oauth2_client_credentials'
               CHECK (auth_type IN ('oauth2_client_credentials','oauth2_auth_code','api_key','none')),
  config     jsonb NOT NULL DEFAULT '{}'::jsonb,             -- non-secret settings; secrets live in env
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (system, name)
);
COMMENT ON TABLE integration_endpoints IS 'Configured external systems (D365 F&O, MS Graph, Power BI). Secrets are never stored here.';

CREATE TABLE IF NOT EXISTS api_logs (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  system          text NOT NULL,
  endpoint        text NOT NULL,
  method          text NOT NULL DEFAULT 'GET',
  direction       text NOT NULL DEFAULT 'outbound' CHECK (direction IN ('outbound','inbound')),
  entity_type     entity_type,
  entity_id       uuid,
  correlation_id  text,
  request_headers jsonb,
  request_payload jsonb,
  response_status int,
  response_payload jsonb,
  is_success      boolean NOT NULL DEFAULT false,
  error_message   text,
  duration_ms     int,
  retry_count     int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE api_logs IS 'Full request/response log for every integration call (Admin > API Logs).';
CREATE INDEX IF NOT EXISTS idx_api_logs_system  ON api_logs (system, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_api_logs_success ON api_logs (is_success);
CREATE INDEX IF NOT EXISTS idx_api_logs_corr    ON api_logs (correlation_id);

CREATE TABLE IF NOT EXISTS integration_sync_state (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  system         text NOT NULL,
  entity_type    entity_type NOT NULL,
  external_id    text NOT NULL,
  internal_id    uuid,
  direction      text NOT NULL DEFAULT 'inbound' CHECK (direction IN ('inbound','outbound','bidirectional')),
  last_synced_at timestamptz,
  sync_status    sync_status NOT NULL DEFAULT 'pending',
  checksum       text,
  message        text,
  UNIQUE (system, entity_type, external_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_state_internal ON integration_sync_state (internal_id);

CREATE TABLE IF NOT EXISTS d365_sync_queue (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation      text NOT NULL
                   CHECK (operation IN ('create_ecr','create_eco','update_item','update_bom',
                                        'update_product_version','attach_ecm','link_record','sync_status')),
  entity_type    entity_type,
  entity_id      uuid,
  ecm_request_id uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  status         sync_status NOT NULL DEFAULT 'pending',
  attempts       int NOT NULL DEFAULT 0,
  max_attempts   int NOT NULL DEFAULT 5,
  next_retry_at  timestamptz NOT NULL DEFAULT now(),
  last_error     text,
  correlation_id text,
  processed_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE d365_sync_queue IS 'Outbound operations to D365 F&O with retry/backoff; drained by an Edge Function (Module 12).';
CREATE INDEX IF NOT EXISTS idx_d365_queue_pending ON d365_sync_queue (status, next_retry_at) WHERE status IN ('pending','failed');

CREATE TRIGGER trg_endpoints_updated  BEFORE UPDATE ON integration_endpoints FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_d365_queue_updated BEFORE UPDATE ON d365_sync_queue        FOR EACH ROW EXECUTE FUNCTION set_updated_at();

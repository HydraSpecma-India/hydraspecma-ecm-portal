-- =============================================================================
-- 0009_comments_attachments.sql
-- Module 1: Collaboration — threaded comments with @mentions, generic attachments.
-- Polymorphic (entity_type/entity_id) so any record can be discussed / annotated.
-- =============================================================================

CREATE TABLE IF NOT EXISTS comments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type       entity_type NOT NULL,
  entity_id         uuid NOT NULL,
  parent_comment_id uuid REFERENCES comments(id) ON DELETE CASCADE,
  author_id         uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  body              text NOT NULL,
  mentions          uuid[] NOT NULL DEFAULT '{}',            -- profile ids @-mentioned
  is_internal       boolean NOT NULL DEFAULT false,          -- hidden from external/viewer roles
  is_deleted        boolean NOT NULL DEFAULT false,
  edited_at         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE comments IS 'Threaded discussion attached to any entity; mentions drive notifications.';
CREATE INDEX IF NOT EXISTS idx_comments_entity   ON comments (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent   ON comments (parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_comments_author   ON comments (author_id);
CREATE INDEX IF NOT EXISTS idx_comments_mentions ON comments USING gin (mentions);

CREATE TABLE IF NOT EXISTS attachments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type    entity_type NOT NULL,
  entity_id      uuid NOT NULL,
  name           text NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'ecm-attachments',
  storage_path   text NOT NULL,
  file_size      bigint,
  mime_type      text,
  uploaded_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_attachments_entity ON attachments (entity_type, entity_id);

CREATE TRIGGER trg_comments_updated BEFORE UPDATE ON comments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

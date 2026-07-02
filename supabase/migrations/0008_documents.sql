-- =============================================================================
-- 0008_documents.sql
-- Module 1 / Module 9: Document management — versioning, check-in/out, e-signatures.
-- Binary content lives in Supabase Storage; these tables hold metadata + pointers.
-- =============================================================================

CREATE TABLE IF NOT EXISTS document_categories (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code               citext NOT NULL UNIQUE,
  name               text NOT NULL,
  description        text,
  allowed_extensions text[] NOT NULL DEFAULT '{}',
  requires_approval  boolean NOT NULL DEFAULT false,
  retention_months   int,
  created_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE document_categories IS 'Engineering drawings, CAD, specs, work instructions, etc.';

CREATE TABLE IF NOT EXISTS documents (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_number         citext UNIQUE,
  entity_type        entity_type NOT NULL DEFAULT 'ecm',
  entity_id          uuid NOT NULL,
  ecm_request_id     uuid REFERENCES ecm_requests(id) ON DELETE CASCADE,   -- denormalized rollup
  category_id        uuid REFERENCES document_categories(id) ON DELETE SET NULL,
  name               text NOT NULL,
  description        text,
  doc_type           text NOT NULL DEFAULT 'other'
                       CHECK (doc_type IN ('drawing','cad','pdf','word','excel','image','specification','work_instruction','other')),
  status             document_status NOT NULL DEFAULT 'draft',
  current_version_id uuid,                                    -- FK added after document_versions
  is_checked_out     boolean NOT NULL DEFAULT false,
  checked_out_by     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  checked_out_at     timestamptz,
  created_by         uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE documents IS 'Controlled documents attached to a change record; one row per logical document.';
CREATE INDEX IF NOT EXISTS idx_documents_entity ON documents (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_documents_ecm    ON documents (ecm_request_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents (status);

CREATE TABLE IF NOT EXISTS document_versions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id    uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  version_no     int  NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'ecm-documents',
  storage_path   text NOT NULL,
  file_name      text,
  file_size      bigint,
  mime_type      text,
  checksum       text,                                      -- sha256 for integrity
  status         document_status NOT NULL DEFAULT 'draft',
  change_note    text,
  is_current     boolean NOT NULL DEFAULT false,
  uploaded_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  uploaded_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, version_no)
);
CREATE INDEX IF NOT EXISTS idx_doc_versions_document ON document_versions (document_id, version_no DESC);
-- exactly one current version per document
CREATE UNIQUE INDEX IF NOT EXISTS uq_doc_versions_current ON document_versions (document_id) WHERE is_current;

ALTER TABLE documents
  ADD CONSTRAINT fk_documents_current_version
  FOREIGN KEY (current_version_id) REFERENCES document_versions(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS document_signatures (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_version_id uuid NOT NULL REFERENCES document_versions(id) ON DELETE CASCADE,
  signer_id           uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  meaning             signature_meaning NOT NULL DEFAULT 'approved',
  signature_hash      text NOT NULL,                        -- HMAC over version checksum + signer + timestamp
  method              text NOT NULL DEFAULT 'password' CHECK (method IN ('password','azure_ad','otp')),
  ip_address          inet,
  comment             text,
  signed_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_version_id, signer_id, meaning)
);
COMMENT ON TABLE document_signatures IS '21 CFR Part 11-style e-signatures bound to a specific document version.';
CREATE INDEX IF NOT EXISTS idx_signatures_version ON document_signatures (document_version_id);

CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

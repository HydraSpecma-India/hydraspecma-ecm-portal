-- =============================================================================
-- 0021_storage_buckets.sql
-- Module 1 / Module 9: Supabase Storage buckets + object policies.
-- Guarded so it is a no-op on a plain PostgreSQL instance (no storage schema).
-- =============================================================================
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NULL THEN
    RAISE NOTICE 'storage schema not present — skipping bucket setup (non-Supabase environment).';
    RETURN;
  END IF;

  -- Buckets (private by default; avatars public for direct rendering).
  INSERT INTO storage.buckets (id, name, public, file_size_limit) VALUES
    ('ecm-documents',   'ecm-documents',   false, 262144000),   -- 250 MB (CAD/drawings)
    ('ecm-attachments', 'ecm-attachments', false, 52428800),    -- 50 MB
    ('ecm-exports',     'ecm-exports',     false, 104857600),   -- 100 MB (reports/packages)
    ('ecm-avatars',     'ecm-avatars',     true,  5242880)      -- 5 MB
  ON CONFLICT (id) DO NOTHING;

  -- Object policies: authenticated users operate within the ECM buckets.
  EXECUTE $p$
    CREATE POLICY "ecm_objects_read" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_insert" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_update" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars'))
    WITH CHECK (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
  EXECUTE $p$
    CREATE POLICY "ecm_objects_delete" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id IN ('ecm-documents','ecm-attachments','ecm-exports','ecm-avatars')) $p$;
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE 'storage object policies already exist — skipping.';
END $$;

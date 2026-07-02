-- =============================================================================
-- 0001_extensions_and_types.sql
-- HydraSpecma ECM Portal — Module 1: Database Design
-- Extensions, enumerated types (structural), and generic utility functions.
-- Target: PostgreSQL 15 / Supabase.
-- =============================================================================

-- ---- Extensions -------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;      -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS citext;        -- case-insensitive email/codes
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- fuzzy / global search
CREATE EXTENSION IF NOT EXISTS unaccent;      -- accent-insensitive search
CREATE EXTENSION IF NOT EXISTS btree_gin;     -- composite GIN indexes

-- ---- Enumerated types (fixed, structural — NOT workflow content) ------------
-- Workflow states/categories are DATA (wf_* tables), never enums.
DO $$ BEGIN
  CREATE TYPE priority_level  AS ENUM ('low','medium','high','critical');            EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE risk_level      AS ENUM ('low','medium','high','severe');              EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE change_source   AS ENUM ('manual','d365','ai','email','import','api'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE entity_type     AS ENUM ('ecm','ecr','eco','task','document','approval','comment','item','bom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE task_status      AS ENUM ('todo','in_progress','blocked','done','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_decision AS ENUM ('pending','approved','rejected','returned','delegated','escalated','abstained'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_status  AS ENUM ('pending','in_progress','approved','rejected','returned','cancelled','escalated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE approval_policy  AS ENUM ('any','all','quorum','sequential'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE notification_channel AS ENUM ('in_app','email','teams','sms'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE document_status  AS ENUM ('draft','in_review','approved','released','obsolete','rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE signature_meaning AS ENUM ('authored','reviewed','approved','released','witnessed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE sync_status      AS ENUM ('pending','processing','success','failed','skipped'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE audit_action     AS ENUM ('INSERT','UPDATE','DELETE'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---- Generic utility functions ---------------------------------------------

-- Maintains updated_at on any table that carries the column.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;
COMMENT ON FUNCTION set_updated_at() IS 'BEFORE UPDATE trigger: stamps updated_at = now().';

-- Returns the current authenticated user id (Supabase auth.uid()), or a
-- request-scoped override set via SET LOCAL app.current_user_id (used by API/edge fns).
CREATE OR REPLACE FUNCTION app_current_user_id()
RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE uid uuid;
BEGIN
  BEGIN uid := auth.uid(); EXCEPTION WHEN undefined_function THEN uid := NULL; END;
  IF uid IS NULL THEN
    uid := NULLIF(current_setting('app.current_user_id', true), '')::uuid;
  END IF;
  RETURN uid;
END $$;
COMMENT ON FUNCTION app_current_user_id() IS 'Resolves the acting user id from Supabase auth.uid() or app.current_user_id GUC.';

-- Request context getters (populated by the app layer via set_config for the audit trail).
CREATE OR REPLACE FUNCTION app_context(key text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.' || key, true), '');
$$;
COMMENT ON FUNCTION app_context(text) IS 'Reads request-scoped context (ip, user_agent, browser, device, session_id, request_id) for auditing.';

-- Slugify helper for codes / search keys.
CREATE OR REPLACE FUNCTION app_slugify(txt text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT trim(both '-' from regexp_replace(lower(unaccent(coalesce(txt,''))), '[^a-z0-9]+', '-', 'g'));
$$;

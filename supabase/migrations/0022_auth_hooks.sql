-- =============================================================================
-- 0022_auth_hooks.sql
-- Module 2: Supabase Auth integration.
--   * Auto-provision a profile row when an auth user is created.
--   * Bootstrap: the very first user becomes SUPER_ADMIN; everyone else VIEWER.
--   * Admin helper to (re)assign a role by email.
-- Guarded so this file is a no-op on a plain PostgreSQL instance (no auth schema).
-- =============================================================================

-- ---- Assign a role to a user by email (admin/service use) ------------------
CREATE OR REPLACE FUNCTION fn_grant_role(p_email citext, p_role citext, p_plant uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_user uuid; v_role uuid;
BEGIN
  SELECT id INTO v_user FROM profiles WHERE email = p_email;
  IF v_user IS NULL THEN RAISE EXCEPTION 'No profile for email %', p_email; END IF;
  SELECT id INTO v_role FROM roles WHERE code = p_role;
  IF v_role IS NULL THEN RAISE EXCEPTION 'No role %', p_role; END IF;
  INSERT INTO user_roles (user_id, role_id, plant_id, assigned_by)
  VALUES (v_user, v_role, p_plant, app_current_user_id())
  ON CONFLICT (user_id, role_id, plant_id) DO NOTHING;
END $$;
COMMENT ON FUNCTION fn_grant_role(citext, citext, uuid) IS 'Assigns a role to a user by email; used by the bootstrap-admin Edge Function and Admin Panel.';

-- ---- New-user handler: create profile + assign default/bootstrap role ------
CREATE OR REPLACE FUNCTION fn_handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_first boolean;
  v_role_code citext;
  v_full_name text;
BEGIN
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name',
                          NEW.raw_user_meta_data->>'name',
                          split_part(NEW.email, '@', 1));

  INSERT INTO profiles (id, email, full_name, avatar_url, azure_ad_object_id)
  VALUES (
    NEW.id,
    NEW.email,
    v_full_name,
    NEW.raw_user_meta_data->>'avatar_url',
    COALESCE(NEW.raw_user_meta_data->>'provider_id', NEW.raw_user_meta_data->>'sub')
  )
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

  -- Bootstrap: first ever user gets SUPER_ADMIN; subsequent users get VIEWER.
  SELECT NOT EXISTS (
    SELECT 1 FROM user_roles ur JOIN roles r ON r.id = ur.role_id WHERE r.code = 'SUPER_ADMIN'
  ) INTO v_is_first;
  v_role_code := CASE WHEN v_is_first THEN 'SUPER_ADMIN' ELSE 'VIEWER' END;

  INSERT INTO user_roles (user_id, role_id)
  SELECT NEW.id, r.id FROM roles r WHERE r.code = v_role_code
  ON CONFLICT (user_id, role_id, plant_id) DO NOTHING;

  RETURN NEW;
END $$;
COMMENT ON FUNCTION fn_handle_new_user() IS 'AFTER INSERT on auth.users: provisions profile and default role (first user = Super Admin).';

-- ---- Wire the trigger onto auth.users (Supabase only) ----------------------
DO $$
BEGIN
  IF to_regclass('auth.users') IS NULL THEN
    RAISE NOTICE 'auth.users not present — skipping auth trigger (non-Supabase environment).';
    RETURN;
  END IF;
  DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
  CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION fn_handle_new_user();
END $$;

-- Keep profiles.last_login_at fresh from a lightweight RPC the client calls post-login.
CREATE OR REPLACE FUNCTION fn_touch_last_login()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE profiles SET last_login_at = now() WHERE id = app_current_user_id();
$$;

-- Convenience RPC: the signed-in user's profile + roles + permissions (for the app bootstrap).
CREATE OR REPLACE FUNCTION fn_me()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT jsonb_build_object(
    'profile', to_jsonb(p),
    'roles',       COALESCE((SELECT jsonb_agg(r.code) FROM user_roles ur JOIN roles r ON r.id=ur.role_id WHERE ur.user_id = p.id), '[]'::jsonb),
    'permissions', COALESCE((SELECT jsonb_agg(DISTINCT pm.code)
                             FROM user_roles ur
                             JOIN role_permissions rp ON rp.role_id = ur.role_id
                             JOIN permissions pm ON pm.id = rp.permission_id
                             WHERE ur.user_id = p.id), '[]'::jsonb)
  )
  FROM profiles p WHERE p.id = app_current_user_id();
$$;
COMMENT ON FUNCTION fn_me() IS 'Returns the current user profile, role codes and permission codes as JSON for client bootstrap.';

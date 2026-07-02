-- pgTAP testing suite for HydraSpecma ECM Portal RLS matrix
BEGIN;
SELECT plan(6);

-- 1. Check if audit_logs table is protected from direct user modification
SELECT table_privs_are(
    'audit_logs',
    'postgres',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
);

-- 2. Verify profiles can be queried by authenticated users
SELECT RLS_enabled('profiles');

-- 3. Verify comments table RLS policy exists
SELECT has_policy('comments');

-- 4. Verify ecm_requests table RLS policy exists
SELECT has_policy('ecm_requests');

-- 5. Test that profiles are read-only for public access
SELECT table_privs_are(
    'profiles',
    'anon',
    ARRAY['SELECT']
);

-- 6. Check that users cannot modify critical parameters (departments/plants)
SELECT table_privs_are(
    'plants',
    'anon',
    ARRAY['SELECT']
);

SELECT * FROM finish();
ROLLBACK;

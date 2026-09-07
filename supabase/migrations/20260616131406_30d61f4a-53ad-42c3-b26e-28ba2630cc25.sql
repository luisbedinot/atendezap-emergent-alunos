
-- =====================================================================
-- SECURITY HARDENING
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Helper: check role within a company (SECURITY DEFINER, used by RLS)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_company_role(_company_id uuid, _roles text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.company_user
    WHERE company_id = _company_id
      AND user_id = auth.uid()
      AND ativo = true
      AND role::text = ANY (_roles)
  );
$$;
REVOKE EXECUTE ON FUNCTION public.has_company_role(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_company_role(uuid, text[]) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2) Prevent self privilege escalation in company_user
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS company_user_update ON public.company_user;
CREATE POLICY company_user_update ON public.company_user
FOR UPDATE TO authenticated
USING (
  public.is_super_admin()
  OR public.has_company_role(company_id, ARRAY['owner','admin'])
)
WITH CHECK (
  public.is_super_admin()
  OR public.has_company_role(company_id, ARRAY['owner','admin'])
);

DROP POLICY IF EXISTS company_user_insert ON public.company_user;
CREATE POLICY company_user_insert ON public.company_user
FOR INSERT TO authenticated
WITH CHECK (
  public.is_super_admin()
  OR public.has_company_role(company_id, ARRAY['owner','admin'])
  OR (
    -- Allow the original company creator to bootstrap themselves as owner
    user_id = auth.uid()
    AND role = 'owner'::tenant_role
    AND EXISTS (
      SELECT 1 FROM public.company c
      WHERE c.id = company_user.company_id
        AND c.created_by = auth.uid()
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.company_user existing
      WHERE existing.company_id = company_user.company_id
    )
  )
);

-- ---------------------------------------------------------------------
-- 3) app_config: explicit super-admin-only write/read policies
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS app_config_select ON public.app_config;
DROP POLICY IF EXISTS app_config_insert ON public.app_config;
DROP POLICY IF EXISTS app_config_update ON public.app_config;
DROP POLICY IF EXISTS app_config_delete ON public.app_config;

CREATE POLICY app_config_select ON public.app_config
FOR SELECT TO authenticated USING (public.is_super_admin());

CREATE POLICY app_config_insert ON public.app_config
FOR INSERT TO authenticated WITH CHECK (public.is_super_admin());

CREATE POLICY app_config_update ON public.app_config
FOR UPDATE TO authenticated
USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());

CREATE POLICY app_config_delete ON public.app_config
FOR DELETE TO authenticated USING (public.is_super_admin());

REVOKE ALL ON public.app_config FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_config TO authenticated;
GRANT ALL ON public.app_config TO service_role;

-- ---------------------------------------------------------------------
-- 4) google_integration: hide tokens from authenticated reads/writes
--    Tokens are only accessible through service_role (server functions).
-- ---------------------------------------------------------------------
REVOKE ALL ON public.google_integration FROM anon, authenticated;

GRANT SELECT (company_id, email, conectado, calendar_id, expiry, updated_at)
  ON public.google_integration TO authenticated;
GRANT INSERT (company_id, email, conectado, calendar_id, expiry)
  ON public.google_integration TO authenticated;
GRANT UPDATE (email, conectado, calendar_id, expiry)
  ON public.google_integration TO authenticated;
GRANT DELETE ON public.google_integration TO authenticated;
GRANT ALL ON public.google_integration TO service_role;

-- ---------------------------------------------------------------------
-- 5) Realtime: tenant-scoped channel subscriptions
--    Channel topics must be 'tenant:<company_uuid>[:suffix]'
-- ---------------------------------------------------------------------
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tenant_topic_subscription" ON realtime.messages;
CREATE POLICY "tenant_topic_subscription"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  (realtime.topic())::text ~ '^tenant:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(:.*)?$'
  AND public.has_company_access(split_part((realtime.topic())::text, ':', 2)::uuid)
);

-- ---------------------------------------------------------------------
-- 6) Revoke EXECUTE on SECURITY DEFINER functions that are not meant
--    to be callable as RPC by API roles. RLS helpers
--    (is_super_admin / has_company_access / current_company_id /
--    has_company_role) must stay executable for authenticated,
--    otherwise Row Level Security stops working.
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.handle_new_user()             FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_default_stages()         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_set_updated_at()           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_super_admin_if_empty()  FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.is_super_admin()              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_company_access(uuid)      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.current_company_id()          FROM PUBLIC, anon;

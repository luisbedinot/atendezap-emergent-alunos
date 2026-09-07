
-- 1) agent_config: restrict to owner/admin (protects openai/anthropic api keys)
DROP POLICY IF EXISTS agent_config_access ON public.agent_config;
CREATE POLICY agent_config_owner_admin ON public.agent_config
  FOR ALL
  USING (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']))
  WITH CHECK (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']));

-- 2) google_integration: confirm owner/admin only (recreate idempotently)
DROP POLICY IF EXISTS google_integration_access ON public.google_integration;
CREATE POLICY google_integration_owner_admin ON public.google_integration
  FOR ALL
  USING (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']))
  WITH CHECK (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']));

-- 3) company_billing: restrict reads to owner/admin
DROP POLICY IF EXISTS "billing company read" ON public.company_billing;
DROP POLICY IF EXISTS "billing owner write" ON public.company_billing;
CREATE POLICY billing_owner_admin_read ON public.company_billing
  FOR SELECT
  USING (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']));
CREATE POLICY billing_owner_admin_write ON public.company_billing
  FOR ALL
  USING (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']))
  WITH CHECK (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']));

-- 4) subscription: restrict reads to owner/admin (hides paddle/stripe IDs)
DROP POLICY IF EXISTS "subscription company access" ON public.subscription;
CREATE POLICY subscription_owner_admin_read ON public.subscription
  FOR SELECT
  USING (is_super_admin() OR has_company_role(company_id, ARRAY['owner','admin']));

-- 5) profiles: owners/admins can view profiles of company members
DROP POLICY IF EXISTS profiles_company_admin_select ON public.profiles;
CREATE POLICY profiles_company_admin_select ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.company_user me
      JOIN public.company_user target
        ON target.company_id = me.company_id
      WHERE me.user_id = auth.uid()
        AND me.ativo = true
        AND me.role IN ('owner'::public.tenant_role, 'admin'::public.tenant_role)
        AND target.user_id = profiles.user_id
        AND target.ativo = true
    )
  );

-- 6) Lock down SECURITY DEFINER helpers that should only run from triggers
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_default_stages() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_super_admin_if_empty() FROM PUBLIC, anon, authenticated;

-- Harden search_path on tg_set_updated_at
CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $function$;

-- Earlier runtime bootstrap granted all operations after the security
-- migration. Restore those boundaries when upgrading an existing preview.
-- GoTrue previously created users with an empty database role. Repair only
-- empty roles; password hashes and existing nonempty roles are preserved.
UPDATE auth.users SET role = 'authenticated' WHERE role IS NULL OR role = '';

REVOKE ALL ON public.app_config FROM anon;
REVOKE ALL ON public.google_integration FROM anon, authenticated;
REVOKE UPDATE ON public.company FROM authenticated;
GRANT UPDATE (
  nome, primary_color, logo_url, telefone, tipo_pessoa, cnpj_cpf,
  razao_social, nome_fantasia, inscricao_estadual, segmento, porte, site,
  email_corporativo, cep, rua, numero, complemento, bairro, cidade, estado,
  pais, onboarding_completed, onboarding_step, financeiro_ativo,
  financeiro_dias_vencimento_padrao
) ON public.company TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.subscription FROM authenticated;
GRANT SELECT ON public.subscription TO authenticated;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.seed_default_stages() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_super_admin_if_empty() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_super_admin_if_empty() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_company_access(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.current_company_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_company_role(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin(), public.has_company_access(uuid),
  public.current_company_id(), public.has_company_role(uuid, text[])
TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.consume_ai_credit(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.topup_plan_credits(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refund_ai_credit(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_campaign_targets(uuid, integer, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_ai_credit(uuid, text),
  public.topup_plan_credits(uuid, text), public.refund_ai_credit(uuid, text),
  public.claim_campaign_targets(uuid, integer, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.grant_credits(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_credits(uuid, integer, text) TO authenticated, service_role;

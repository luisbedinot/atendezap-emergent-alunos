-- AtendeZap clone readiness + security hardening.
-- This migration intentionally corrects historical seeds without rewriting
-- migrations that may already have run in existing projects.

-- ---------------------------------------------------------------------------
-- 1. Every clone bootstraps its own first real super administrator.
-- ---------------------------------------------------------------------------
DELETE FROM public.user_roles
WHERE user_id = '5d59803b-d8b6-492c-870f-597bf304cd9e'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = '5d59803b-d8b6-492c-870f-597bf304cd9e'::uuid
  );

UPDATE public.app_config
SET super_admin_emails = array_remove(super_admin_emails, 'luis.bedinot@gmail.com'),
    updated_at = now()
WHERE id = true
  AND 'luis.bedinot@gmail.com' = ANY(super_admin_emails)
  AND NOT EXISTS (
    SELECT 1 FROM auth.users WHERE lower(email) = 'luis.bedinot@gmail.com'
  );

-- Historical seeds must not send a cloned installation to the original
-- project's checkout. Each owner configures their own provider URLs.
UPDATE public.plan
SET checkout_url = NULL
WHERE checkout_url IN (
  'https://pay.kiwify.com.br/VjuB3ZQ',
  'https://pay.kiwify.com.br/MxQXUxn',
  'https://pay.kiwify.com.br/AOVOIkU'
);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  _allow text[];
BEGIN
  INSERT INTO public.profiles (user_id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (user_id) DO NOTHING;

  PERFORM pg_advisory_xact_lock(hashtext('atendezap:first-super-admin'));
  SELECT super_admin_emails INTO _allow FROM public.app_config WHERE id = true;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE role = 'super_admin'::public.app_role
  ) OR (
    NEW.email IS NOT NULL
    AND _allow IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM unnest(_allow) AS allowed(email)
      WHERE lower(allowed.email) = lower(NEW.email)
    )
  ) THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'super_admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.claim_super_admin_if_empty()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  _email text;
  _allow text[];
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT email INTO _email FROM auth.users WHERE id = auth.uid();
  IF _email IS NULL THEN RETURN; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('atendezap:first-super-admin'));
  SELECT super_admin_emails INTO _allow FROM public.app_config WHERE id = true;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE role = 'super_admin'::public.app_role
  ) OR (
    _allow IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM unnest(_allow) AS allowed(email)
      WHERE lower(allowed.email) = lower(_email)
    )
  ) THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (auth.uid(), 'super_admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.claim_super_admin_if_empty() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_super_admin_if_empty() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Tenant roles cannot edit billing, plan or credit state directly.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS company_update ON public.company;
CREATE POLICY company_update ON public.company
FOR UPDATE TO authenticated
USING (
  public.is_super_admin()
  OR public.has_company_role(id, ARRAY['owner','admin'])
)
WITH CHECK (
  public.is_super_admin()
  OR public.has_company_role(id, ARRAY['owner','admin'])
);

REVOKE UPDATE ON public.company FROM authenticated;
GRANT UPDATE (
  nome, primary_color, logo_url, telefone, tipo_pessoa, cnpj_cpf,
  razao_social, nome_fantasia, inscricao_estadual, segmento, porte, site,
  email_corporativo, cep, rua, numero, complemento, bairro, cidade, estado,
  pais, onboarding_completed, onboarding_step, financeiro_ativo,
  financeiro_dias_vencimento_padrao
) ON public.company TO authenticated;

DROP POLICY IF EXISTS company_user_delete ON public.company_user;
CREATE POLICY company_user_delete ON public.company_user
FOR DELETE TO authenticated
USING (
  public.is_super_admin()
  OR public.has_company_role(company_id, ARRAY['owner','admin'])
);

DROP POLICY IF EXISTS "subscription owner update" ON public.subscription;
REVOKE INSERT, UPDATE, DELETE ON public.subscription FROM authenticated;
GRANT SELECT ON public.subscription TO authenticated;

DROP POLICY IF EXISTS "webhook_endpoint_company_access" ON public.webhook_endpoint;
CREATE POLICY webhook_endpoint_owner_admin ON public.webhook_endpoint
FOR ALL TO authenticated
USING (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','admin']))
WITH CHECK (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','admin']));

DROP POLICY IF EXISTS "api_token_company_access" ON public.api_token;
CREATE POLICY api_token_owner_admin ON public.api_token
FOR ALL TO authenticated
USING (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','admin']))
WITH CHECK (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','admin']));

DROP POLICY IF EXISTS "webhook_log_company_read" ON public.webhook_delivery_log;
CREATE POLICY webhook_log_owner_admin_read ON public.webhook_delivery_log
FOR SELECT TO authenticated
USING (public.is_super_admin() OR public.has_company_role(company_id, ARRAY['owner','admin']));

-- ---------------------------------------------------------------------------
-- 3. Credits are mutated only by trusted backend code.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refund_ai_credit(_company_id uuid, _ref text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  _novo integer;
BEGIN
  UPDATE public.company
  SET creditos_saldo = creditos_saldo + 1
  WHERE id = _company_id
  RETURNING creditos_saldo INTO _novo;

  IF _novo IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.credit_ledger(company_id, delta, saldo_apos, motivo, ref)
  VALUES (_company_id, 1, _novo, 'ai_message_refund', _ref);
  RETURN _novo;
END $function$;

REVOKE ALL ON FUNCTION public.consume_ai_credit(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.topup_plan_credits(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refund_ai_credit(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.grant_credits(uuid, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_ai_credit(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.topup_plan_credits(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.refund_ai_credit(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.grant_credits(uuid, integer, text) TO authenticated, service_role;

-- Existing self-service trials created before the fix receive their selected plan.
INSERT INTO public.subscription (
  company_id, plan_id, status, trial_ends_at, current_period_end, metadata
)
SELECT
  c.id, p.id, 'trialing', c.trial_ate, c.trial_ate,
  jsonb_build_object('source', 'trial_backfill')
FROM public.company c
JOIN public.plan p ON p.slug = c.selected_plan_slug AND p.ativo = true
WHERE c.status_cobranca = 'trial'
  AND c.trial_ate > now()
ON CONFLICT (company_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Campaign worker claims targets atomically and requires a backend secret.
-- ---------------------------------------------------------------------------
ALTER TABLE public.campaign_target
  ADD COLUMN IF NOT EXISTS processing_token uuid,
  ADD COLUMN IF NOT EXISTS processing_started_at timestamptz;

CREATE INDEX IF NOT EXISTS campaign_target_processing_idx
ON public.campaign_target(campaign_id, processing_started_at)
WHERE status = 'pendente';

CREATE OR REPLACE FUNCTION public.claim_campaign_targets(
  _campaign_id uuid,
  _limit integer,
  _token uuid
)
RETURNS TABLE(id uuid, contato_numero text, contato_nome text)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH picked AS (
    SELECT ct.id
    FROM public.campaign_target ct
    WHERE ct.campaign_id = _campaign_id
      AND ct.status = 'pendente'::public.campaign_target_status
      AND (
        ct.processing_token IS NULL
        OR ct.processing_started_at < now() - interval '5 minutes'
      )
    ORDER BY ct.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(_limit, 1), 50)
  ), claimed AS (
    UPDATE public.campaign_target ct
    SET processing_token = _token, processing_started_at = now()
    FROM picked
    WHERE ct.id = picked.id
    RETURNING ct.id, ct.contato_numero, ct.contato_nome
  )
  SELECT claimed.id, claimed.contato_numero, claimed.contato_nome FROM claimed;
$function$;

REVOKE ALL ON FUNCTION public.claim_campaign_targets(uuid, integer, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_campaign_targets(uuid, integer, uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. Billing webhook replay protection.
-- ---------------------------------------------------------------------------
ALTER TABLE public.billing_event_log
  ADD COLUMN IF NOT EXISTS event_key text;

CREATE UNIQUE INDEX IF NOT EXISTS billing_event_log_event_key_unique
ON public.billing_event_log(provider, event_key)
WHERE event_key IS NOT NULL;

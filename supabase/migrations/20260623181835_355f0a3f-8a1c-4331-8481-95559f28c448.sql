
-- 1) Plan: créditos configuráveis
ALTER TABLE public.plan
  ADD COLUMN IF NOT EXISTS creditos_mensais integer NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS creditos_trial integer NOT NULL DEFAULT 100;

-- 2) Company: saldo de créditos
ALTER TABLE public.company
  ADD COLUMN IF NOT EXISTS creditos_saldo integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS creditos_resetam_em timestamptz,
  ADD COLUMN IF NOT EXISTS creditos_origem text NOT NULL DEFAULT 'trial'
    CHECK (creditos_origem IN ('trial','plano','bonus'));

-- 3) Ledger
CREATE TABLE IF NOT EXISTS public.credit_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  delta integer NOT NULL,
  saldo_apos integer NOT NULL,
  motivo text NOT NULL,
  ref text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS credit_ledger_company_idx ON public.credit_ledger(company_id, created_at DESC);

GRANT SELECT ON public.credit_ledger TO authenticated;
GRANT ALL ON public.credit_ledger TO service_role;
ALTER TABLE public.credit_ledger ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ledger company members read" ON public.credit_ledger
  FOR SELECT TO authenticated
  USING (public.has_company_role(company_id, ARRAY['owner','admin']) OR public.is_super_admin());

-- 4) Funções
CREATE OR REPLACE FUNCTION public.consume_ai_credit(_company_id uuid, _ref text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _novo int;
BEGIN
  UPDATE public.company
    SET creditos_saldo = creditos_saldo - 1
    WHERE id = _company_id AND creditos_saldo > 0
    RETURNING creditos_saldo INTO _novo;
  IF _novo IS NULL THEN RETURN false; END IF;
  INSERT INTO public.credit_ledger(company_id, delta, saldo_apos, motivo, ref)
    VALUES (_company_id, -1, _novo, 'ai_message', _ref);
  RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.grant_credits(_company_id uuid, _qtd integer, _motivo text DEFAULT 'bonus_admin')
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _novo int; _uid uuid;
BEGIN
  IF NOT public.is_super_admin() THEN RAISE EXCEPTION 'Acesso negado'; END IF;
  IF _qtd = 0 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
  _uid := auth.uid();
  UPDATE public.company
    SET creditos_saldo = GREATEST(0, creditos_saldo + _qtd)
    WHERE id = _company_id
    RETURNING creditos_saldo INTO _novo;
  IF _novo IS NULL THEN RAISE EXCEPTION 'Empresa não encontrada'; END IF;
  INSERT INTO public.credit_ledger(company_id, delta, saldo_apos, motivo, created_by)
    VALUES (_company_id, _qtd, _novo, _motivo, _uid);
  RETURN _novo;
END $$;

CREATE OR REPLACE FUNCTION public.topup_plan_credits(_company_id uuid, _plan_slug text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _qtd int; _novo int;
BEGIN
  SELECT creditos_mensais INTO _qtd FROM public.plan WHERE slug = _plan_slug AND ativo = true;
  IF _qtd IS NULL THEN RETURN NULL; END IF;
  UPDATE public.company
    SET creditos_saldo = _qtd,
        creditos_origem = 'plano',
        creditos_resetam_em = now() + interval '30 days'
    WHERE id = _company_id
    RETURNING creditos_saldo INTO _novo;
  INSERT INTO public.credit_ledger(company_id, delta, saldo_apos, motivo, ref)
    VALUES (_company_id, _qtd, _novo, 'plan_topup', _plan_slug);
  RETURN _novo;
END $$;

-- 5) Trigger: ao criar empresa, entrega créditos trial baseado no plano selecionado
CREATE OR REPLACE FUNCTION public.tg_company_trial_credits()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _qtd int;
BEGIN
  IF NEW.selected_plan_slug IS NOT NULL THEN
    SELECT creditos_trial INTO _qtd FROM public.plan WHERE slug = NEW.selected_plan_slug;
  END IF;
  IF _qtd IS NULL THEN _qtd := 100; END IF;
  NEW.creditos_saldo := _qtd;
  NEW.creditos_origem := 'trial';
  NEW.creditos_resetam_em := NEW.trial_ate;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS company_trial_credits ON public.company;
CREATE TRIGGER company_trial_credits
  BEFORE INSERT ON public.company
  FOR EACH ROW EXECUTE FUNCTION public.tg_company_trial_credits();

-- 6) Backfill: empresas existentes ganham créditos trial agora
UPDATE public.plan SET creditos_mensais = limite_mensagens WHERE creditos_mensais = 1000;
UPDATE public.company c
  SET creditos_saldo = COALESCE((SELECT creditos_trial FROM public.plan WHERE slug = c.selected_plan_slug), 100)
  WHERE creditos_saldo = 0;

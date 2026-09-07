
-- ============ MÓDULO FINANCEIRO ============

-- 1) Coluna na empresa
ALTER TABLE public.company
  ADD COLUMN IF NOT EXISTS financeiro_ativo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS financeiro_dias_vencimento_padrao smallint NOT NULL DEFAULT 7;

-- 2) Enums
DO $$ BEGIN
  CREATE TYPE public.fin_tipo AS ENUM ('receita','despesa');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.fin_status AS ENUM ('pendente','pago','atrasado','cancelado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.fin_forma AS ENUM ('pix','boleto','cartao','dinheiro','transferencia','outro');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3) Categorias
CREATE TABLE IF NOT EXISTS public.fin_categoria (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  nome text NOT NULL,
  tipo public.fin_tipo NOT NULL,
  cor text NOT NULL DEFAULT '#8AA89A',
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, tipo, nome)
);
CREATE INDEX IF NOT EXISTS idx_fin_categoria_company ON public.fin_categoria(company_id, tipo);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fin_categoria TO authenticated;
GRANT ALL ON public.fin_categoria TO service_role;
ALTER TABLE public.fin_categoria ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fin_categoria_access" ON public.fin_categoria
  FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

-- 4) Lançamentos
CREATE TABLE IF NOT EXISTS public.fin_lancamento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  tipo public.fin_tipo NOT NULL,
  descricao text NOT NULL,
  valor_cents bigint NOT NULL CHECK (valor_cents >= 0),
  categoria_id uuid REFERENCES public.fin_categoria(id) ON DELETE SET NULL,
  forma_pagamento public.fin_forma,
  status public.fin_status NOT NULL DEFAULT 'pendente',
  vencimento date NOT NULL,
  pago_em date,
  competencia date NOT NULL DEFAULT CURRENT_DATE,
  crm_card_id uuid REFERENCES public.crm_cards(id) ON DELETE SET NULL,
  contato_numero text,
  observacao text,
  anexo_url text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS fin_lancamento_card_uniq
  ON public.fin_lancamento(company_id, crm_card_id) WHERE crm_card_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_lanc_company_status ON public.fin_lancamento(company_id, status, vencimento);
CREATE INDEX IF NOT EXISTS idx_fin_lanc_company_tipo ON public.fin_lancamento(company_id, tipo, competencia);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fin_lancamento TO authenticated;
GRANT ALL ON public.fin_lancamento TO service_role;
ALTER TABLE public.fin_lancamento ENABLE ROW LEVEL SECURITY;

CREATE POLICY "fin_lancamento_access" ON public.fin_lancamento
  FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

-- updated_at trigger
DROP TRIGGER IF EXISTS tg_fin_lancamento_updated_at ON public.fin_lancamento;
CREATE TRIGGER tg_fin_lancamento_updated_at
  BEFORE UPDATE ON public.fin_lancamento
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- 5) Seed categorias quando empresa ativa o módulo
CREATE OR REPLACE FUNCTION public.seed_fin_categorias(_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.fin_categoria (company_id, nome, tipo, cor) VALUES
    (_company_id, 'Vendas', 'receita', '#22B85F'),
    (_company_id, 'Serviços', 'receita', '#8AA89A'),
    (_company_id, 'Outras receitas', 'receita', '#5DB6FF'),
    (_company_id, 'Marketing', 'despesa', '#FFB020'),
    (_company_id, 'Folha de pagamento', 'despesa', '#FF7A59'),
    (_company_id, 'Infraestrutura', 'despesa', '#A36BFF'),
    (_company_id, 'Operacional', 'despesa', '#FF5A5A'),
    (_company_id, 'Impostos', 'despesa', '#666666')
  ON CONFLICT DO NOTHING;
END $$;

-- 6) Trigger: card movido pra stage 'ganho' -> lançamento receita
CREATE OR REPLACE FUNCTION public.tg_fin_auto_receita_on_ganho()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _stage_tipo text;
  _old_stage_tipo text;
  _ativo boolean;
  _dias smallint;
  _cat uuid;
BEGIN
  IF NEW.stage_id IS NULL THEN RETURN NEW; END IF;

  SELECT s.tipo::text INTO _stage_tipo FROM public.crm_stage s WHERE s.id = NEW.stage_id;
  IF _stage_tipo IS DISTINCT FROM 'ganho' THEN RETURN NEW; END IF;

  IF TG_OP = 'UPDATE' AND OLD.stage_id IS NOT NULL THEN
    SELECT s.tipo::text INTO _old_stage_tipo FROM public.crm_stage s WHERE s.id = OLD.stage_id;
    IF _old_stage_tipo = 'ganho' THEN RETURN NEW; END IF;
  END IF;

  SELECT financeiro_ativo, financeiro_dias_vencimento_padrao
    INTO _ativo, _dias
    FROM public.company WHERE id = NEW.company_id;
  IF NOT COALESCE(_ativo, false) THEN RETURN NEW; END IF;

  SELECT id INTO _cat FROM public.fin_categoria
    WHERE company_id = NEW.company_id AND tipo = 'receita' AND nome = 'Vendas'
    LIMIT 1;

  INSERT INTO public.fin_lancamento (
    company_id, tipo, descricao, valor_cents, categoria_id,
    status, vencimento, competencia, crm_card_id, contato_numero
  ) VALUES (
    NEW.company_id, 'receita',
    COALESCE('Venda: ' || NULLIF(NEW.nome,''), 'Venda CRM ' || NEW.numero),
    GREATEST(0, COALESCE((NEW.valor * 100)::bigint, 0)),
    _cat,
    'pendente',
    CURRENT_DATE + COALESCE(_dias, 7),
    CURRENT_DATE,
    NEW.id, NEW.numero
  )
  ON CONFLICT (company_id, crm_card_id) WHERE crm_card_id IS NOT NULL DO NOTHING;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS tg_crm_cards_fin_receita ON public.crm_cards;
CREATE TRIGGER tg_crm_cards_fin_receita
  AFTER INSERT OR UPDATE OF stage_id ON public.crm_cards
  FOR EACH ROW EXECUTE FUNCTION public.tg_fin_auto_receita_on_ganho();

-- 7) Função pra ativar módulo (chamada do toggle)
CREATE OR REPLACE FUNCTION public.fin_enable_for_company(_company_id uuid, _enable boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_company_role(_company_id, ARRAY['owner','admin']) THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;
  UPDATE public.company SET financeiro_ativo = _enable WHERE id = _company_id;
  IF _enable THEN PERFORM public.seed_fin_categorias(_company_id); END IF;
END $$;

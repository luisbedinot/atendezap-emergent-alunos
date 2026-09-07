
-- ============ ENUM ============
DO $$ BEGIN
  CREATE TYPE public.stage_tipo AS ENUM ('normal','ganho','perda');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ crm_stage ============
CREATE TABLE IF NOT EXISTS public.crm_stage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  nome text NOT NULL,
  ordem int NOT NULL DEFAULT 0,
  cor text NOT NULL DEFAULT '#8AA89A',
  tipo public.stage_tipo NOT NULL DEFAULT 'normal',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_crm_stage_company ON public.crm_stage(company_id, ordem);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_stage TO authenticated;
GRANT ALL ON public.crm_stage TO service_role;
ALTER TABLE public.crm_stage ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY crm_stage_access ON public.crm_stage
    FOR ALL TO authenticated
    USING (public.is_super_admin() OR public.has_company_access(company_id))
    WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ produto ============
CREATE TABLE IF NOT EXISTS public.produto (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  nome text NOT NULL,
  preco numeric NOT NULL DEFAULT 0,
  descricao text,
  ativo boolean NOT NULL DEFAULT true,
  ordem int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_produto_company ON public.produto(company_id, ordem);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.produto TO authenticated;
GRANT ALL ON public.produto TO service_role;
ALTER TABLE public.produto ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY produto_access ON public.produto
    FOR ALL TO authenticated
    USING (public.is_super_admin() OR public.has_company_access(company_id))
    WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ extend crm_cards ============
ALTER TABLE public.crm_cards DROP CONSTRAINT IF EXISTS crm_cards_status_check;
ALTER TABLE public.crm_cards
  ADD COLUMN IF NOT EXISTS stage_id uuid REFERENCES public.crm_stage(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS valor numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS origem text,
  ADD COLUMN IF NOT EXISTS owner_id uuid,
  ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS proxima_acao text,
  ADD COLUMN IF NOT EXISTS follow_up timestamptz;
CREATE INDEX IF NOT EXISTS idx_crm_cards_stage ON public.crm_cards(stage_id);

-- ============ lead_nota ============
CREATE TABLE IF NOT EXISTS public.lead_nota (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  card_id uuid NOT NULL REFERENCES public.crm_cards(id) ON DELETE CASCADE,
  autor_id uuid,
  texto text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lead_nota_card ON public.lead_nota(card_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_nota TO authenticated;
GRANT ALL ON public.lead_nota TO service_role;
ALTER TABLE public.lead_nota ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY lead_nota_access ON public.lead_nota
    FOR ALL TO authenticated
    USING (public.is_super_admin() OR public.has_company_access(company_id))
    WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ lead_evento ============
CREATE TABLE IF NOT EXISTS public.lead_evento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  card_id uuid NOT NULL REFERENCES public.crm_cards(id) ON DELETE CASCADE,
  tipo text NOT NULL,
  descricao text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lead_evento_card ON public.lead_evento(card_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_evento TO authenticated;
GRANT ALL ON public.lead_evento TO service_role;
ALTER TABLE public.lead_evento ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY lead_evento_access ON public.lead_evento
    FOR ALL TO authenticated
    USING (public.is_super_admin() OR public.has_company_access(company_id))
    WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ agendamento ============
CREATE TABLE IF NOT EXISTS public.agendamento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  card_id uuid REFERENCES public.crm_cards(id) ON DELETE SET NULL,
  titulo text NOT NULL,
  inicio timestamptz NOT NULL,
  fim timestamptz NOT NULL,
  google_event_id text,
  status text NOT NULL DEFAULT 'agendado',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_agendamento_company ON public.agendamento(company_id, inicio);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.agendamento TO authenticated;
GRANT ALL ON public.agendamento TO service_role;
ALTER TABLE public.agendamento ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY agendamento_access ON public.agendamento
    FOR ALL TO authenticated
    USING (public.is_super_admin() OR public.has_company_access(company_id))
    WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ google_integration ============
CREATE TABLE IF NOT EXISTS public.google_integration (
  company_id uuid PRIMARY KEY REFERENCES public.company(id) ON DELETE CASCADE,
  email text,
  access_token text,
  refresh_token text,
  expiry timestamptz,
  calendar_id text,
  conectado boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.google_integration TO authenticated;
GRANT ALL ON public.google_integration TO service_role;
ALTER TABLE public.google_integration ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY google_integration_access ON public.google_integration
    FOR ALL TO authenticated
    USING (
      public.is_super_admin() OR EXISTS (
        SELECT 1 FROM public.company_user cu
        WHERE cu.company_id = google_integration.company_id
          AND cu.user_id = auth.uid()
          AND cu.ativo = true
          AND cu.role IN ('owner','admin')
      )
    )
    WITH CHECK (
      public.is_super_admin() OR EXISTS (
        SELECT 1 FROM public.company_user cu
        WHERE cu.company_id = google_integration.company_id
          AND cu.user_id = auth.uid()
          AND cu.ativo = true
          AND cu.role IN ('owner','admin')
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ agent_config extensions ============
ALTER TABLE public.agent_config
  ADD COLUMN IF NOT EXISTS segmento text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS descricao_negocio text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS diferenciais text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS publico_alvo text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS regiao_horario text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS ofertas text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS cupom text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS como_vender text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS objecoes text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS formas_pagamento text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS ticket_medio text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS faq text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS politicas text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS posvenda_msg text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS pedir_avaliacao boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reativar_cliente boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tom int NOT NULL DEFAULT 70,
  ADD COLUMN IF NOT EXISTS formalidade int NOT NULL DEFAULT 40,
  ADD COLUMN IF NOT EXISTS usar_emojis boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS tamanho_resposta text NOT NULL DEFAULT 'curtas',
  ADD COLUMN IF NOT EXISTS apresentacao text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS agendamento_ativo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS servicos_agendaveis text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS duracao_padrao text NOT NULL DEFAULT '30 min',
  ADD COLUMN IF NOT EXISTS horarios_disponiveis text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS antecedencia_min text NOT NULL DEFAULT '2 horas';

-- ============ SEED default stages for existing companies ============
INSERT INTO public.crm_stage (company_id, nome, ordem, cor, tipo)
SELECT c.id, v.nome, v.ordem, v.cor, v.tipo::public.stage_tipo
FROM public.company c
CROSS JOIN (VALUES
  ('Conversas', 0, '#8AA89A', 'normal'),
  ('Negociando', 1, '#FFB020', 'normal'),
  ('Ganho', 2, '#22B85F', 'ganho'),
  ('Perda', 3, '#FF5A5A', 'perda')
) AS v(nome, ordem, cor, tipo)
WHERE NOT EXISTS (
  SELECT 1 FROM public.crm_stage s WHERE s.company_id = c.id
);

-- ============ BACKFILL crm_cards.stage_id ============
UPDATE public.crm_cards cc
SET stage_id = s.id
FROM public.crm_stage s
WHERE cc.stage_id IS NULL
  AND s.company_id = cc.company_id
  AND lower(s.nome) = CASE lower(cc.status)
    WHEN 'conversas' THEN 'conversas'
    WHEN 'negociando' THEN 'negociando'
    WHEN 'ganho' THEN 'ganho'
    WHEN 'perda' THEN 'perda'
    ELSE lower(cc.status)
  END;

-- ============ Trigger: seed default stages for new companies ============
CREATE OR REPLACE FUNCTION public.seed_default_stages()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.crm_stage (company_id, nome, ordem, cor, tipo) VALUES
    (NEW.id, 'Conversas',  0, '#8AA89A', 'normal'),
    (NEW.id, 'Negociando', 1, '#FFB020', 'normal'),
    (NEW.id, 'Ganho',      2, '#22B85F', 'ganho'),
    (NEW.id, 'Perda',      3, '#FF5A5A', 'perda')
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_company_seed_stages ON public.company;
CREATE TRIGGER trg_company_seed_stages
AFTER INSERT ON public.company
FOR EACH ROW EXECUTE FUNCTION public.seed_default_stages();

-- ============ Realtime ============
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.crm_stage;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

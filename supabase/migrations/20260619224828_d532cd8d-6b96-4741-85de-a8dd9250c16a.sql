
-- Campaign status enum
DO $$ BEGIN
  CREATE TYPE public.campaign_status AS ENUM ('rascunho','agendada','enviando','pausada','concluida','cancelada');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE public.campaign_target_status AS ENUM ('pendente','enviado','falhou','pulado');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- Campaign table
CREATE TABLE IF NOT EXISTS public.campaign (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  nome text NOT NULL,
  mensagem text NOT NULL,
  media_url text,
  status public.campaign_status NOT NULL DEFAULT 'rascunho',
  agendado_para timestamptz,
  filtro_tags text[] DEFAULT '{}',
  intervalo_min_seg integer NOT NULL DEFAULT 5,
  intervalo_max_seg integer NOT NULL DEFAULT 20,
  pausa_apos_envios integer NOT NULL DEFAULT 50,
  pausa_duracao_min integer NOT NULL DEFAULT 10,
  total_destinatarios integer NOT NULL DEFAULT 0,
  total_enviados integer NOT NULL DEFAULT 0,
  total_falhas integer NOT NULL DEFAULT 0,
  iniciado_em timestamptz,
  concluido_em timestamptz,
  proximo_envio_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign TO authenticated;
GRANT ALL ON public.campaign TO service_role;
ALTER TABLE public.campaign ENABLE ROW LEVEL SECURITY;

CREATE POLICY "campaign_company_access" ON public.campaign
  FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

CREATE TRIGGER set_campaign_updated_at BEFORE UPDATE ON public.campaign
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

CREATE INDEX IF NOT EXISTS idx_campaign_company ON public.campaign(company_id);
CREATE INDEX IF NOT EXISTS idx_campaign_status_next ON public.campaign(status, proximo_envio_em) WHERE status IN ('agendada','enviando');

-- Campaign targets
CREATE TABLE IF NOT EXISTS public.campaign_target (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.campaign(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  contato_numero text NOT NULL,
  contato_nome text,
  status public.campaign_target_status NOT NULL DEFAULT 'pendente',
  enviado_em timestamptz,
  erro text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_target TO authenticated;
GRANT ALL ON public.campaign_target TO service_role;
ALTER TABLE public.campaign_target ENABLE ROW LEVEL SECURITY;

CREATE POLICY "campaign_target_company_access" ON public.campaign_target
  FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

CREATE INDEX IF NOT EXISTS idx_campaign_target_campaign ON public.campaign_target(campaign_id, status);
CREATE INDEX IF NOT EXISTS idx_campaign_target_pending ON public.campaign_target(campaign_id) WHERE status = 'pendente';

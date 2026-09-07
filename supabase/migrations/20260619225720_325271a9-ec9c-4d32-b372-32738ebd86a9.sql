
-- UTM tracking on leads
ALTER TABLE public.crm_cards
  ADD COLUMN IF NOT EXISTS utm_source text,
  ADD COLUMN IF NOT EXISTS utm_medium text,
  ADD COLUMN IF NOT EXISTS utm_campaign text;

-- Webhook endpoints
CREATE TABLE IF NOT EXISTS public.webhook_endpoint (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  nome text NOT NULL,
  url text NOT NULL,
  secret text NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
  eventos text[] NOT NULL DEFAULT '{}',
  ativo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.webhook_endpoint TO authenticated;
GRANT ALL ON public.webhook_endpoint TO service_role;
ALTER TABLE public.webhook_endpoint ENABLE ROW LEVEL SECURITY;
CREATE POLICY "webhook_endpoint_company_access" ON public.webhook_endpoint
  FOR ALL TO authenticated USING (public.has_company_access(company_id)) WITH CHECK (public.has_company_access(company_id));
CREATE TRIGGER set_webhook_updated_at BEFORE UPDATE ON public.webhook_endpoint
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE INDEX IF NOT EXISTS idx_webhook_company ON public.webhook_endpoint(company_id) WHERE ativo;

-- API tokens
CREATE TABLE IF NOT EXISTS public.api_token (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  label text NOT NULL,
  token text NOT NULL UNIQUE DEFAULT 'azp_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
  criado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ultimo_uso_em timestamptz,
  revogado boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.api_token TO authenticated;
GRANT ALL ON public.api_token TO service_role;
ALTER TABLE public.api_token ENABLE ROW LEVEL SECURITY;
CREATE POLICY "api_token_company_access" ON public.api_token
  FOR ALL TO authenticated USING (public.has_company_access(company_id)) WITH CHECK (public.has_company_access(company_id));
CREATE TRIGGER set_api_token_updated_at BEFORE UPDATE ON public.api_token
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE INDEX IF NOT EXISTS idx_api_token_company ON public.api_token(company_id);

-- Webhook delivery log
CREATE TABLE IF NOT EXISTS public.webhook_delivery_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  endpoint_id uuid REFERENCES public.webhook_endpoint(id) ON DELETE SET NULL,
  evento text NOT NULL,
  status_code integer,
  erro text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.webhook_delivery_log TO authenticated;
GRANT ALL ON public.webhook_delivery_log TO service_role;
ALTER TABLE public.webhook_delivery_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "webhook_log_company_read" ON public.webhook_delivery_log
  FOR SELECT TO authenticated USING (public.has_company_access(company_id));
CREATE INDEX IF NOT EXISTS idx_webhook_log_company ON public.webhook_delivery_log(company_id, created_at DESC);

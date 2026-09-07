
CREATE TABLE IF NOT EXISTS public.csat_response (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  numero text NOT NULL,
  contato_nome text,
  token text NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  score integer,
  comentario text,
  enviado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  enviado_em timestamptz NOT NULL DEFAULT now(),
  respondido_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT csat_score_range CHECK (score IS NULL OR (score BETWEEN 1 AND 5))
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.csat_response TO authenticated;
GRANT ALL ON public.csat_response TO service_role;
ALTER TABLE public.csat_response ENABLE ROW LEVEL SECURITY;

CREATE POLICY "csat_company_access" ON public.csat_response
  FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

CREATE TRIGGER set_csat_updated_at BEFORE UPDATE ON public.csat_response
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

CREATE INDEX IF NOT EXISTS idx_csat_company ON public.csat_response(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_csat_token ON public.csat_response(token);

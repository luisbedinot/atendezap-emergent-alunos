
-- Fase 1: templates de mensagem rápidos + horário de atendimento
-- (tags já existem em crm_cards.tags[])

CREATE TABLE public.message_template (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  atalho text NOT NULL,
  texto text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, atalho)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.message_template TO authenticated;
GRANT ALL ON public.message_template TO service_role;

ALTER TABLE public.message_template ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members read templates"
  ON public.message_template FOR SELECT TO authenticated
  USING (public.has_company_access(company_id));

CREATE POLICY "members manage templates"
  ON public.message_template FOR ALL TO authenticated
  USING (public.has_company_access(company_id))
  WITH CHECK (public.has_company_access(company_id));

CREATE TRIGGER trg_message_template_updated_at
  BEFORE UPDATE ON public.message_template
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- Horário de atendimento + mensagem fora do horário (no agent_config)
ALTER TABLE public.agent_config
  ADD COLUMN IF NOT EXISTS horarios_atendimento jsonb NOT NULL DEFAULT '{"enabled":false,"timezone":"America/Sao_Paulo","dias":{"0":null,"1":{"abre":"09:00","fecha":"18:00"},"2":{"abre":"09:00","fecha":"18:00"},"3":{"abre":"09:00","fecha":"18:00"},"4":{"abre":"09:00","fecha":"18:00"},"5":{"abre":"09:00","fecha":"18:00"},"6":null}}'::jsonb,
  ADD COLUMN IF NOT EXISTS mensagem_fora_horario text NOT NULL DEFAULT 'Olá! No momento estamos fora do horário de atendimento. Assim que abrirmos, retornamos por aqui. 🙏';


-- ============ EXPAND COMPANY ============
ALTER TABLE public.company
  ADD COLUMN IF NOT EXISTS tipo_pessoa text NOT NULL DEFAULT 'PJ' CHECK (tipo_pessoa IN ('PF','PJ')),
  ADD COLUMN IF NOT EXISTS cnpj_cpf text,
  ADD COLUMN IF NOT EXISTS razao_social text,
  ADD COLUMN IF NOT EXISTS nome_fantasia text,
  ADD COLUMN IF NOT EXISTS inscricao_estadual text,
  ADD COLUMN IF NOT EXISTS segmento text,
  ADD COLUMN IF NOT EXISTS porte text,
  ADD COLUMN IF NOT EXISTS site text,
  ADD COLUMN IF NOT EXISTS email_corporativo text,
  ADD COLUMN IF NOT EXISTS cep text,
  ADD COLUMN IF NOT EXISTS rua text,
  ADD COLUMN IF NOT EXISTS numero text,
  ADD COLUMN IF NOT EXISTS complemento text,
  ADD COLUMN IF NOT EXISTS bairro text,
  ADD COLUMN IF NOT EXISTS cidade text,
  ADD COLUMN IF NOT EXISTS estado text,
  ADD COLUMN IF NOT EXISTS pais text DEFAULT 'BR',
  ADD COLUMN IF NOT EXISTS onboarding_completed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_step int NOT NULL DEFAULT 0;

-- ============ EXPAND PROFILES ============
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS nome_completo text,
  ADD COLUMN IF NOT EXISTS cpf text,
  ADD COLUMN IF NOT EXISTS cargo text,
  ADD COLUMN IF NOT EXISTS telefone text;

-- ============ PLAN TABLE ============
CREATE TABLE IF NOT EXISTS public.plan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  nome text NOT NULL,
  descricao text,
  preco_cents int NOT NULL DEFAULT 0,
  moeda text NOT NULL DEFAULT 'BRL',
  intervalo text NOT NULL DEFAULT 'month' CHECK (intervalo IN ('month','year')),
  trial_days int NOT NULL DEFAULT 3,
  limite_mensagens int NOT NULL DEFAULT 1000,
  limite_instancias int NOT NULL DEFAULT 1,
  limite_usuarios int NOT NULL DEFAULT 2,
  limite_contatos int NOT NULL DEFAULT 1000,
  features jsonb NOT NULL DEFAULT '[]'::jsonb,
  destaque boolean NOT NULL DEFAULT false,
  ativo boolean NOT NULL DEFAULT true,
  ordem int NOT NULL DEFAULT 0,
  paddle_product_id text,
  paddle_price_id text,
  stripe_product_id text,
  stripe_price_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.plan TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.plan TO authenticated;
GRANT ALL ON public.plan TO service_role;
ALTER TABLE public.plan ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plans public read active" ON public.plan FOR SELECT TO anon USING (ativo = true);
CREATE POLICY "plans authenticated read" ON public.plan FOR SELECT TO authenticated USING (true);
CREATE POLICY "plans super admin write" ON public.plan FOR ALL TO authenticated USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());
CREATE TRIGGER trg_plan_updated_at BEFORE UPDATE ON public.plan FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- ============ SUBSCRIPTION TABLE ============
CREATE TABLE IF NOT EXISTS public.subscription (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  plan_id uuid REFERENCES public.plan(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'trialing' CHECK (status IN ('trialing','active','past_due','canceled','incomplete','paused')),
  paddle_subscription_id text,
  paddle_customer_id text,
  stripe_subscription_id text,
  stripe_customer_id text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  canceled_at timestamptz,
  payment_method_brand text,
  payment_method_last4 text,
  payment_method_exp text,
  next_billing_amount_cents int,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS subscription_company_unique ON public.subscription(company_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.subscription TO authenticated;
GRANT ALL ON public.subscription TO service_role;
ALTER TABLE public.subscription ENABLE ROW LEVEL SECURITY;
CREATE POLICY "subscription company access" ON public.subscription FOR SELECT TO authenticated
  USING (public.has_company_access(company_id) OR public.is_super_admin());
CREATE POLICY "subscription super admin write" ON public.subscription FOR ALL TO authenticated
  USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());
CREATE POLICY "subscription owner update" ON public.subscription FOR UPDATE TO authenticated
  USING (public.has_company_role(company_id, ARRAY['owner','admin']))
  WITH CHECK (public.has_company_role(company_id, ARRAY['owner','admin']));
CREATE TRIGGER trg_subscription_updated_at BEFORE UPDATE ON public.subscription FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- ============ COMPANY BILLING TABLE ============
CREATE TABLE IF NOT EXISTS public.company_billing (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL UNIQUE REFERENCES public.company(id) ON DELETE CASCADE,
  tipo_pessoa text NOT NULL DEFAULT 'PJ' CHECK (tipo_pessoa IN ('PF','PJ')),
  cnpj_cpf text,
  razao_social text,
  nome_responsavel text,
  email_cobranca text,
  telefone text,
  inscricao_estadual text,
  cep text,
  rua text,
  numero text,
  complemento text,
  bairro text,
  cidade text,
  estado text,
  pais text DEFAULT 'BR',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_billing TO authenticated;
GRANT ALL ON public.company_billing TO service_role;
ALTER TABLE public.company_billing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "billing company read" ON public.company_billing FOR SELECT TO authenticated
  USING (public.has_company_access(company_id) OR public.is_super_admin());
CREATE POLICY "billing owner write" ON public.company_billing FOR ALL TO authenticated
  USING (public.has_company_role(company_id, ARRAY['owner','admin']) OR public.is_super_admin())
  WITH CHECK (public.has_company_role(company_id, ARRAY['owner','admin']) OR public.is_super_admin());
CREATE TRIGGER trg_billing_updated_at BEFORE UPDATE ON public.company_billing FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- ============ SEED DEFAULT PLANS ============
INSERT INTO public.plan (slug, nome, descricao, preco_cents, intervalo, trial_days, limite_mensagens, limite_instancias, limite_usuarios, limite_contatos, features, destaque, ordem) VALUES
  ('starter', 'Starter', 'Para autônomos e pequenos negócios começando com automação no WhatsApp.', 9700, 'month', 3, 2000, 1, 2, 1000,
    '["1 número de WhatsApp","2 usuários","CRM Kanban completo","IA Gemini incluída","Suporte por email"]'::jsonb,
    false, 1),
  ('pro', 'Pro', 'Para times de vendas que precisam escalar atendimento e conversão.', 19700, 'month', 3, 10000, 3, 8, 5000,
    '["3 números de WhatsApp","8 usuários","CRM Kanban + Automações","IA Gemini, GPT e Claude","Integração Google Agenda","Relatórios avançados","Suporte prioritário"]'::jsonb,
    true, 2),
  ('business', 'Business', 'Para empresas que recebem alto volume e precisam de SLA dedicado.', 49700, 'month', 3, 50000, 10, 30, 25000,
    '["10 números de WhatsApp","30 usuários","Todas as integrações","IA ilimitada (Gemini, GPT, Claude)","API e Webhooks","Gerente de conta dedicado","SLA 99,9% + suporte 24/7"]'::jsonb,
    false, 3)
ON CONFLICT (slug) DO NOTHING;

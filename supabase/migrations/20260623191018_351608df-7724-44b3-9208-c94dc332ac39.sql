
-- Seed allowlist with only the desired super admin
INSERT INTO public.app_config (id, super_admin_emails)
VALUES (true, ARRAY['luis.bedinot@gmail.com'])
ON CONFLICT (id) DO UPDATE SET
  super_admin_emails = ARRAY['luis.bedinot@gmail.com'],
  updated_at = now();

-- Replace trigger to grant super_admin only to allowlisted emails
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

  SELECT super_admin_emails INTO _allow FROM public.app_config WHERE id = true;

  IF NEW.email IS NOT NULL AND _allow IS NOT NULL AND NEW.email = ANY(_allow) THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'super_admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END $function$;

-- Also tighten claim_super_admin_if_empty to respect allowlist
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

  SELECT super_admin_emails INTO _allow FROM public.app_config WHERE id = true;
  IF _allow IS NULL OR NOT (_email = ANY(_allow)) THEN RETURN; END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (auth.uid(), 'super_admin'::public.app_role)
  ON CONFLICT (user_id, role) DO NOTHING;
END $function$;

-- Seed the 3 plans from the landing page
INSERT INTO public.plan (slug, nome, descricao, preco_cents, intervalo, trial_days,
  limite_mensagens, limite_instancias, limite_usuarios, limite_contatos,
  features, destaque, ativo, ordem, creditos_mensais, creditos_trial)
VALUES
  ('starter', 'Starter', 'Pra autônomo testando a operação.', 9700, 'month', 3,
   1500, 1, 1, 1000,
   '["1 número de WhatsApp","1 usuário","1.500 conversas/mês","1.000 contatos","CRM Kanban + IA Gemini","Suporte por email"]'::jsonb,
   false, true, 1, 1500, 50),
  ('pro', 'Pro', 'Pra time que já vende todo dia. O mais escolhido.', 19700, 'month', 3,
   6000, 1, 5, 5000,
   '["1 número de WhatsApp","5 usuários no painel","6.000 conversas/mês","5.000 contatos","IA Gemini + GPT + Claude","Google Agenda + Relatórios","Suporte prioritário"]'::jsonb,
   true, true, 2, 6000, 50),
  ('business', 'Business', 'Pra operação alta performance e múltiplas equipes.', 49700, 'month', 3,
   30000, 1, 20, 25000,
   '["1 número de WhatsApp","20 usuários no painel","30.000 conversas/mês","25.000 contatos","API + Webhooks","Onboarding 1:1 + Gerente dedicado","SLA 99,9% + Suporte 24/7"]'::jsonb,
   false, true, 3, 30000, 50)
ON CONFLICT (slug) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  preco_cents = EXCLUDED.preco_cents,
  limite_mensagens = EXCLUDED.limite_mensagens,
  limite_instancias = EXCLUDED.limite_instancias,
  limite_usuarios = EXCLUDED.limite_usuarios,
  limite_contatos = EXCLUDED.limite_contatos,
  features = EXCLUDED.features,
  destaque = EXCLUDED.destaque,
  ativo = EXCLUDED.ativo,
  ordem = EXCLUDED.ordem,
  creditos_mensais = EXCLUDED.creditos_mensais,
  creditos_trial = EXCLUDED.creditos_trial,
  updated_at = now();

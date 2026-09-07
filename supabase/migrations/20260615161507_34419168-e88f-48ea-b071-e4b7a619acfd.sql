
-- =========================================================
-- FASE A — MULTI-TENANT BASE
-- =========================================================

-- ENUMS ---------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('super_admin');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.tenant_role AS ENUM ('owner','admin','atendente');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- updated_at helper (idempotente) -------------------------
CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS
$$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

-- COMPANY -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text NOT NULL,
  slug text NOT NULL UNIQUE,
  primary_color text NOT NULL DEFAULT '#22C55E',
  logo_url text,
  telefone text,
  status_cobranca text NOT NULL DEFAULT 'trial',
  trial_ate timestamptz NOT NULL DEFAULT (now() + interval '14 days'),
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company TO authenticated;
GRANT ALL ON public.company TO service_role;
ALTER TABLE public.company ENABLE ROW LEVEL SECURITY;
DROP TRIGGER IF EXISTS trg_company_updated ON public.company;
CREATE TRIGGER trg_company_updated BEFORE UPDATE ON public.company
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- COMPANY_USER --------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  company_id uuid NOT NULL REFERENCES public.company(id) ON DELETE CASCADE,
  role public.tenant_role NOT NULL DEFAULT 'owner',
  ativo boolean NOT NULL DEFAULT true,
  forcar_troca_senha boolean NOT NULL DEFAULT false,
  convite_token text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, company_id)
);
CREATE INDEX IF NOT EXISTS idx_company_user_user ON public.company_user(user_id) WHERE ativo;
CREATE INDEX IF NOT EXISTS idx_company_user_company ON public.company_user(company_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_user TO authenticated;
GRANT ALL ON public.company_user TO service_role;
ALTER TABLE public.company_user ENABLE ROW LEVEL SECURITY;
DROP TRIGGER IF EXISTS trg_company_user_updated ON public.company_user;
CREATE TRIGGER trg_company_user_updated BEFORE UPDATE ON public.company_user
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- USER_ROLES ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  role public.app_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- APP_CONFIG (singleton) ----------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  id boolean PRIMARY KEY DEFAULT true,
  super_admin_emails text[] NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_config_singleton CHECK (id = true)
);
GRANT ALL ON public.app_config TO service_role;
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.app_config (id, super_admin_emails)
VALUES (true, ARRAY['luis.bedinot@gmail.com'])
ON CONFLICT (id) DO UPDATE
  SET super_admin_emails =
    (SELECT ARRAY(SELECT DISTINCT unnest(public.app_config.super_admin_emails || EXCLUDED.super_admin_emails)));

-- PROFILES ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  nome text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- =========================================================
-- FUNÇÕES SECURITY DEFINER
-- =========================================================
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = 'super_admin'::public.app_role
  );
$$;

CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT company_id FROM public.company_user
  WHERE user_id = auth.uid() AND ativo = true
  ORDER BY created_at ASC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.has_company_access(_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.company_user
    WHERE user_id = auth.uid()
      AND company_id = _company_id
      AND ativo = true
  );
$$;

CREATE OR REPLACE FUNCTION public.claim_super_admin_if_empty()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  _email text;
  _emails text[];
BEGIN
  SELECT email INTO _email FROM auth.users WHERE id = auth.uid();
  IF _email IS NULL THEN RETURN; END IF;
  SELECT super_admin_emails INTO _emails FROM public.app_config WHERE id = true;
  IF _emails IS NULL THEN RETURN; END IF;
  IF _email = ANY(_emails) THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (auth.uid(), 'super_admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
END $$;

-- handle_new_user trigger ---------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE _emails text[]; _email text;
BEGIN
  INSERT INTO public.profiles (user_id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT super_admin_emails INTO _emails FROM public.app_config WHERE id = true;
  _email := NEW.email;
  IF _emails IS NOT NULL AND _email = ANY(_emails) THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'super_admin'::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- POLICIES: company / company_user / user_roles / profiles
-- =========================================================
DROP POLICY IF EXISTS company_select ON public.company;
CREATE POLICY company_select ON public.company FOR SELECT TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(id));

DROP POLICY IF EXISTS company_insert ON public.company;
CREATE POLICY company_insert ON public.company FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

DROP POLICY IF EXISTS company_update ON public.company;
CREATE POLICY company_update ON public.company FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(id));

DROP POLICY IF EXISTS company_delete ON public.company;
CREATE POLICY company_delete ON public.company FOR DELETE TO authenticated
  USING (public.is_super_admin());

DROP POLICY IF EXISTS company_user_select ON public.company_user;
CREATE POLICY company_user_select ON public.company_user FOR SELECT TO authenticated
  USING (
    public.is_super_admin()
    OR user_id = auth.uid()
    OR public.has_company_access(company_id)
  );

DROP POLICY IF EXISTS company_user_insert ON public.company_user;
CREATE POLICY company_user_insert ON public.company_user FOR INSERT TO authenticated
  WITH CHECK (
    public.is_super_admin()
    OR (user_id = auth.uid())  -- usuário se adiciona ao criar empresa
    OR public.has_company_access(company_id) -- owners convidam
  );

DROP POLICY IF EXISTS company_user_update ON public.company_user;
CREATE POLICY company_user_update ON public.company_user FOR UPDATE TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id) OR user_id = auth.uid())
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id) OR user_id = auth.uid());

DROP POLICY IF EXISTS company_user_delete ON public.company_user;
CREATE POLICY company_user_delete ON public.company_user FOR DELETE TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id));

DROP POLICY IF EXISTS user_roles_select ON public.user_roles;
CREATE POLICY user_roles_select ON public.user_roles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());

DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_super_admin());

DROP POLICY IF EXISTS profiles_update ON public.profiles;
CREATE POLICY profiles_update ON public.profiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS profiles_insert ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- =========================================================
-- RE-ESCOPE: add company_id às tabelas do motor + backfill
-- =========================================================
ALTER TABLE public.agent_config        ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.whatsapp_instances  ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.mensagens           ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.crm_cards           ADD COLUMN IF NOT EXISTS company_id uuid;
ALTER TABLE public.contact_pause       ADD COLUMN IF NOT EXISTS company_id uuid;

-- Cria 1 company por user_id existente (em qualquer tabela do motor) que ainda não tem company
DO $$
DECLARE r record; _cid uuid; _email text; _slug text; _base text; _i int;
BEGIN
  FOR r IN
    SELECT DISTINCT u_id FROM (
      SELECT user_id AS u_id FROM public.agent_config
      UNION SELECT user_id FROM public.whatsapp_instances
      UNION SELECT user_id FROM public.mensagens
      UNION SELECT user_id FROM public.crm_cards
      UNION SELECT user_id FROM public.contact_pause
    ) s WHERE u_id IS NOT NULL
  LOOP
    -- já tem company?
    SELECT company_id INTO _cid FROM public.company_user
      WHERE user_id = r.u_id AND ativo = true LIMIT 1;

    IF _cid IS NULL THEN
      SELECT email INTO _email FROM auth.users WHERE id = r.u_id;
      _base := COALESCE(regexp_replace(lower(split_part(COALESCE(_email,'minha-empresa'),'@',1)),'[^a-z0-9]+','-','g'), 'empresa');
      _slug := _base; _i := 1;
      WHILE EXISTS (SELECT 1 FROM public.company WHERE slug = _slug) LOOP
        _i := _i + 1; _slug := _base || '-' || _i;
      END LOOP;

      INSERT INTO public.company (nome, slug, created_by, status_cobranca, trial_ate)
      VALUES (COALESCE(_email,'Minha empresa'), _slug, r.u_id, 'trial', now() + interval '14 days')
      RETURNING id INTO _cid;

      INSERT INTO public.company_user (user_id, company_id, role, ativo)
      VALUES (r.u_id, _cid, 'owner', true)
      ON CONFLICT (user_id, company_id) DO NOTHING;
    END IF;

    UPDATE public.agent_config       SET company_id = _cid WHERE user_id = r.u_id AND company_id IS NULL;
    UPDATE public.whatsapp_instances SET company_id = _cid WHERE user_id = r.u_id AND company_id IS NULL;
    UPDATE public.mensagens          SET company_id = _cid WHERE user_id = r.u_id AND company_id IS NULL;
    UPDATE public.crm_cards          SET company_id = _cid WHERE user_id = r.u_id AND company_id IS NULL;
    UPDATE public.contact_pause      SET company_id = _cid WHERE user_id = r.u_id AND company_id IS NULL;
  END LOOP;
END $$;

-- NOT NULL + index
ALTER TABLE public.agent_config       ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.whatsapp_instances ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.mensagens          ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.crm_cards          ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.contact_pause      ALTER COLUMN company_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_agent_config_company       ON public.agent_config(company_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_instances_company ON public.whatsapp_instances(company_id);
CREATE INDEX IF NOT EXISTS idx_mensagens_company          ON public.mensagens(company_id);
CREATE INDEX IF NOT EXISTS idx_crm_cards_company          ON public.crm_cards(company_id);
CREATE INDEX IF NOT EXISTS idx_contact_pause_company      ON public.contact_pause(company_id);

-- agent_config: chave única por company
DO $$ BEGIN
  ALTER TABLE public.agent_config ADD CONSTRAINT agent_config_company_unique UNIQUE (company_id);
EXCEPTION WHEN duplicate_object THEN NULL; WHEN duplicate_table THEN NULL; END $$;

-- whatsapp_instances: única por company
DO $$ BEGIN
  ALTER TABLE public.whatsapp_instances ADD CONSTRAINT whatsapp_instances_company_unique UNIQUE (company_id);
EXCEPTION WHEN duplicate_object THEN NULL; WHEN duplicate_table THEN NULL; END $$;

-- crm_cards: única por (company, numero)
DO $$ BEGIN
  ALTER TABLE public.crm_cards ADD CONSTRAINT crm_cards_company_numero_unique UNIQUE (company_id, numero);
EXCEPTION WHEN duplicate_object THEN NULL; WHEN duplicate_table THEN NULL; END $$;

-- contact_pause: única por (company, numero)
DO $$ BEGIN
  ALTER TABLE public.contact_pause ADD CONSTRAINT contact_pause_company_numero_unique UNIQUE (company_id, numero);
EXCEPTION WHEN duplicate_object THEN NULL; WHEN duplicate_table THEN NULL; END $$;

-- =========================================================
-- REESCREVE RLS: motor → company-based
-- =========================================================
-- agent_config
DROP POLICY IF EXISTS agent_config_own ON public.agent_config;
CREATE POLICY agent_config_access ON public.agent_config FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));

-- whatsapp_instances
DROP POLICY IF EXISTS whatsapp_instances_own ON public.whatsapp_instances;
CREATE POLICY whatsapp_instances_access ON public.whatsapp_instances FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));

-- mensagens
DROP POLICY IF EXISTS mensagens_own ON public.mensagens;
CREATE POLICY mensagens_access ON public.mensagens FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));

-- crm_cards
DROP POLICY IF EXISTS crm_cards_own ON public.crm_cards;
CREATE POLICY crm_cards_access ON public.crm_cards FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));

-- contact_pause
DROP POLICY IF EXISTS contact_pause_own ON public.contact_pause;
CREATE POLICY contact_pause_access ON public.contact_pause FOR ALL TO authenticated
  USING (public.is_super_admin() OR public.has_company_access(company_id))
  WITH CHECK (public.is_super_admin() OR public.has_company_access(company_id));


-- updated_at trigger helper
CREATE OR REPLACE FUNCTION public.tg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

-- AGENT CONFIG (1 por usuário)
CREATE TABLE public.agent_config (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nome_agente text NOT NULL DEFAULT 'Atendente Virtual',
  nome_empresa text NOT NULL DEFAULT '',
  papel_objetivo text NOT NULL DEFAULT 'Atender clientes, tirar dúvidas e ajudar a fechar vendas.',
  estilo_comunicacao text NOT NULL DEFAULT 'Cordial, profissional e objetivo. Usa emojis com moderação.',
  sobre_empresa text NOT NULL DEFAULT '',
  produtos_servicos text NOT NULL DEFAULT '',
  pode_fazer text NOT NULL DEFAULT '',
  nao_pode_fazer text NOT NULL DEFAULT '',
  telefone_transferencia text NOT NULL DEFAULT '',
  palavra_pausar text NOT NULL DEFAULT '/pausar',
  palavra_despausar text NOT NULL DEFAULT '/despausar',
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.agent_config TO authenticated;
GRANT ALL ON public.agent_config TO service_role;
ALTER TABLE public.agent_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "agent_config_own" ON public.agent_config FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE TRIGGER agent_config_updated BEFORE UPDATE ON public.agent_config
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- WHATSAPP INSTANCES (1 por usuário)
CREATE TABLE public.whatsapp_instances (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  instance_name text NOT NULL UNIQUE,
  numero text,
  status text NOT NULL DEFAULT 'disconnected',
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.whatsapp_instances TO authenticated;
GRANT ALL ON public.whatsapp_instances TO service_role;
ALTER TABLE public.whatsapp_instances ENABLE ROW LEVEL SECURITY;
CREATE POLICY "whatsapp_instances_own" ON public.whatsapp_instances FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE TRIGGER whatsapp_instances_updated BEFORE UPDATE ON public.whatsapp_instances
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- MENSAGENS
CREATE TABLE public.mensagens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  numero text NOT NULL,
  contato_nome text,
  direcao text NOT NULL CHECK (direcao IN ('entrada','saida')),
  autor text NOT NULL CHECK (autor IN ('ia','humano','contato')),
  texto text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mensagens TO authenticated;
GRANT ALL ON public.mensagens TO service_role;
ALTER TABLE public.mensagens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "mensagens_own" ON public.mensagens FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE INDEX mensagens_user_created_idx ON public.mensagens (user_id, created_at DESC);
CREATE INDEX mensagens_user_numero_idx ON public.mensagens (user_id, numero, created_at DESC);

-- CRM CARDS
CREATE TABLE public.crm_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  numero text NOT NULL,
  nome text,
  status text NOT NULL DEFAULT 'conversas' CHECK (status IN ('conversas','negociando','ganho','perda')),
  ultima_mensagem text,
  ultima_em timestamptz NOT NULL DEFAULT now(),
  observacao text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, numero)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_cards TO authenticated;
GRANT ALL ON public.crm_cards TO service_role;
ALTER TABLE public.crm_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "crm_cards_own" ON public.crm_cards FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE TRIGGER crm_cards_updated BEFORE UPDATE ON public.crm_cards
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();
CREATE INDEX crm_cards_user_status_idx ON public.crm_cards (user_id, status, ultima_em DESC);

-- realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.crm_cards;
ALTER TABLE public.crm_cards REPLICA IDENTITY FULL;

-- CONTACT PAUSE
CREATE TABLE public.contact_pause (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  numero text NOT NULL,
  pausado boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, numero)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact_pause TO authenticated;
GRANT ALL ON public.contact_pause TO service_role;
ALTER TABLE public.contact_pause ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contact_pause_own" ON public.contact_pause FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE TRIGGER contact_pause_updated BEFORE UPDATE ON public.contact_pause
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

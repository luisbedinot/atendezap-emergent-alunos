ALTER TABLE public.agent_config
  ADD COLUMN IF NOT EXISTS personalidade text DEFAULT 'padrao',
  ADD COLUMN IF NOT EXISTS foco_atendimento text DEFAULT 'ambos',
  ADD COLUMN IF NOT EXISTS emoji_intensidade text DEFAULT 'pouco',
  ADD COLUMN IF NOT EXISTS usar_girias boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS chamar_por_nome boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS perguntar_uma_por_vez boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS pode_brincar boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS assinar_mensagens boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS proatividade integer DEFAULT 50,
  ADD COLUMN IF NOT EXISTS velocidade_resposta text DEFAULT 'humana',
  ADD COLUMN IF NOT EXISTS evitar_palavras text,
  ADD COLUMN IF NOT EXISTS idioma text DEFAULT 'pt-BR';
ALTER TABLE public.agent_config
  ADD COLUMN IF NOT EXISTS segundos_buffer integer NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS responder_em_partes boolean NOT NULL DEFAULT true;

UPDATE public.agent_config SET segundos_buffer = COALESCE(segundos_buffer, 8), responder_em_partes = COALESCE(responder_em_partes, true);
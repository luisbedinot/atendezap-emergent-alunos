
ALTER TABLE public.agent_config
  ADD COLUMN IF NOT EXISTS ai_provider text NOT NULL DEFAULT 'gemini',
  ADD COLUMN IF NOT EXISTS ai_model text NOT NULL DEFAULT 'google/gemini-2.5-flash',
  ADD COLUMN IF NOT EXISTS openai_api_key text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS anthropic_api_key text NOT NULL DEFAULT '';

ALTER TABLE public.agent_config
  DROP CONSTRAINT IF EXISTS agent_config_ai_provider_check;
ALTER TABLE public.agent_config
  ADD CONSTRAINT agent_config_ai_provider_check
  CHECK (ai_provider IN ('gemini','openai','anthropic'));

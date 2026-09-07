ALTER TABLE public.mensagens
  ADD COLUMN IF NOT EXISTS whatsapp_message_id text;

CREATE UNIQUE INDEX IF NOT EXISTS mensagens_company_whatsapp_message_id_idx
  ON public.mensagens(company_id, whatsapp_message_id)
  WHERE whatsapp_message_id IS NOT NULL;

ALTER TABLE public.whatsapp_instances
  ADD COLUMN IF NOT EXISTS webhook_configured_at timestamptz;
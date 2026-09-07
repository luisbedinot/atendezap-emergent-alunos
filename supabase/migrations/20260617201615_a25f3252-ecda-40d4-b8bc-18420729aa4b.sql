ALTER TABLE public.whatsapp_instances
  ADD COLUMN IF NOT EXISTS webhook_token text;

UPDATE public.whatsapp_instances
SET webhook_token = gen_random_uuid()::text
WHERE webhook_token IS NULL;

ALTER TABLE public.whatsapp_instances
  ALTER COLUMN webhook_token SET DEFAULT gen_random_uuid()::text,
  ALTER COLUMN webhook_token SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_instances_webhook_token_idx
  ON public.whatsapp_instances(webhook_token);
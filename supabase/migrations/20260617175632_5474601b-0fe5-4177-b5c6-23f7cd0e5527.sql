
ALTER TABLE public.plan ADD COLUMN IF NOT EXISTS checkout_url text;

ALTER TABLE public.subscription ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'manual';
ALTER TABLE public.subscription ADD COLUMN IF NOT EXISTS external_subscription_id text;
ALTER TABLE public.subscription ADD COLUMN IF NOT EXISTS external_customer_id text;
ALTER TABLE public.subscription ADD COLUMN IF NOT EXISTS buyer_email text;

CREATE INDEX IF NOT EXISTS subscription_provider_external_idx ON public.subscription (provider, external_subscription_id);
CREATE INDEX IF NOT EXISTS subscription_buyer_email_idx ON public.subscription (lower(buyer_email));

CREATE TABLE IF NOT EXISTS public.billing_event_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  event_type text,
  external_id text,
  buyer_email text,
  matched_company_id uuid REFERENCES public.company(id) ON DELETE SET NULL,
  processed boolean NOT NULL DEFAULT false,
  error text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.billing_event_log TO authenticated;
GRANT ALL ON public.billing_event_log TO service_role;

ALTER TABLE public.billing_event_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "billing_event_log super admin read"
  ON public.billing_event_log FOR SELECT
  TO authenticated
  USING (is_super_admin());

CREATE INDEX IF NOT EXISTS billing_event_log_created_idx ON public.billing_event_log (created_at DESC);
CREATE INDEX IF NOT EXISTS billing_event_log_provider_idx ON public.billing_event_log (provider, created_at DESC);

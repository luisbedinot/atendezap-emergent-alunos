-- Applied as the postgres superuser AFTER GoTrue migrations create auth.users
-- and GoTrue's own auth.uid()/auth.role(). Overrides them with claims-aware
-- versions compatible with PostgREST v16 (request.jwt.claims JSON GUC), while
-- staying backward compatible with legacy per-claim GUCs.

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
  LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
  LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
  LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
  LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;

GRANT EXECUTE ON FUNCTION auth.jwt(), auth.uid(), auth.role(), auth.email()
  TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Minimal `realtime` schema stub.
-- The Supabase Realtime SERVICE is NOT provisioned in this environment, but the
-- app migrations declare tenant-scoped RLS on realtime.messages and reference
-- realtime.topic(). We create compatible stubs so migrations apply cleanly and
-- RLS definitions are preserved. Live websocket subscriptions remain INACTIVE.
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS realtime;
GRANT USAGE ON SCHEMA realtime TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS realtime.messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  topic text NOT NULL,
  extension text,
  payload jsonb,
  event text,
  private boolean DEFAULT false,
  inserted_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON realtime.messages TO authenticated, service_role;

CREATE OR REPLACE FUNCTION realtime.topic() RETURNS text
  LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('realtime.topic', true), '')::text
$$;
GRANT EXECUTE ON FUNCTION realtime.topic() TO anon, authenticated, service_role;


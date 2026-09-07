#!/usr/bin/env bash
# Supervised PostgREST (REST/RLS) in the FOREGROUND. Waits for db-init
# (.db-ready) so roles/grants exist before it connects.
set -eu
R=/app/.supabase-runtime; BIN=$R/bin; L=$R/logs; mkdir -p "$L"
READY="$R/.db-ready"

echo "[postgrest] waiting for .db-ready..."
ok=0
for i in $(seq 1 240); do [ -f "$READY" ] && { ok=1; break; }; sleep 1; done
[ "$ok" = "1" ] || { echo "[postgrest] FATAL: db not ready" >&2; exit 1; }

set -a; . "$R/secrets.env"; set +a

export PGRST_DB_URI="postgres://authenticator@127.0.0.1:5432/postgres?sslmode=disable"
export PGRST_DB_SCHEMAS=public
export PGRST_DB_ANON_ROLE=anon
export PGRST_JWT_SECRET="$JWT_SECRET"
export PGRST_DB_USE_LEGACY_GUCS=false
export PGRST_SERVER_HOST=127.0.0.1
export PGRST_SERVER_PORT=3001
export PGRST_DB_POOL=10

echo "[postgrest] starting on 127.0.0.1:3001"
exec "$BIN/postgrest"

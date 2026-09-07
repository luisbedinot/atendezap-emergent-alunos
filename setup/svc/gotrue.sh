#!/usr/bin/env bash
# Supervised GoTrue (Auth) in the FOREGROUND. Waits for db-init to finish
# (.db-ready) before exec'ing so it never starts against an unmigrated DB.
set -eu
R=/app/.supabase-runtime; L=$R/logs; mkdir -p "$L"
READY="$R/.db-ready"

echo "[gotrue] waiting for .db-ready..."
ok=0
for i in $(seq 1 240); do [ -f "$READY" ] && { ok=1; break; }; sleep 1; done
[ "$ok" = "1" ] || { echo "[gotrue] FATAL: db not ready" >&2; exit 1; }

set -a; . "$R/secrets.env"; set +a

# Public URL (best-effort): explicit env, else parse supervisor backend conf.
APP_URL="${APP_URL:-}"
if [ -z "$APP_URL" ]; then
  APP_URL="$(grep -h -m1 'APP_URL="' /etc/supervisor/conf.d/*.conf 2>/dev/null | sed 's/.*APP_URL="\([^"]*\)".*/\1/')"
fi
APP_URL="${APP_URL:-http://localhost:3000}"

export GOTRUE_DB_DRIVER=postgres
export GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin@127.0.0.1:5432/postgres?sslmode=disable&search_path=auth"
export DATABASE_URL="$GOTRUE_DB_DATABASE_URL"
export GOTRUE_DB_MIGRATIONS_PATH="$R/auth/migrations"
export GOTRUE_SITE_URL="$APP_URL"
export GOTRUE_URI_ALLOW_LIST="*"
export GOTRUE_JWT_SECRET="$JWT_SECRET"
export GOTRUE_JWT_EXP=3600
export GOTRUE_JWT_AUD=authenticated
export GOTRUE_JWT_ADMIN_ROLES=service_role
export GOTRUE_JWT_ISSUER="$APP_URL/api/auth/v1"
export GOTRUE_API_HOST=127.0.0.1
export GOTRUE_API_PORT=9999
export GOTRUE_DISABLE_SIGNUP=false
export GOTRUE_MAILER_AUTOCONFIRM=true
export GOTRUE_EXTERNAL_EMAIL_ENABLED=true
export GOTRUE_EXTERNAL_PHONE_ENABLED=false
export GOTRUE_LOG_LEVEL=warn
export API_EXTERNAL_URL="$APP_URL/api/auth/v1"
export GOTRUE_DB_NAMESPACE=auth

echo "[gotrue] starting serve on 127.0.0.1:9999"
exec "$R/auth/auth" serve

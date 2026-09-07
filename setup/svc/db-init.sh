#!/usr/bin/env bash
# One-shot ordered DB init (idempotent). Runs UNDER SUPERVISOR after Postgres:
#   secrets -> wait pg -> bootstrap -> gotrue migrate -> post-bootstrap ->
#   app migrations (once) -> grants -> write .db-ready marker.
# Fail-fast: any step error aborts (set -e) so supervisor marks it FATAL and the
# marker is NOT written -> gotrue/postgrest stay parked (never start half-baked).
set -eu
S=/app/setup; R=/app/.supabase-runtime; PGBIN=/usr/lib/postgresql/15/bin
L=$R/logs; mkdir -p "$L"
READY="$R/.db-ready"
rm -f "$READY"

log(){ echo "[db-init] $*"; }

python3 "$S/gen_keys.py"

log "waiting for postgres on 127.0.0.1:5432..."
ok=0
for i in $(seq 1 120); do
  su postgres -c "$PGBIN/pg_isready -h127.0.0.1 -p5432" >/dev/null 2>&1 && { ok=1; break; }
  sleep 1
done
[ "$ok" = "1" ] || { log "FATAL: postgres not ready"; exit 1; }
log "postgres ready"

su postgres -c "$PGBIN/psql -h127.0.0.1 -Upostgres -d postgres -v ON_ERROR_STOP=1 -f $S/bootstrap.sql"
log "bootstrap applied"

set -a; . "$R/secrets.env"; set +a

# Public URL (best-effort): explicit env, else parse supervisor backend conf.
APP_URL="${APP_URL:-}"
if [ -z "$APP_URL" ]; then
  APP_URL="$(grep -h -m1 'APP_URL="' /etc/supervisor/conf.d/*.conf 2>/dev/null | sed 's/.*APP_URL="\([^"]*\)".*/\1/')"
fi
APP_URL="${APP_URL:-http://localhost:3000}"

export GOTRUE_DB_DRIVER=postgres \
  GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin@127.0.0.1:5432/postgres?sslmode=disable&search_path=auth" \
  GOTRUE_DB_MIGRATIONS_PATH="$R/auth/migrations" GOTRUE_JWT_SECRET="$JWT_SECRET" GOTRUE_DB_NAMESPACE=auth \
  GOTRUE_API_HOST=127.0.0.1 GOTRUE_API_PORT=9999 \
  GOTRUE_SITE_URL="$APP_URL" API_EXTERNAL_URL="$APP_URL/api/auth/v1"
timeout 90 "$R/auth/auth" migrate
log "gotrue migrated"

su postgres -c "$PGBIN/psql -h127.0.0.1 -Upostgres -d postgres -v ON_ERROR_STOP=1 -f $S/post-bootstrap.sql"
log "post-bootstrap applied"

if [ ! -f "$R/.migrations_applied" ]; then
  for f in $(ls /app/supabase/migrations/*.sql | sort); do
    log "migration: $(basename "$f")"
    su postgres -c "$PGBIN/psql -h127.0.0.1 -Upostgres -d postgres -v ON_ERROR_STOP=1 -f $f"
  done
  touch "$R/.migrations_applied"
  log "app migrations applied"
else
  log "app migrations already applied"
fi

su postgres -c "$PGBIN/psql -h127.0.0.1 -Upostgres -d postgres -c \"GRANT USAGE ON SCHEMA public TO anon,authenticated,service_role; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO authenticated; GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role; GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated,service_role; GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated,service_role,anon;\""
log "grants applied"

touch "$READY"
log "done (.db-ready written)"

#!/usr/bin/env bash
# Apply each application migration once, in its own transaction. A failed
# installation can resume without replaying migrations that already succeeded.
set -euo pipefail
R=/app/.supabase-runtime
PGBIN=/usr/lib/postgresql/15/bin
sql() {
  setpriv --reuid=postgres --regid=postgres --init-groups \
    "$PGBIN/psql" -h127.0.0.1 -Upostgres -d postgres -v ON_ERROR_STOP=1 "$@"
}

sql -c 'CREATE SCHEMA IF NOT EXISTS atendezap_setup; CREATE TABLE IF NOT EXISTS atendezap_setup.migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());'

# The previous installer recorded the original 26 migrations with one marker.
# Import that record once when upgrading an existing, completed installation.
if [ -f "$R/.migrations_applied" ]; then
  for f in /app/supabase/migrations/20260[68]*.sql; do
    name="$(basename "$f")"
    [[ "$name" =~ ^[0-9A-Za-z_-]+\.sql$ ]] || exit 1
    sql -c "INSERT INTO atendezap_setup.migrations(name) VALUES ('$name') ON CONFLICT DO NOTHING;" >/dev/null
  done
fi

for f in /app/supabase/migrations/*.sql; do
  name="$(basename "$f")"
  [[ "$name" =~ ^[0-9A-Za-z_-]+\.sql$ ]] || exit 1
  applied="$(sql -Atc "SELECT count(*) FROM atendezap_setup.migrations WHERE name='$name';")"
  [ "$applied" = 1 ] && continue
  echo "[migrations] $name"
  sql --single-transaction -f "$f" \
    -c "INSERT INTO atendezap_setup.migrations(name) VALUES ('$name');"
done
touch "$R/.migrations_applied"

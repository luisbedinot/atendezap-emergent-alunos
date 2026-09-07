#!/usr/bin/env bash
# Supervised Postgres (FOREGROUND, tracked directly by supervisor).
# Idempotent init + stale-pid cleanup. Uses `setpriv` (exec, no fork) so the
# postmaster is supervisor's DIRECT child — a supervisor stop/restart then kills
# the real Postgres (no orphaned postmaster holding a stale postmaster.pid).
set -eu
R=/app/.supabase-runtime; PGBIN=/usr/lib/postgresql/15/bin; PGDATA=$R/pgdata; L=$R/logs
mkdir -p "$L"

# Emergent restores OS packages/accounts after supervisor has already started.
# Wait through that window instead of exhausting supervisor's quick retries
# on `chown: invalid user` while the persisted database is still intact.
echo "[postgres] waiting for the OS account and PostgreSQL runtime..."
runtime_ready=0
for i in $(seq 1 300); do
  if id postgres >/dev/null 2>&1 && getent group postgres >/dev/null 2>&1 && \
     [ -x "$PGBIN/initdb" ] && "$PGBIN/postgres" --version >/dev/null 2>&1; then
    runtime_ready=1
    break
  fi
  sleep 1
done
[ "$runtime_ready" = "1" ] || {
  echo "[postgres] OS runtime not ready after 300s; supervisor will retry." >&2
  exit 1
}

if [ ! -f "$PGDATA/PG_VERSION" ]; then
  mkdir -p "$PGDATA"; chown -R postgres:postgres "$PGDATA" "$L"
  setpriv --reuid=postgres --regid=postgres --init-groups \
    "$PGBIN/initdb" -D "$PGDATA" -U postgres --auth=trust -E UTF8
  printf 'host all all 127.0.0.1/32 trust\nhost all all ::1/128 trust\n' >> "$PGDATA/pg_hba.conf"
fi
chown -R postgres:postgres "$PGDATA" "$L"

# Remove a stale postmaster.pid left by a killed server (only if no live
# postmaster owns it) so a restart is never blocked by a phantom lock file.
if [ -f "$PGDATA/postmaster.pid" ]; then
  p=$(head -1 "$PGDATA/postmaster.pid" 2>/dev/null || true)
  { [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null; } || rm -f "$PGDATA/postmaster.pid"
fi

exec setpriv --reuid=postgres --regid=postgres --init-groups \
  "$PGBIN/postgres" -D "$PGDATA" -c listen_addresses=127.0.0.1 -p 5432 -k /tmp

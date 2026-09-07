#!/usr/bin/env bash
# AtendeZap on Emergent — one-shot idempotent installer for a fresh clone.
# Provisions an isolated, self-hosted Supabase-compatible stack (Postgres +
# GoTrue + PostgREST) MANAGED BY SUPERVISOR (foreground + auto-restart + logs),
# plus Node 22, and wires the app. Generates fresh per-install secrets ONCE
# (idempotent: re-runs never regenerate secrets nor wipe data). Inherits NOTHING
# from any other instance.
#
# FAIL-FAST: mandatory steps abort with a clear error instead of a false success.
set -euo pipefail
SETUP="$(cd "$(dirname "$0")" && pwd)"
RUNTIME=/app/.supabase-runtime
export NODE_BIN="$RUNTIME/node/bin"
mkdir -p "$RUNTIME"

die(){ echo "FATAL: $*" >&2; exit 1; }

echo "== 1/7 system packages (postgres 15) =="
if [ ! -x /usr/lib/postgresql/15/bin/initdb ]; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
fi
# Hard requirement: Postgres 15 binaries must exist after install.
[ -x /usr/lib/postgresql/15/bin/initdb ] || \
  die "Postgres 15 (/usr/lib/postgresql/15/bin/initdb) not found after apt install."

echo "== 2/7 Node 22 runtime =="
bash "$SETUP/install-node.sh"
[ -x "$NODE_BIN/node" ] || die "Node 22 not installed at $NODE_BIN/node."

echo "== 3/7 Supabase binaries (GoTrue + PostgREST) + per-install secrets =="
bash "$SETUP/svc/fetch-bins.sh"
[ -x "$RUNTIME/auth/auth" ]     || die "GoTrue binary missing ($RUNTIME/auth/auth)."
[ -x "$RUNTIME/bin/postgrest" ] || die "PostgREST binary missing ($RUNTIME/bin/postgrest)."
# Idempotent: only creates missing keys; never overwrites existing secrets.
python3 "$SETUP/gen_keys.py"
[ -f "$RUNTIME/secrets.env" ] || die "secrets.env not generated."

echo "== 4/7 supervisor programs (postgres -> db-init -> gotrue -> postgrest) =="
chmod +x "$SETUP/svc/"*.sh
cp "$SETUP/svc/supabase.conf" /etc/supervisor/conf.d/supabase.conf
# Register/refresh ONLY the supabase-* group (backend/frontend untouched).
sudo supervisorctl reread
sudo supervisorctl update supabase-postgres supabase-db-init supabase-gotrue supabase-postgrest
# A script-only update does not recover a previously FATAL/stopped program.
if ! sudo supervisorctl status supabase-postgres | grep -q RUNNING; then
  sudo supervisorctl start supabase-postgres
fi
# On reruns, supervisor does not restart a completed one-shot whose config is
# unchanged. Run db-init again so new migrations are applied without data loss.
if ! sudo supervisorctl status supabase-db-init | grep -q RUNNING; then
  rm -f "$RUNTIME/.db-ready"
  sudo supervisorctl start supabase-db-init
fi
# Wait for the one-shot db-init to finish (it writes .db-ready on success).
echo -n "waiting for database init"
for i in $(seq 1 600); do
  [ -f "$RUNTIME/.db-ready" ] && break
  echo -n "."; sleep 1
done
echo ""
if [ ! -f "$RUNTIME/.db-ready" ]; then
  echo "---- supabase-db-init log ----" >&2
  tail -40 /var/log/supervisor/supabase-db-init.err.log 2>/dev/null >&2 || true
  die "db-init did not complete (no .db-ready). See log above."
fi

# Refresh script/env changes as well as configuration-file changes on reruns.
sudo supervisorctl restart supabase-gotrue supabase-postgrest

echo "== 5/7 environment files (secrets + discovered URL) =="
python3 "$SETUP/write_env.py"
[ -f /app/backend/.env ] && [ -f /app/frontend/.env ] || die "env files not written."

echo "== 6/7 backend deps (pinned, via emergent index) =="
PIP=/root/.venv/bin/pip
[ -x "$PIP" ] || PIP=pip
"$PIP" install -r /app/backend/requirements.txt

echo "== 7/7 frontend deps (Node 22, frozen lockfile) =="
( cd /app/frontend && PATH="$NODE_BIN:$PATH" yarn install --frozen-lockfile )

echo "restarting app services (backend + frontend only)..."
sudo supervisorctl restart backend frontend

echo "verifying health (fail-fast; requires gotrue=200, postgrest=200, frontend HTTP 200)..."
FRONT_URL="$(grep -m1 '^REACT_APP_BACKEND_URL=' /app/frontend/.env | cut -d= -f2- | tr -d '"')"
ok=0
for i in $(seq 1 60); do
  h="$(curl -s http://127.0.0.1:8001/api/health 2>/dev/null || true)"
  fc="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null || echo 000)"
  if echo "$h" | grep -q '"gotrue":200' && echo "$h" | grep -q '"postgrest":200' && [ "$fc" = "200" ]; then
    ok=1; echo "health OK: $h | frontend=$fc"; break
  fi
  sleep 2
done
if [ "$ok" != "1" ]; then
  echo "last gateway health: ${h:-<none>}" >&2
  echo "last frontend HTTP: ${fc:-<none>}" >&2
  die "services did not become healthy (see logs in /var/log/supervisor/)."
fi

echo "DONE. Preview: ${FRONT_URL:-<discovered URL>}"
echo "First user to sign up at /entrar?modo=signup becomes super admin."

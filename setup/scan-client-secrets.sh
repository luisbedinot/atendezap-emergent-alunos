#!/usr/bin/env bash
# Post-build secret scan: build the client and assert that server-only secrets
# (service_role JWT, JWT signing secret, Emergent LLM key, AI proxy secret) do
# NOT appear in the client assets or sourcemaps. Prints only PASS/FAIL — never
# the secret values. The public anon/publishable key is expected and NOT checked.
set -u
RUNTIME=/app/.supabase-runtime
export PATH="$RUNTIME/node/bin:$PATH"
cd /app/frontend

echo "[scan] building client bundle..."
NITRO_PRESET=node-server yarn build >/tmp/vite_build.log 2>&1
BUILD_RC=$?
if [ $BUILD_RC -ne 0 ]; then echo "BUILD: FAIL (see /tmp/vite_build.log)"; tail -15 /tmp/vite_build.log; fi

# Collect candidate client asset dirs (client bundle + sourcemaps).
DIRS=""
for d in .output/public dist/client .tanstack/start/build/client-dist .nitro/dist/public node_modules/.vite; do
  [ -d "$d" ] && DIRS="$DIRS $d"
done
[ -z "$DIRS" ] && DIRS=".output dist .tanstack"

# Load secret values (never printed).
source "$RUNTIME/secrets.env"
declare -A SECRETS=(
  [service_role_key]="$SERVICE_ROLE_KEY"
  [jwt_signing_secret]="$JWT_SECRET"
  [ai_proxy_secret]="$AI_PROXY_SECRET"
)
EMK="$(grep -m1 '^EMERGENT_LLM_KEY=' /app/backend/.env 2>/dev/null | cut -d= -f2-)"
[ -n "${EMK:-}" ] && SECRETS[emergent_llm_key]="$EMK"

FAIL=0
for name in "${!SECRETS[@]}"; do
  val="${SECRETS[$name]}"
  [ -z "$val" ] && { echo "$name: SKIP (unset)"; continue; }
  if grep -rqF -- "$val" $DIRS 2>/dev/null; then
    echo "$name: FAIL (found in client assets)"; FAIL=1
  else
    echo "$name: PASS"
  fi
done
echo "PUBLIC anon/publishable key: not checked (expected public)"
[ $FAIL -eq 0 ] && echo "SECRET-SCAN: PASS" || echo "SECRET-SCAN: FAIL"

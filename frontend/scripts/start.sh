#!/usr/bin/env bash
# Emergent start entrypoint (Node 22 pinned runtime).
# Uses the official-download Node 22 provisioned by /app/setup/install.sh; falls
# back to system node. Runs the explicit TanStack Start + Vite config.
set -e
cd "$(dirname "$0")/.."
NODE_BIN=/app/.supabase-runtime/node/bin
if [ -x "$NODE_BIN/node" ]; then
  export PATH="$NODE_BIN:$PATH"
fi
exec node ./scripts/start.mjs

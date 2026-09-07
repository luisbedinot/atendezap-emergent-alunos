#!/usr/bin/env bash
# Downloads the official Node 22 LTS runtime into the (git-ignored) runtime dir.
# Idempotent. Used for both `yarn install` and `yarn start` (same version).
set -eu
RUNTIME=/app/.supabase-runtime
NODE_VER="${NODE_VER:-v22.13.1}"
DEST="$RUNTIME/node"
case "$(uname -m)" in
  aarch64|arm64) NA=arm64 ;;
  x86_64|amd64)  NA=x64 ;;
  *) NA=x64 ;;
esac
if [ -x "$DEST/bin/node" ]; then
  echo "[node] already present: $("$DEST/bin/node" -v)"; exit 0
fi
mkdir -p "$DEST"
echo "[node] downloading Node ${NODE_VER} (${NA})..."
curl -sL --max-time 240 -o /tmp/node.tar.xz \
  "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${NA}.tar.xz"
tar -xf /tmp/node.tar.xz -C "$DEST" --strip-components=1
echo "[node] installed: $("$DEST/bin/node" -v)"

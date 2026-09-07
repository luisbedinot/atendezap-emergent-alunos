#!/usr/bin/env bash
# Download the pinned GoTrue (auth) + PostgREST binaries into the runtime dir.
# Idempotent: skips whatever already exists. Runtime artifacts are gitignored.
set -eu
R=/app/.supabase-runtime
BIN=$R/bin
mkdir -p "$BIN" "$R/auth"

PGREST_VER="${PGREST_VER:-v16.2}"
GOTRUE_VER="${GOTRUE_VER:-v2.196.0}"
case "$(uname -m)" in
  aarch64|arm64) PGREST_ARCH=aarch64; GOTRUE_ARCH=arm64 ;;
  *)             PGREST_ARCH=x86-64;  GOTRUE_ARCH=amd64 ;;
esac

if [ ! -x "$BIN/postgrest" ]; then
  echo "[fetch-bins] downloading PostgREST ${PGREST_VER} (${PGREST_ARCH})..."
  curl -sL --max-time 180 -o /tmp/pgrst.tar.xz \
    "https://github.com/PostgREST/postgrest/releases/download/${PGREST_VER}/postgrest-${PGREST_VER}-linux-static-${PGREST_ARCH}.tar.xz"
  tar -xf /tmp/pgrst.tar.xz -C "$BIN/"
fi

if [ ! -x "$R/auth/auth" ]; then
  echo "[fetch-bins] downloading GoTrue ${GOTRUE_VER} (${GOTRUE_ARCH})..."
  curl -sL --max-time 180 -o /tmp/auth.tar.gz \
    "https://github.com/supabase/auth/releases/download/${GOTRUE_VER}/auth-${GOTRUE_VER}-${GOTRUE_ARCH}.tar.gz"
  tar -xzf /tmp/auth.tar.gz -C "$R/auth/"
fi
echo "[fetch-bins] ok"

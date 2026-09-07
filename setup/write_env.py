#!/usr/bin/env python3
"""Compose backend/.env and frontend/.env from generated secrets.
Never prints secret values."""
import os

RUNTIME = "/app/.supabase-runtime"
SECRETS = os.path.join(RUNTIME, "secrets.env")
def discover_public_url() -> str:
    # 1) explicit env (backend supervisor sets APP_URL)
    for k in ("APP_URL", "PUBLIC_APP_URL"):
        v = os.environ.get(k, "").strip()
        if v:
            return v.rstrip("/")
    # 2) parse the supervisor backend program env for APP_URL
    import glob, re
    for conf in glob.glob("/etc/supervisor/conf.d/*.conf"):
        try:
            m = re.search(r'APP_URL="([^"]+)"', open(conf).read())
            if m:
                return m.group(1).rstrip("/")
        except OSError:
            pass
    # 3) reuse an existing frontend/.env REACT_APP_BACKEND_URL
    try:
        for line in open("/app/frontend/.env"):
            if line.startswith("REACT_APP_BACKEND_URL="):
                return line.split("=", 1)[1].strip().rstrip("/")
    except OSError:
        pass
    return ""


PUBLIC_URL = discover_public_url()

s = {}
with open(SECRETS) as f:
    for line in f:
        line = line.strip()
        if not line or "=" not in line:
            continue
        k, v = line.split("=", 1)
        s[k] = v

anon = s["ANON_KEY"]
service = s["SERVICE_ROLE_KEY"]
jwt_secret = s["JWT_SECRET"]
ai_proxy_secret = s.get("AI_PROXY_SECRET", "")

# Frontend (.env):
#  - VITE_* keys are injected into the browser bundle; the browser reaches
#    Supabase through the Emergent ingress -> /api -> backend proxy.
#  - The non-VITE SUPABASE_* keys below are read ONLY server-side (SSR /
#    server functions) via loadEnv() in vite.config.ts, which mirrors them
#    into process.env. They are never shipped to the browser. Server-side
#    calls target the backend proxy on loopback to avoid an ingress round-trip.
frontend_env = f"""VITE_SUPABASE_URL={PUBLIC_URL}/api
VITE_SUPABASE_PUBLISHABLE_KEY={anon}
VITE_SUPABASE_PROJECT_ID=atendezap_local
REACT_APP_BACKEND_URL={PUBLIC_URL}
SUPABASE_URL=http://127.0.0.1:8001/api
SUPABASE_PUBLISHABLE_KEY={anon}
SUPABASE_SERVICE_ROLE_KEY={service}
SUPABASE_JWT_SECRET={jwt_secret}
AI_PROXY_SECRET={ai_proxy_secret}
"""
with open("/app/frontend/.env", "w") as f:
    f.write(frontend_env)
os.chmod("/app/frontend/.env", 0o600)

# Backend (.env): server-side Supabase clients + GoTrue/PostgREST config.
backend_env = f"""SUPABASE_URL=http://127.0.0.1:8001/api
SUPABASE_PUBLISHABLE_KEY={anon}
SUPABASE_SERVICE_ROLE_KEY={service}
SUPABASE_JWT_SECRET={jwt_secret}
SUPABASE_ANON_KEY={anon}
GOTRUE_INTERNAL_URL=http://127.0.0.1:9999
POSTGREST_INTERNAL_URL=http://127.0.0.1:3001
PUBLIC_APP_URL={PUBLIC_URL}
AI_PROXY_SECRET={ai_proxy_secret}
"""
# The Emergent Universal Key powers Gemini. It is per-install and injected from
# the environment (never committed). If absent, the AI endpoint reports
# "ai_not_configured" cleanly instead of contacting any external gateway.
emergent_key = os.environ.get("EMERGENT_LLM_KEY", "").strip()
if emergent_key:
    backend_env += f"EMERGENT_LLM_KEY={emergent_key}\n"
with open("/app/backend/.env", "w") as f:
    f.write(backend_env)
os.chmod("/app/backend/.env", 0o600)

print("env files written (values masked)")

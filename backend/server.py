"""
AtendeZap on Emergent — backend gateway.

Responsibilities:
  1. Reverse-proxy the Supabase surface through Emergent's ingress so the browser
     can reach it:
        /api/auth/v1/*  ->  GoTrue    (127.0.0.1:9999)
        /api/rest/v1/*  ->  PostgREST (127.0.0.1:3001)
"""
import os
from contextlib import asynccontextmanager


def _load_env(path: str = "/app/backend/.env"):
    """Load KEY=VALUE lines from backend/.env into os.environ (no external dep)."""
    try:
        with open(path) as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                os.environ.setdefault(key, val)
    except FileNotFoundError:
        pass


_load_env()

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel

GOTRUE = os.environ.get("GOTRUE_INTERNAL_URL", "http://127.0.0.1:9999")
POSTGREST = os.environ.get("POSTGREST_INTERNAL_URL", "http://127.0.0.1:3001")

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
    "content-encoding",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # The Supabase stack (Postgres + GoTrue + PostgREST) is managed by supervisor
    # (see setup/svc/*.sh + setup/svc/supabase.conf), NOT booted here.
    app.state.client = httpx.AsyncClient(timeout=60.0)
    yield
    await app.state.client.aclose()


app = FastAPI(title="AtendeZap Gateway", lifespan=lifespan)


async def _proxy(request: Request, upstream_base: str, upstream_path: str) -> Response:
    url = f"{upstream_base}/{upstream_path}"
    if request.url.query:
        url += f"?{request.url.query}"
    fwd_headers = {k: v for k, v in request.headers.items()
                   if k.lower() not in HOP_BY_HOP}
    body = await request.body()
    client: httpx.AsyncClient = app.state.client
    try:
        upstream = await client.request(
            request.method, url, headers=fwd_headers,
            content=body if body else None,
        )
    except httpx.ConnectError:
        return JSONResponse(
            {"error": "supabase_backend_unavailable",
             "detail": "GoTrue/PostgREST not reachable yet."},
            status_code=503,
        )
    resp_headers = {k: v for k, v in upstream.headers.items()
                    if k.lower() not in HOP_BY_HOP}
    return Response(content=upstream.content, status_code=upstream.status_code,
                    headers=resp_headers,
                    media_type=upstream.headers.get("content-type"))


@app.get("/api/health")
async def health():
    client: httpx.AsyncClient = app.state.client
    out = {"gateway": "ok"}
    try:
        r = await client.get(f"{GOTRUE}/health", timeout=5)
        out["gotrue"] = r.status_code
    except Exception:  # noqa: BLE001
        out["gotrue"] = "down"
    try:
        r = await client.get(f"{POSTGREST}/", timeout=5)
        out["postgrest"] = r.status_code
    except Exception:  # noqa: BLE001
        out["postgrest"] = "down"
    return out


@app.api_route("/api/auth/v1/{path:path}",
               methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy_auth(request: Request, path: str):
    return await _proxy(request, GOTRUE, path)


@app.api_route("/api/rest/v1/{path:path}",
               methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"])
async def proxy_rest(request: Request, path: str):
    return await _proxy(request, POSTGREST, path)


# --------------------------------------------------------------------------
# Gemini via the Emergent Universal Key.
# The frontend is Node/TypeScript, so the Python emergentintegrations library
# runs here and the SSR AI helper (lovable-ai.server.ts) calls this endpoint.
# No Lovable gateway / credits are used. WhatsApp is never contacted here.
# --------------------------------------------------------------------------
class AiChatBody(BaseModel):
    messages: list
    model: str | None = None


@app.post("/api/ai/chat")
async def ai_chat(body: AiChatBody, request: Request):
    # Server->server only: this path is on the public /api ingress and, with a
    # loaded EMERGENT_LLM_KEY, must never allow anonymous spend or let a normal
    # client JWT bypass the per-company credit flow. Only the SSR server (which
    # enforces user/company + credits in its server functions) knows this secret.
    import hmac as _hmac
    expected = os.environ.get("AI_PROXY_SECRET", "")
    provided = request.headers.get("x-ai-proxy-secret", "")
    if not expected or not provided or not _hmac.compare_digest(expected, provided):
        return JSONResponse({"error": "forbidden",
                             "detail": "AI proxy requires the server-side secret."},
                            status_code=403)
    key = os.environ.get("EMERGENT_LLM_KEY")
    if not key:
        return JSONResponse(
            {"error": "ai_not_configured",
             "detail": "EMERGENT_LLM_KEY ausente no backend/.env."},
            status_code=503,
        )
    try:
        from emergentintegrations.llm.chat import LlmChat, UserMessage
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(
            {"error": "ai_lib_missing", "detail": str(exc)}, status_code=503)

    msgs = body.messages or []
    system_parts = [str(m.get("content", "")) for m in msgs if m.get("role") == "system"]
    convo = [m for m in msgs if m.get("role") != "system"]
    system_message = "\n\n".join(p for p in system_parts if p) or "You are a helpful assistant."
    if convo:
        user_text = "\n".join(f"{m.get('role')}: {m.get('content')}" for m in convo)
    else:
        user_text = "Olá"
    model = body.model or "gemini-2.5-flash"
    import uuid
    try:
        chat = LlmChat(api_key=key, session_id=str(uuid.uuid4()),
                       system_message=system_message).with_model("gemini", model)
        resp = await chat.send_message(UserMessage(text=user_text))
    except Exception as exc:  # noqa: BLE001
        detail = str(exc)
        status = 402 if "credit" in detail.lower() or "quota" in detail.lower() else 502
        return JSONResponse({"error": "ai_upstream", "detail": detail}, status_code=status)
    content = resp if isinstance(resp, str) else getattr(resp, "content", str(resp))
    return {"content": content, "model": model, "provider": "gemini"}

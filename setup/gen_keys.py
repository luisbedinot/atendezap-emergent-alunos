#!/usr/bin/env python3
"""Generate per-install secrets (idempotent, additive).
Writes to /app/.supabase-runtime/secrets.env WITHOUT printing values.
Existing values are preserved; only missing keys are added."""
import base64, hmac, hashlib, json, os, secrets, time

RUNTIME = "/app/.supabase-runtime"
SECRETS = os.path.join(RUNTIME, "secrets.env")


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def sign(payload: dict, secret: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    seg = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
          b64url(json.dumps(payload, separators=(",", ":")).encode())
    sig = hmac.new(secret.encode(), seg.encode(), hashlib.sha256).digest()
    return seg + "." + b64url(sig)


def load() -> dict:
    d = {}
    if os.path.exists(SECRETS):
        for line in open(SECRETS):
            line = line.strip()
            if line and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                d[k] = v
    return d


def main():
    os.makedirs(RUNTIME, exist_ok=True)
    s = load()
    changed = False

    if "JWT_SECRET" not in s:
        s["JWT_SECRET"] = secrets.token_urlsafe(48); changed = True
    if "PG_PASSWORD" not in s:
        s["PG_PASSWORD"] = secrets.token_hex(16); changed = True
    # server->server secret guarding the internal AI proxy (/api/ai/chat)
    if "AI_PROXY_SECRET" not in s:
        s["AI_PROXY_SECRET"] = secrets.token_urlsafe(32); changed = True

    # anon/service keys depend on JWT_SECRET; (re)generate if missing
    if "ANON_KEY" not in s or "SERVICE_ROLE_KEY" not in s:
        iat = int(time.time()); exp = iat + 60 * 60 * 24 * 3650
        s["ANON_KEY"] = sign({"role": "anon", "iss": "supabase", "iat": iat, "exp": exp}, s["JWT_SECRET"])
        s["SERVICE_ROLE_KEY"] = sign({"role": "service_role", "iss": "supabase", "iat": iat, "exp": exp}, s["JWT_SECRET"])
        changed = True

    if changed:
        with open(SECRETS, "w") as f:
            for k in ["JWT_SECRET", "ANON_KEY", "SERVICE_ROLE_KEY", "PG_PASSWORD", "AI_PROXY_SECRET"]:
                if k in s:
                    f.write(f"{k}={s[k]}\n")
        os.chmod(SECRETS, 0o600)


if __name__ == "__main__":
    main()

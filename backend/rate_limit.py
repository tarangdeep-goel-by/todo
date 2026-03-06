"""Rate limiting configuration (slowapi)."""
from fastapi import Request
from slowapi import Limiter
from config import get_settings


def _rate_limit_key(request: Request) -> str:
    """Key by Authorization bearer token (one bucket per auth session).

    Falls back to client IP, respecting trusted_proxy_count for
    X-Forwarded-For parsing (prevents spoofing).
    """
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]

    settings = get_settings()
    if settings.trusted_proxy_count > 0:
        xff = request.headers.get("X-Forwarded-For", "")
        if xff:
            parts = [p.strip() for p in xff.split(",")]
            idx = -settings.trusted_proxy_count
            if abs(idx) <= len(parts):
                return parts[idx]

    return request.client.host if request.client else "unknown"


def _get_storage_uri() -> str | None:
    """Return Redis URI for rate limit storage, or None for in-memory."""
    settings = get_settings()
    return settings.redis_url or None


limiter = Limiter(key_func=_rate_limit_key, storage_uri=_get_storage_uri())

"""Rate limiting configuration (slowapi)."""
from fastapi import Request
from slowapi import Limiter
from config import get_settings


def _rate_limit_key(request: Request) -> str:
    """Key by Authorization bearer token (one bucket per auth session)."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]
    return request.client.host if request.client else "unknown"


def _get_storage_uri() -> str | None:
    """Return Redis URI for rate limit storage, or None for in-memory."""
    settings = get_settings()
    return settings.redis_url or None


limiter = Limiter(key_func=_rate_limit_key, storage_uri=_get_storage_uri())

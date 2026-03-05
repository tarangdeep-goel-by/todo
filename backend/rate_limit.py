"""Rate limiting configuration (slowapi)."""
from fastapi import Request
from slowapi import Limiter


def _rate_limit_key(request: Request) -> str:
    """Key by Authorization bearer token (one bucket per auth session)."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        return auth[7:]
    return request.client.host if request.client else "unknown"


limiter = Limiter(key_func=_rate_limit_key)

"""Request logging middleware — logs api.request/api.response with trace IDs."""
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from structured_logging import get_logger, trace_id_var, user_id_var, session_id_var

logger = get_logger(__name__)

# Paths to skip logging
_SKIP_PATHS = {"/health", "/", "/docs", "/redoc", "/openapi.json"}


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path in _SKIP_PATHS:
            return await call_next(request)

        # Extract or generate trace/session IDs
        trace_id = request.headers.get("x-request-id") or str(uuid.uuid4())
        session_id = request.headers.get("x-session-id", "")

        # Set context vars for this request
        trace_id_var.set(trace_id)
        session_id_var.set(session_id)

        logger.info(
            "api.request",
            method=request.method,
            path=request.url.path,
            query=str(request.query_params) if request.query_params else None,
        )

        t0 = time.monotonic()
        try:
            response = await call_next(request)
        except Exception:
            logger.exception("api.error", method=request.method, path=request.url.path)
            raise

        duration_ms = round((time.monotonic() - t0) * 1000, 1)
        logger.info(
            "api.response",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            duration_ms=duration_ms,
        )

        # Echo trace_id back in response header
        response.headers["X-Request-ID"] = trace_id
        return response

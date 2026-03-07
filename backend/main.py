"""Main FastAPI application."""
from structured_logging import setup_logging
from config import get_settings as _get_settings

# Initialize structured logging before any other imports that use logging
_settings_init = _get_settings()
setup_logging(_settings_init.log_level)

# Initialize Sentry before FastAPI app creation (no-op if DSN not set)
if _settings_init.sentry_dsn:
    import sentry_sdk
    sentry_sdk.init(
        dsn=_settings_init.sentry_dsn,
        traces_sample_rate=0.1,
        environment=_settings_init.app_env,
    )

import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from routers import agent, tasks, categories, ramble, logs, notifications, test_utils
from config import get_settings
from rate_limit import limiter
from structured_logging import get_logger

settings = get_settings()
_logger = get_logger(__name__)

PURGE_INTERVAL_HOURS = 24
PURGE_RETENTION_DAYS = 30
NOTIFICATION_CHECK_INTERVAL = settings.notification_check_interval_minutes * 60


async def _purge_archived_loop():
    """Background task: hard-delete archived tasks older than retention period."""
    from database import AsyncSessionLocal
    from services.task_service import TaskService

    while True:
        await asyncio.sleep(PURGE_INTERVAL_HOURS * 3600)
        try:
            async with AsyncSessionLocal() as session:
                svc = TaskService(session)
                count = await svc.purge_old_archived(days=PURGE_RETENTION_DAYS)
                if count:
                    _logger.info("purge.archived", purged_count=count, retention_days=PURGE_RETENTION_DAYS)
        except Exception as e:
            _logger.error("purge.archived.error", error=str(e))


async def _notification_loop():
    """Background task: check for due tasks and send push notifications."""
    from database import AsyncSessionLocal
    from services.notification_service import NotificationService

    while True:
        await asyncio.sleep(NOTIFICATION_CHECK_INTERVAL)
        try:
            async with AsyncSessionLocal() as session:
                svc = NotificationService(session)
                count = await svc.check_and_send_due_reminders()
                if count:
                    _logger.info("notification.cycle_complete", tasks_notified=count)
        except Exception as e:
            _logger.error("notification.cycle_error", error=str(e))


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: start background tasks, clean up on shutdown."""
    purge_task = asyncio.create_task(_purge_archived_loop())
    notification_task = asyncio.create_task(_notification_loop())

    # Warm up connection pool
    from database import AsyncSessionLocal
    from sqlalchemy import text
    try:
        async with AsyncSessionLocal() as session:
            await session.execute(text("SELECT 1"))
        _logger.info("app.pool_warmup", status="ok")
    except Exception as e:
        _logger.warning("app.pool_warmup", status="failed", error=str(e))

    _logger.info("app.startup", purge_interval_hours=PURGE_INTERVAL_HOURS,
                 notification_interval_minutes=settings.notification_check_interval_minutes)
    yield
    purge_task.cancel()
    notification_task.cancel()
    try:
        await purge_task
    except asyncio.CancelledError:
        pass
    try:
        await notification_task
    except asyncio.CancelledError:
        pass
    from database import engine
    get_logger("main").info("app.shutdown")
    await engine.dispose()


# Create FastAPI app
app = FastAPI(
    title="Amble API",
    description="AI-powered voice-first todo list backend",
    version="1.0.0",
    debug=settings.debug,
    docs_url="/docs" if settings.debug else None,
    redoc_url="/redoc" if settings.debug else None,
    lifespan=lifespan,
)


# Security headers middleware
class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        if settings.app_env == "production":
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Reject request bodies larger than 1MB."""
    MAX_BODY_SIZE = 1_048_576  # 1MB

    async def dispatch(self, request: Request, call_next):
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > self.MAX_BODY_SIZE:
            return JSONResponse(status_code=413, content={"detail": "Request body too large"})
        return await call_next(request)


app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestSizeLimitMiddleware)

from middleware.request_logging import RequestLoggingMiddleware
app.add_middleware(RequestLoggingMiddleware)

# HTTPS redirect in production (expects a reverse proxy setting X-Forwarded-Proto)
if settings.app_env == "production":
    app.add_middleware(HTTPSRedirectMiddleware)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID", "X-Session-ID"],
)

# Include routers
app.include_router(agent.router, prefix="/api")
app.include_router(tasks.router, prefix="/api")
app.include_router(categories.router, prefix="/api")
app.include_router(ramble.router)  # No /api prefix — WebSocket at /ws/ramble
app.include_router(logs.router, prefix="/api")
app.include_router(notifications.router, prefix="/api")

# Test utilities (guarded by APP_ENV != production)
if settings.app_env != "production":
    app.include_router(test_utils.router, prefix="/api")

# Prometheus metrics (after routers so all endpoints are instrumented)
from prometheus_fastapi_instrumentator import Instrumentator
Instrumentator(
    excluded_handlers=["/health", "/docs", "/redoc", "/openapi.json", "/metrics"],
).instrument(app).expose(app, endpoint="/metrics")


# Global exception handler — mask details in production
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    from structured_logging import trace_id_var
    tid = trace_id_var.get("")
    try:
        import sentry_sdk
        if tid:
            sentry_sdk.set_tag("trace_id", tid)
    except Exception:
        pass
    if settings.debug:
        return JSONResponse(status_code=500, content={"detail": str(exc)})
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.get("/health")
async def health():
    """Health check endpoint with DB connectivity test."""
    import asyncio
    from sqlalchemy import text
    from database import AsyncSessionLocal
    try:
        async with AsyncSessionLocal() as session:
            await asyncio.wait_for(session.execute(text("SELECT 1")), timeout=2.0)
        return {"status": "healthy", "db": "connected"}
    except Exception as e:
        return JSONResponse(status_code=503, content={"status": "unhealthy", "db": str(e)})


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "Amble API",
        "version": "1.0.0",
    }

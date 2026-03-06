"""Main FastAPI application."""
from structured_logging import setup_logging
from config import get_settings as _get_settings

# Initialize structured logging before any other imports that use logging
setup_logging(_get_settings().log_level)

import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from routers import agent, tasks, categories, ramble
from config import get_settings
from rate_limit import limiter
from structured_logging import get_logger

settings = get_settings()
_logger = get_logger(__name__)

PURGE_INTERVAL_HOURS = 24
PURGE_RETENTION_DAYS = 30


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


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan: start background tasks, clean up on shutdown."""
    purge_task = asyncio.create_task(_purge_archived_loop())
    _logger.info("app.startup", purge_interval_hours=PURGE_INTERVAL_HOURS)
    yield
    purge_task.cancel()
    try:
        await purge_task
    except asyncio.CancelledError:
        pass


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


app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SecurityHeadersMiddleware)

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


# Global exception handler — mask details in production
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    if settings.debug:
        return JSONResponse(status_code=500, content={"detail": str(exc)})
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/")
async def root():
    """Root endpoint."""
    return {
        "message": "Amble API",
        "version": "1.0.0",
    }

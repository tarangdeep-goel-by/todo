"""Structured logging configuration using structlog + contextvars."""
import logging
import os
import sys
from contextvars import ContextVar

import structlog

# Context variables — set per-request by middleware, read by all loggers
trace_id_var: ContextVar[str] = ContextVar("trace_id", default="")
user_id_var: ContextVar[str] = ContextVar("user_id", default="")
session_id_var: ContextVar[str] = ContextVar("session_id", default="")


def _add_context_vars(logger, method_name, event_dict):
    """Inject context vars into every log entry."""
    tid = trace_id_var.get("")
    if tid:
        event_dict["trace_id"] = tid
    uid = user_id_var.get("")
    if uid:
        event_dict["user_id"] = uid
    sid = session_id_var.get("")
    if sid:
        event_dict["session_id"] = sid
    event_dict["source"] = "backend"
    return event_dict


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    """Get a structured logger bound to the given name."""
    return structlog.get_logger(name)


def _sentry_breadcrumb(logger, method_name, event_dict):
    """Send structured log entries to Sentry as breadcrumbs."""
    try:
        import sentry_sdk
        sentry_sdk.add_breadcrumb(
            category="log",
            message=event_dict.get("event", ""),
            level=event_dict.get("level", "info"),
            data={k: v for k, v in event_dict.items() if k not in ("event", "level", "timestamp")},
        )
    except Exception:
        pass
    return event_dict


def setup_logging(log_level: str = "INFO") -> None:
    """Configure structlog + stdlib logging."""
    level = getattr(logging, log_level.upper(), logging.INFO)
    use_json = os.environ.get("LOG_FORMAT", "json") != "console"

    shared_processors = [
        structlog.contextvars.merge_contextvars,
        _add_context_vars,
        _sentry_breadcrumb,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    if use_json:
        renderer = structlog.processors.JSONRenderer()
    else:
        renderer = structlog.dev.ConsoleRenderer()

    structlog.configure(
        processors=[
            *shared_processors,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    formatter = structlog.stdlib.ProcessorFormatter(
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            renderer,
        ],
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)

    # Quiet noisy loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(level)

"""Structured audit logging for security-sensitive operations.

Emits JSON lines to stdout via Python logging. Compatible with log aggregators
(CloudWatch, Datadog, etc.) without requiring a database table.
"""
import json
import logging
from datetime import datetime, timezone
from typing import Any


_audit_logger = logging.getLogger("audit")


def audit_log(event: str, user_id: str, resource_id: str | None = None, **details: Any) -> None:
    """Emit a structured audit log entry."""
    entry = {
        "event": event,
        "user_id": user_id,
        "resource_id": resource_id,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    if details:
        entry["details"] = details
    _audit_logger.info(json.dumps(entry))

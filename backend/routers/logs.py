"""Client log ingestion endpoint."""
from typing import List
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field, field_validator
from auth import get_current_user
from rate_limit import limiter
from structured_logging import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/logs", tags=["logs"])


class ClientLogEntry(BaseModel):
    level: str = "info"
    event: str
    logger_name: str | None = Field(default=None, alias="logger")
    data: dict | None = None
    ts: str | None = None
    trace_id: str | None = None

    @field_validator("event")
    @classmethod
    def truncate_event(cls, v: str) -> str:
        return v[:500] if v else v

    @field_validator("level")
    @classmethod
    def validate_level(cls, v: str) -> str:
        if v.lower() not in ("debug", "info", "warning", "error"):
            return "info"
        return v.lower()


class ClientLogBatch(BaseModel):
    entries: List[ClientLogEntry] = Field(max_length=50)


@router.post("")
@limiter.limit("5/minute")
async def ingest_logs(
    request: Request,
    batch: ClientLogBatch,
    user_id: str = Depends(get_current_user),
):
    """Accept a batch of frontend log entries and forward to structured logging."""
    for entry in batch.entries:
        log_data = {
            "source": "frontend",
            "user_id": user_id,
        }
        if entry.logger_name:
            log_data["logger"] = entry.logger_name
        if entry.trace_id:
            log_data["trace_id"] = entry.trace_id
        if entry.data:
            # Truncate oversized data values
            log_data["data"] = {
                k: (str(v)[:200] if isinstance(v, str) and len(v) > 200 else v)
                for k, v in entry.data.items()
            }
        if entry.ts:
            log_data["client_ts"] = entry.ts

        getattr(logger, entry.level, logger.info)(
            f"client.{entry.event}", **log_data
        )

    return {"accepted": len(batch.entries)}

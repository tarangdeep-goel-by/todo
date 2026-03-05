"""Agent API router."""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db
from auth import get_current_user
from models.schemas import (
    BrainDumpRequest, BrainDumpResponse, BrainDumpSubmitRequest, BrainDumpSubmitResponse,
)
from services.gemini_service import GeminiService
from services.agent_service import AgentService
from config import get_settings
from rate_limit import limiter
from audit import audit_log
from structured_logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/braindump", response_model=BrainDumpResponse)
@limiter.limit("10/minute")
async def process_brain_dump(
    request: Request,
    body: BrainDumpRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> BrainDumpResponse:
    """
    Process a voice brain dump into task proposals.

    Extracts multiple tasks from a voice transcription and returns
    them as proposals for user review — does NOT create tasks yet.
    """
    settings = get_settings()
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    return await agent_service.process_brain_dump(
        transcription=body.transcription,
        user_id=user_id,
        db=db,
        category=body.category,
        parent_id=body.parent_id,
    )


@router.post("/braindump/submit", response_model=BrainDumpSubmitResponse)
@limiter.limit("10/minute")
async def submit_brain_dump(
    request: Request,
    body: BrainDumpSubmitRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> BrainDumpSubmitResponse:
    """
    Commit reviewed brain dump tasks to the database.

    Called after user reviews and edits the task proposals
    returned by /braindump.
    """
    import time
    t0 = time.monotonic()
    logger.info("braindump.submit", task_count=len(body.tasks))
    for i, t in enumerate(body.tasks):
        logger.debug("braindump.submit.task", index=i, action=t.action, matched_task_id=t.matched_task_id)

    settings = get_settings()
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    result = await agent_service.submit_brain_dump(
        user_id=user_id,
        tasks=body.tasks,
        db=db,
    )
    logger.info("braindump.submit.done", duration_ms=round((time.monotonic() - t0) * 1000, 1), success=result.success)
    audit_log("braindump.submitted", user_id, task_count=len(body.tasks),
              actions=[t.action for t in body.tasks])
    return result

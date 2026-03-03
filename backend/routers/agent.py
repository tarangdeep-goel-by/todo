"""Agent API router."""
import logging
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db
from models.schemas import (
    BrainDumpRequest, BrainDumpResponse, BrainDumpSubmitRequest, BrainDumpSubmitResponse,
)
from services.gemini_service import GeminiService
from services.agent_service import AgentService
from config import get_settings

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/braindump", response_model=BrainDumpResponse)
async def process_brain_dump(
    request: BrainDumpRequest,
    db: AsyncSession = Depends(get_db)
) -> BrainDumpResponse:
    """
    Process a voice brain dump into task proposals.

    Extracts multiple tasks from a voice transcription and returns
    them as proposals for user review — does NOT create tasks yet.

    Args:
        request: Contains transcription, user_id, optional category
        db: Database session

    Returns:
        BrainDumpResponse with list of proposed tasks
    """
    settings = get_settings()
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    return await agent_service.process_brain_dump(
        transcription=request.transcription,
        user_id=request.user_id,
        db=db,
        category=request.category,
        parent_id=request.parent_id,
    )


@router.post("/braindump/submit", response_model=BrainDumpSubmitResponse)
async def submit_brain_dump(
    request: BrainDumpSubmitRequest,
    db: AsyncSession = Depends(get_db)
) -> BrainDumpSubmitResponse:
    """
    Commit reviewed brain dump tasks to the database.

    Called after user reviews and edits the task proposals
    returned by /braindump.

    Args:
        request: Contains user_id and list of reviewed task proposals
        db: Database session

    Returns:
        BrainDumpSubmitResponse with created task IDs
    """
    import time
    t0 = time.monotonic()
    logger.info("braindump/submit: %d tasks for user '%s'", len(request.tasks), request.user_id)
    for i, t in enumerate(request.tasks):
        logger.debug("  task[%d]: action=%s content='%s' matched=%s", i, t.action, t.content, t.matched_task_id)

    settings = get_settings()
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    result = await agent_service.submit_brain_dump(
        user_id=request.user_id,
        tasks=request.tasks,
        db=db,
    )
    logger.info("braindump/submit RESPONSE in %.1fms: success=%s", (time.monotonic() - t0) * 1000, result.success)
    return result

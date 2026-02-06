"""Agent API router."""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db
from models.schemas import AgentProcessRequest, AgentResolveRequest, AgentResponse
from services.gemini_service import GeminiService
from services.agent_service import AgentService
from config import get_settings

router = APIRouter(prefix="/agent", tags=["agent"])


@router.post("/process", response_model=AgentResponse)
async def process_voice_command(
    request: AgentProcessRequest,
    db: AsyncSession = Depends(get_db)
) -> AgentResponse:
    """
    Process voice command and execute agent intent.

    This endpoint:
    1. Refines transcription
    2. Builds task tree context
    3. Detects intent with Gemini
    4. Executes the appropriate action
    5. Returns structured response

    Args:
        request: Contains transcription and user_id
        db: Database session

    Returns:
        AgentResponse with success, message, type, and data
    """
    settings = get_settings()

    # Initialize services
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    # Process command
    return await agent_service.process_voice_command(
        transcription=request.transcription,
        user_id=request.user_id,
        db=db
    )


@router.post("/resolve", response_model=AgentResponse)
async def resolve_question(
    request: AgentResolveRequest,
    db: AsyncSession = Depends(get_db)
) -> AgentResponse:
    """Resolve a question response by executing the user's choice."""
    settings = get_settings()
    gemini_service = GeminiService(settings.gemini_api_key)
    agent_service = AgentService(gemini_service)

    return await agent_service.resolve_question(
        user_id=request.user_id,
        selected_task_id=request.selected_task_id,
        action=request.action,
        data=request.data,
        db=db
    )

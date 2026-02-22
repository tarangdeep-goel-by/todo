"""Shared test fixtures for backend tests."""
import os
import sys
import pytest
import pytest_asyncio
from unittest.mock import AsyncMock

# Set env vars before any app imports
os.environ["DATABASE_URL"] = "postgresql+asyncpg://todo:todo123@postgres:5432/todo_test"
os.environ.setdefault("GEMINI_API_KEY", "test-key")

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy import text

from database import Base, get_db
from models.task import Task  # noqa: F401 — registers model on Base
from models.category import Category  # noqa: F401 — registers model on Base
from services.task_service import TaskService
from services.gemini_service import GeminiService
from services.agent_service import AgentService


# ──────────────── Database fixtures ────────────────

TEST_DB_URL = "postgresql+asyncpg://todo:todo123@postgres:5432/todo_test"
ADMIN_DB_URL = "postgresql+asyncpg://todo:todo123@postgres:5432/todo_db"

_db_created = False


@pytest_asyncio.fixture
async def db_engine():
    """Create test database (once) and tables, yield engine."""
    global _db_created
    if not _db_created:
        admin_engine = create_async_engine(ADMIN_DB_URL, isolation_level="AUTOCOMMIT")
        async with admin_engine.connect() as conn:
            await conn.execute(text("DROP DATABASE IF EXISTS todo_test"))
            await conn.execute(text("CREATE DATABASE todo_test"))
        await admin_engine.dispose()
        _db_created = True

    engine = create_async_engine(TEST_DB_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(db_engine):
    """Provide a database session. Cleans up tasks after each test."""
    session_factory = async_sessionmaker(
        db_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        yield session
    # Clean up any committed data after the test
    async with session_factory() as cleanup:
        await cleanup.execute(text("DELETE FROM tasks"))
        await cleanup.execute(text("DELETE FROM categories"))
        await cleanup.commit()


@pytest_asyncio.fixture
async def task_service(db_session):
    """Provide a TaskService wrapping the test session."""
    return TaskService(db_session)


# ──────────────── Gemini mock ────────────────

@pytest.fixture
def mock_gemini():
    """AsyncMock of GeminiService with passthrough refine."""
    mock = AsyncMock(spec=GeminiService)
    mock.refine_transcription = AsyncMock(side_effect=lambda t: t)
    return mock


# ──────────────── Agent service ────────────────

@pytest_asyncio.fixture
async def agent_service(mock_gemini):
    """AgentService with mocked Gemini."""
    return AgentService(mock_gemini)


# ──────────────── HTTP test client ────────────────

@pytest_asyncio.fixture
async def test_client(db_session, mock_gemini):
    """httpx AsyncClient hitting the FastAPI app with overridden deps."""
    from httpx import AsyncClient, ASGITransport
    from main import app

    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test/api") as client:
        yield client

    app.dependency_overrides.clear()

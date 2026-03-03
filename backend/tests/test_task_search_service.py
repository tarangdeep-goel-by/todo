"""Tests for TaskSearchService (pg_trgm trigram search)."""
import pytest
import pytest_asyncio
from tests.helpers import make_task_tree
from services.task_search_service import TaskSearchService
from services.task_service import TaskService

USER_ID = "test-user"


@pytest_asyncio.fixture
async def search_env(db_session, task_service):
    """Create task tree and return (search_service, tasks)."""
    tasks = await make_task_tree(task_service, USER_ID)

    # Add more tasks for richer search testing
    work_cat = tasks["_career_cat"]
    tasks["safe_drop"] = await task_service.create_task(
        user_id=USER_ID, title="safe drop", category="career",
        category_id=work_cat.id, parent_id=None,
        transcription="safe drop",
        ai_placement={"confidence": 0.9, "reasoning": "test"},
    )
    tasks["tech_spec"] = await task_service.create_task(
        user_id=USER_ID, title="tech spec", category="career",
        category_id=work_cat.id, parent_id=tasks["safe_drop"].id,
        transcription="tech spec",
        ai_placement={"confidence": 0.9, "reasoning": "test"},
    )
    tasks["meal_prep"] = await task_service.create_task(
        user_id=USER_ID, title="meal prep for the week", category="home",
        category_id=tasks["_home_cat"].id, parent_id=None,
        transcription="meal prep",
        ai_placement={"confidence": 0.9, "reasoning": "test"},
    )

    search = TaskSearchService(db_session)
    return search, tasks


class TestSearch:
    """Test the search() method."""

    @pytest.mark.asyncio
    async def test_exact_match(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "safe drop")
        assert len(results) > 0
        top_task, top_score = results[0]
        assert top_task.title == "safe drop"
        assert top_score > 0.3

    @pytest.mark.asyncio
    async def test_partial_match(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "tech")
        assert len(results) > 0
        titles = [t.title for t, _ in results]
        assert "tech spec" in titles

    @pytest.mark.asyncio
    async def test_fuzzy_match(self, search_env):
        search, tasks = search_env
        # Slight misspelling
        results = await search.search(USER_ID, "safedrop")
        assert len(results) > 0
        titles = [t.title for t, _ in results]
        assert "safe drop" in titles

    @pytest.mark.asyncio
    async def test_no_match(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "xyznonexistent")
        assert len(results) == 0

    @pytest.mark.asyncio
    async def test_empty_query(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "")
        assert len(results) == 0

    @pytest.mark.asyncio
    async def test_status_filter(self, search_env, task_service):
        search, tasks = search_env
        # Complete a task then search
        await task_service.complete_task(tasks["safe_drop"].id)
        results = await search.search(USER_ID, "safe drop", status_filter="active")
        titles = [t.title for t, _ in results]
        assert "safe drop" not in titles

    @pytest.mark.asyncio
    async def test_limit(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "a", limit=2)
        assert len(results) <= 2

    @pytest.mark.asyncio
    async def test_scores_descending(self, search_env):
        search, tasks = search_env
        results = await search.search(USER_ID, "project")
        if len(results) > 1:
            scores = [s for _, s in results]
            assert scores == sorted(scores, reverse=True)


class TestResolveSingle:
    """Test the resolve_single() method."""

    @pytest.mark.asyncio
    async def test_confident_single_match(self, search_env):
        search, tasks = search_env
        task, candidates = await search.resolve_single(USER_ID, "safe drop")
        assert task is not None
        assert task.title == "safe drop"
        assert candidates == []

    @pytest.mark.asyncio
    async def test_no_match_returns_none(self, search_env):
        search, tasks = search_env
        task, candidates = await search.resolve_single(USER_ID, "xyznonexistent")
        assert task is None
        assert candidates == []

    @pytest.mark.asyncio
    async def test_groceries_match(self, search_env):
        search, tasks = search_env
        task, candidates = await search.resolve_single(USER_ID, "groceries")
        assert task is not None
        assert task.title == "groceries"

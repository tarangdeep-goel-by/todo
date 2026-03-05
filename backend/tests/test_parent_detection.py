"""Tests for implicit parent detection in brain dump pipeline — 5 tests."""
import pytest
from unittest.mock import AsyncMock
from tests.helpers import make_task_tree


class TestImplicitParentDetection:
    """Verify parentQuery from Gemini is resolved to correct parent_id."""

    async def test_for_pattern_resolves_parent(self, agent_service, mock_gemini, task_service, db_session):
        """'write a spec for safedrop' with existing task → parent resolved."""
        tree = await make_task_tree(task_service)
        # Simulate Gemini extracting parentQuery from "for Project Alpha"
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Write a spec", "category": "career", "parentQuery": "Project Alpha", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "write a spec for project alpha", "test-user", db_session,
        )
        assert result.success is True
        assert len(result.tasks) == 1
        assert result.tasks[0].parent_id == tree["project_alpha"].id

    async def test_for_pattern_with_similar_name(self, agent_service, mock_gemini, task_service, db_session):
        """'add tests for login' with existing 'Backend API' → fuzzy match resolves."""
        tree = await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Add integration tests", "category": "career", "parentQuery": "Backend API", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "add integration tests for backend api", "test-user", db_session,
        )
        assert result.success is True
        assert result.tasks[0].parent_id == tree["backend_api"].id

    async def test_no_match_falls_back_to_root(self, agent_service, mock_gemini, task_service, db_session):
        """'buy groceries for dinner' with no 'dinner' task → parent_id is None."""
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Buy groceries for dinner", "category": "home", "parentQuery": "dinner", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "buy groceries for dinner", "test-user", db_session,
        )
        assert result.success is True
        assert len(result.tasks) == 1
        # No task named "dinner" → parentQuery lookup fails gracefully → root level
        assert result.tasks[0].parent_id is None

    async def test_possessive_pattern_resolves_parent(self, agent_service, mock_gemini, task_service, db_session):
        """'implement project alpha's auth' → parentQuery 'Project Alpha' resolved."""
        tree = await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Implement auth module", "category": "career", "parentQuery": "Project Alpha", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "implement project alpha's auth module", "test-user", db_session,
        )
        assert result.success is True
        assert result.tasks[0].parent_id == tree["project_alpha"].id

    async def test_explicit_under_still_works(self, agent_service, mock_gemini, task_service, db_session):
        """Regression: 'add task under Project Alpha' → parentQuery resolved (existing behavior)."""
        tree = await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "New subtask", "category": "career", "parentQuery": "Project Alpha", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "add a new subtask under project alpha", "test-user", db_session,
        )
        assert result.success is True
        assert result.tasks[0].parent_id == tree["project_alpha"].id

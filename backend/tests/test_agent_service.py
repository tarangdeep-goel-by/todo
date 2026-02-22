"""Tests for AgentService handlers (mock Gemini, real DB) — 14 tests."""
import pytest
from unittest.mock import AsyncMock
from tests.helpers import make_task_tree


def _intent(intent, confidence=0.95, **params):
    """Helper to build a Gemini intent response dict."""
    return {"intent": intent, "confidence": confidence, "parameters": params}


class TestProcessRouting:
    async def test_low_confidence_rejection(self, agent_service, mock_gemini, task_service, db_session):
        mock_gemini.detect_intent = AsyncMock(
            return_value=_intent("ADD", confidence=0.3, title="x", category="work")
        )
        result = await agent_service.process_voice_command("something", "test-user", db_session)
        assert result.success is False
        assert "rephras" in result.message.lower()

    async def test_unknown_intent(self, agent_service, mock_gemini, task_service, db_session):
        mock_gemini.detect_intent = AsyncMock(
            return_value=_intent("UNKNOWN", confidence=0.9)
        )
        result = await agent_service.process_voice_command("blah", "test-user", db_session)
        assert result.success is False
        assert result.type == "error"


class TestHandleAdd:
    async def test_add_normal(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "ADD", title="Write tests", category="work",
            suggestedParent=tree["project_alpha"].id, reasoning="testing",
        ))
        result = await agent_service.process_voice_command("write tests", "test-user", db_session)
        assert result.success is True
        assert "Write tests" in result.message

    async def test_add_with_due_date(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "ADD", title="Submit report", category="work",
            suggestedParent=tree["project_alpha"].id, dueDate="tomorrow", reasoning="due soon",
        ))
        result = await agent_service.process_voice_command("submit report tomorrow", "test-user", db_session)
        assert result.success is True

    async def test_add_new_branch_under_limit(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "ADD", title="Practice violin", category="hobbies",
            needsNewBranch=True, suggestedBranchName="Hobbies", reasoning="hobby",
        ))
        result = await agent_service.process_voice_command("practice violin", "test-user", db_session)
        assert result.type == "question"
        assert result.data["action"] == "create_category"

    async def test_add_new_branch_at_limit(self, agent_service, mock_gemini, task_service, db_session):
        """5 categories already exist → reject new branch."""
        for cat in ["work", "personal", "health", "learning", "finance"]:
            await task_service.create_category("test-user", cat)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "ADD", title="Cook dinner", needsNewBranch=True,
            suggestedBranchName="Cooking", reasoning="food",
        ))
        result = await agent_service.process_voice_command("cook dinner", "test-user", db_session)
        assert result.success is False
        assert "maximum" in result.message.lower() or "5" in result.message


class TestHandleComplete:
    async def test_single_match(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "COMPLETE", taskQuery="Backend API",
        ))
        result = await agent_service.process_voice_command("complete backend api", "test-user", db_session)
        assert result.success is True
        assert "Completed" in result.message

    async def test_multiple_matches(self, agent_service, mock_gemini, task_service, db_session):
        await task_service.create_task(
            user_id="test-user", title="Meeting A", category="work", transcription="meeting a",
        )
        await task_service.create_task(
            user_id="test-user", title="Meeting B", category="work", transcription="meeting b",
        )
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "COMPLETE", taskQuery="Meeting",
        ))
        result = await agent_service.process_voice_command("complete meeting", "test-user", db_session)
        assert result.type == "question"

    async def test_no_match(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "COMPLETE", taskQuery="zzz_nonexistent_zzz",
        ))
        result = await agent_service.process_voice_command("complete zzz", "test-user", db_session)
        assert result.success is False


class TestHandleDelete:
    async def test_single_match(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "DELETE", taskQuery="Groceries",
        ))
        result = await agent_service.process_voice_command("delete groceries", "test-user", db_session)
        assert result.success is True
        assert "Deleted" in result.message


class TestHandleEdit:
    async def test_single_match(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "EDIT", taskQuery="Groceries", changes={"title": "Buy groceries"},
        ))
        result = await agent_service.process_voice_command("edit groceries", "test-user", db_session)
        assert result.success is True


class TestHandleMove:
    async def test_move_to_specific_parent(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_intent = AsyncMock(return_value=_intent(
            "MOVE", taskQuery="Groceries", targetParentQuery="Project Alpha",
        ))
        result = await agent_service.process_voice_command("move groceries under project alpha", "test-user", db_session)
        assert result.success is True
        assert "Moved" in result.message

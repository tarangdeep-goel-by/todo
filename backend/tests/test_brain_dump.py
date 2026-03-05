"""Tests for brain dump (voice V2) service + API — 12 tests."""
import pytest
from unittest.mock import AsyncMock, patch
from models.schemas import BrainDumpTaskProposal, BrainDumpResponse, BrainDumpSubmitResponse
from tests.helpers import make_task_tree
from datetime import datetime, timezone


# ──────────────── Service-level tests ────────────────


class TestProcessBrainDump:
    """Tests for AgentService.process_brain_dump()."""

    async def test_single_task(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Buy groceries", "category": "home", "dueDate": "tomorrow", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump("buy groceries tomorrow", "test-user", db_session)
        assert result.success is True
        assert len(result.tasks) == 1
        assert result.tasks[0].content == "Buy groceries"
        assert result.tasks[0].category == "home"
        assert result.tasks[0].due_date is not None

    async def test_multiple_tasks(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Buy milk", "category": "home", "confidence": 0.9},
            {"content": "Call dentist", "category": "home", "dueDate": "tomorrow", "confidence": 0.9},
            {"content": "Finish report", "category": "career", "priority": "high", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "buy milk, call dentist tomorrow, finish the report it's urgent",
            "test-user", db_session,
        )
        assert result.success is True
        assert len(result.tasks) == 3
        assert result.tasks[2].priority == "high"

    async def test_empty_transcription_result(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[])
        result = await agent_service.process_brain_dump("um uh like", "test-user", db_session)
        assert result.success is False
        assert len(result.tasks) == 0
        assert "extract" in result.message.lower() or "rephras" in result.message.lower()

    async def test_invalid_category_falls_back(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Learn guitar", "category": "hobbies", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump("learn guitar", "test-user", db_session)
        assert result.success is True
        assert result.tasks[0].category == "hobbies"  # Kept as-is; category created at submit time

    async def test_category_override(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Task A", "category": "home", "confidence": 0.9},
            {"content": "Task B", "category": "home", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "task a and task b", "test-user", db_session, category="career",
        )
        assert result.success is True
        assert all(t.category == "career" for t in result.tasks)

    async def test_parent_query_resolved(self, agent_service, mock_gemini, task_service, db_session):
        tree = await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Write unit tests", "category": "career", "parentQuery": "Project Alpha", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump(
            "write unit tests under project alpha", "test-user", db_session,
        )
        assert result.success is True
        assert result.tasks[0].parent_id == tree["project_alpha"].id

    async def test_gibberish_returns_empty_proposals(self, agent_service, mock_gemini, task_service, db_session):
        """Gibberish text triggers pre-filter → success=False, empty tasks."""
        await make_task_tree(task_service)
        result = await agent_service.process_brain_dump("xkcd qwrty zxcvbn", "test-user", db_session)
        assert result.success is False
        assert len(result.tasks) == 0
        assert "rephras" in result.message.lower() or "understand" in result.message.lower()
        # Gemini should NOT have been called
        mock_gemini.detect_brain_dump.assert_not_called()

    async def test_normal_text_passes_to_gemini(self, agent_service, mock_gemini, task_service, db_session):
        """Valid text bypasses pre-filter and reaches Gemini."""
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Buy groceries", "category": "home", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump("buy groceries", "test-user", db_session)
        assert result.success is True
        mock_gemini.detect_brain_dump.assert_called_once()

    async def test_skips_empty_content(self, agent_service, mock_gemini, task_service, db_session):
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Real task", "category": "career", "confidence": 0.9},
            {"content": "", "category": "career", "confidence": 0.9},
            {"content": "  ", "category": "career", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump("real task", "test-user", db_session)
        assert result.success is True
        assert len(result.tasks) == 1


class TestSubmitBrainDump:
    """Tests for AgentService.submit_brain_dump() via _execute_action()."""

    async def test_submit_creates_tasks(self, agent_service, task_service, db_session):
        await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", content="Buy milk", category="home",
            ),
            BrainDumpTaskProposal(
                id="temp-2", content="Finish report", category="career",
                priority="high",
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        assert result.created_count == 2
        assert len(result.created_task_ids) == 2

        # Verify tasks exist in DB
        for task_id in result.created_task_ids:
            task = await task_service.get_task(task_id)
            assert task is not None

    async def test_submit_with_due_date_and_parent(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", content="Sub-task", category="career",
                parent_id=tree["project_alpha"].id,
                due_date=datetime(2026, 3, 15, 9, 0, 0, tzinfo=timezone.utc),
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        task = await task_service.get_task(result.created_task_ids[0])
        assert task.parent_id == tree["project_alpha"].id
        assert task.due_date is not None

    async def test_submit_empty_list(self, agent_service, task_service, db_session):
        result = await agent_service.submit_brain_dump("test-user", [], db_session)
        assert result.success is False
        assert result.created_count == 0

    async def test_submit_complete_counts_children(self, agent_service, task_service, db_session):
        """COMPLETE summary should reflect cascaded child count."""
        tree = await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", action="complete", content="Project Alpha",
                category="career", matched_task_id=tree["project_alpha"].id,
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        # Project Alpha has child Backend API → count should be 2
        assert "2" in result.message

    async def test_submit_edit_generic_changes(self, agent_service, task_service, db_session):
        """EDIT should pass through arbitrary changes via **changes."""
        tree = await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", action="edit", content="Backend API",
                category="career", matched_task_id=tree["backend_api"].id,
                changes={"priority": "high", "dueDate": "2026-04-01"},
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        task = await task_service.get_task(tree["backend_api"].id)
        assert task.priority == "high"
        assert task.due_date is not None

    async def test_submit_reparent_validates_target(self, agent_service, task_service, db_session):
        """EDIT with parent_id should fail gracefully if target no longer exists."""
        tree = await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", action="edit", content="Groceries",
                category="home", matched_task_id=tree["groceries"].id,
                changes={"parent_id": "00000000-0000-0000-0000-000000000099"},
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        # Reparent should fail (target doesn't exist), but not crash
        assert result.success is False

    async def test_submit_add_with_tags_and_estimated_hours(self, agent_service, task_service, db_session):
        """ADD should pass through tags and estimated_hours."""
        await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", content="Research APIs", category="career",
                tags=["backend", "research"], estimated_hours=3.5,
                confidence=0.85,
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        task = await task_service.get_task(result.created_task_ids[0])
        assert task.tags == ["backend", "research"]
        assert task.estimated_hours == 3.5

    async def test_submit_add_uses_proposal_confidence(self, agent_service, task_service, db_session):
        """ADD should use proposal.confidence in ai_placement, not hardcoded 0.9."""
        await make_task_tree(task_service)
        proposals = [
            BrainDumpTaskProposal(
                id="temp-1", content="Stretch goal", category="home",
                confidence=0.75,
            ),
        ]
        result = await agent_service.submit_brain_dump("test-user", proposals, db_session)
        assert result.success is True
        task = await task_service.get_task(result.created_task_ids[0])
        assert task.ai_placement_json["confidence"] == 0.75


class TestProcessBrainDumpDisambiguation:
    """Tests for alternate_matches in process_brain_dump()."""

    async def test_alternate_matches_attached(self, agent_service, mock_gemini, task_service, db_session):
        """When fuzzy search returns multiple matches, alternates should be attached."""
        await make_task_tree(task_service)
        # Create a second task with similar name so fuzzy search returns >1
        await task_service.create_task(
            user_id="test-user", title="Backend API v2", category="career",
            transcription="backend api v2",
            ai_placement={"confidence": 0.9, "reasoning": "test"},
        )
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"action": "complete", "content": "Backend API", "category": "career", "confidence": 0.9},
        ])
        result = await agent_service.process_brain_dump("completed backend api", "test-user", db_session)
        assert result.success is True
        assert len(result.tasks) == 1
        proposal = result.tasks[0]
        assert proposal.matched_task_id is not None
        assert proposal.alternate_matches is not None
        assert len(proposal.alternate_matches) >= 1

    async def test_tags_and_estimated_hours_passthrough(self, agent_service, mock_gemini, task_service, db_session):
        """Tags and estimatedHours from Gemini should appear in proposals."""
        await make_task_tree(task_service)
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Design mockups", "category": "career", "confidence": 0.9,
             "tags": ["design", "ui"], "estimatedHours": 4.0},
        ])
        result = await agent_service.process_brain_dump("design mockups", "test-user", db_session)
        assert result.success is True
        proposal = result.tasks[0]
        assert proposal.tags == ["design", "ui"]
        assert proposal.estimated_hours == 4.0


# ──────────────── API-level tests ────────────────


class TestBrainDumpAPI:
    """Tests for /api/agent/braindump endpoints."""

    async def test_braindump_endpoint(self, test_client):
        mock_response = BrainDumpResponse(
            success=True,
            tasks=[BrainDumpTaskProposal(
                id="temp-1", content="Buy groceries", category="home",
            )],
            transcription="buy groceries",
            message="Found 1 tasks",
        )
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.process_brain_dump = AsyncMock(return_value=mock_response)
            response = await test_client.post("/agent/braindump", json={
                "transcription": "buy groceries",
            })
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert len(data["tasks"]) == 1
        assert data["tasks"][0]["content"] == "Buy groceries"

    async def test_braindump_submit_endpoint(self, test_client):
        mock_response = BrainDumpSubmitResponse(
            success=True, created_count=1,
            created_task_ids=["real-id-1"], message="Created 1 tasks",
        )
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.submit_brain_dump = AsyncMock(return_value=mock_response)
            response = await test_client.post("/agent/braindump/submit", json={
                "tasks": [
                    {
                        "id": "temp-1",
                        "content": "Buy milk",
                        "category": "home",
                        "labels": [],
                    },
                ],
            })
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["created_count"] == 1

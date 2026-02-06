"""Tests for /api/agent endpoints — 6 tests."""
import pytest
from unittest.mock import patch, AsyncMock


class TestProcessEndpoint:
    async def test_success(self, test_client):
        mock_response = {
            "success": True, "message": "Created task", "type": "confirmation",
            "data": {"task_id": "t1"},
        }
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.process_voice_command = AsyncMock(
                return_value=type("R", (), mock_response)()
            )
            # Actually we need to return a proper AgentResponse
            from models.schemas import AgentResponse
            instance.process_voice_command = AsyncMock(
                return_value=AgentResponse(**mock_response)
            )
            resp = await test_client.post("/agent/process", json={
                "transcription": "add a task", "user_id": "u1",
            })
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    async def test_validation_error(self, test_client):
        resp = await test_client.post("/agent/process", json={
            "user_id": "u1",
            # missing transcription
        })
        assert resp.status_code == 422


class TestResolveEndpoint:
    async def test_success(self, test_client):
        from models.schemas import AgentResponse
        mock_response = AgentResponse(
            success=True, message="Completed task", type="confirmation",
            data={"task_id": "t1"},
        )
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.resolve_question = AsyncMock(return_value=mock_response)
            resp = await test_client.post("/agent/resolve", json={
                "user_id": "u1", "action": "complete", "selected_task_id": "t1",
            })
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    async def test_complete_action(self, test_client):
        from models.schemas import AgentResponse
        mock_response = AgentResponse(
            success=True, message="Done", type="confirmation",
        )
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.resolve_question = AsyncMock(return_value=mock_response)
            resp = await test_client.post("/agent/resolve", json={
                "user_id": "u1", "action": "complete", "selected_task_id": "abc",
            })
        assert resp.status_code == 200

    async def test_create_category(self, test_client):
        from models.schemas import AgentResponse
        mock_response = AgentResponse(
            success=True, message="Created category", type="confirmation",
        )
        with patch("routers.agent.AgentService") as MockAgent:
            instance = MockAgent.return_value
            instance.resolve_question = AsyncMock(return_value=mock_response)
            resp = await test_client.post("/agent/resolve", json={
                "user_id": "u1", "action": "create_category",
                "data": {"suggested_title": "Violin", "suggested_category": "hobbies"},
            })
        assert resp.status_code == 200

    async def test_validation_error(self, test_client):
        resp = await test_client.post("/agent/resolve", json={
            "user_id": "u1",
            # missing action
        })
        assert resp.status_code == 422

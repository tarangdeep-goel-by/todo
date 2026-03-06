import pytest
from unittest.mock import AsyncMock, patch


class TestBrainDumpPipeline:
    """Journey: brain dump -> review proposals -> submit -> verify results."""

    @pytest.mark.asyncio
    async def test_add_tasks_via_brain_dump(self, e2e, mock_gemini):
        """Extract ADD proposals and submit them."""
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {"content": "Buy groceries", "category": "home", "confidence": 0.95, "priority": "medium"},
            {"content": "Call dentist", "category": "health", "confidence": 0.9, "dueDate": "2026-12-15T00:00:00Z"},
        ])

        with patch("routers.agent.GeminiService") as MockGemini:
            MockGemini.return_value = mock_gemini

            # Step 1: POST /agent/braindump -> proposals
            proposals = await e2e.post(
                "/agent/braindump",
                "Extract ADD proposals",
                json_body={"transcription": "buy groceries and call dentist tomorrow"},
            )
            assert proposals["success"] is True
            assert len(proposals["tasks"]) == 2

            # Step 2: Submit proposals
            result = await e2e.post(
                "/agent/braindump/submit",
                "Submit ADD proposals",
                json_body={"tasks": proposals["tasks"]},
            )
            assert result["success"] is True
            assert result["created_count"] == 2

            # Step 3: Verify tasks exist
            tasks = await e2e.get("/tasks", "Verify tasks created")
            assert tasks["total_count"] == 2

    @pytest.mark.asyncio
    async def test_complete_task_via_brain_dump(self, e2e, mock_gemini):
        """Create a task, then complete it via brain dump."""
        # Step 1: Create a task first
        task = await e2e.post(
            "/tasks",
            "Create task to complete",
            expected_status=201,
            json_body={"title": "Buy milk", "category": "home", "transcription": "buy milk"},
        )
        task_id = task["id"]

        # Configure mock for COMPLETE action
        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {
                "content": "Buy milk",
                "category": "home",
                "action": "complete",
                "matchedTaskId": task_id,
                "confidence": 0.95,
            },
        ])

        with patch("routers.agent.GeminiService") as MockGemini:
            MockGemini.return_value = mock_gemini

            # Step 2: Brain dump with complete intent
            proposals = await e2e.post(
                "/agent/braindump",
                "Extract COMPLETE proposal",
                json_body={"transcription": "I finished buying milk"},
            )
            assert proposals["success"] is True
            # Fix matched_task_id in proposal (AI returns it, we ensure it's correct)
            proposals["tasks"][0]["matched_task_id"] = task_id
            proposals["tasks"][0]["action"] = "complete"

            # Step 3: Submit
            result = await e2e.post(
                "/agent/braindump/submit",
                "Submit COMPLETE",
                json_body={"tasks": proposals["tasks"]},
            )
            assert result["success"] is True

        # Step 4: Verify task is completed
        updated = await e2e.get(f"/tasks/{task_id}", "Verify task completed")
        assert updated["status"] == "completed"

    @pytest.mark.asyncio
    async def test_edit_task_via_brain_dump(self, e2e, mock_gemini):
        """Create a task, then edit it via brain dump."""
        # Step 1: Create task
        task = await e2e.post(
            "/tasks",
            "Create task to edit",
            expected_status=201,
            json_body={"title": "Buy milk", "category": "home", "transcription": "buy milk"},
        )
        task_id = task["id"]

        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {
                "content": "Buy organic milk",
                "category": "home",
                "action": "edit",
                "matchedTaskId": task_id,
                "confidence": 0.9,
                "changes": {"title": "Buy organic milk", "priority": "high"},
            },
        ])

        with patch("routers.agent.GeminiService") as MockGemini:
            MockGemini.return_value = mock_gemini

            proposals = await e2e.post(
                "/agent/braindump",
                "Extract EDIT proposal",
                json_body={"transcription": "change buy milk to buy organic milk and make it high priority"},
            )
            assert proposals["success"] is True
            proposals["tasks"][0]["matched_task_id"] = task_id
            proposals["tasks"][0]["action"] = "edit"
            proposals["tasks"][0]["changes"] = {"title": "Buy organic milk", "priority": "high"}

            result = await e2e.post(
                "/agent/braindump/submit",
                "Submit EDIT",
                json_body={"tasks": proposals["tasks"]},
            )
            assert result["success"] is True

        # Verify edit
        updated = await e2e.get(f"/tasks/{task_id}", "Verify task edited")
        assert updated["title"] == "buy organic milk"  # backend lowercases
        assert updated["priority"] == "high"

    @pytest.mark.asyncio
    async def test_delete_task_via_brain_dump(self, e2e, mock_gemini):
        """Create a task, then delete it via brain dump."""
        task = await e2e.post(
            "/tasks",
            "Create task to delete",
            expected_status=201,
            json_body={"title": "Temp task", "category": "home", "transcription": "temp"},
        )
        task_id = task["id"]

        mock_gemini.detect_brain_dump = AsyncMock(return_value=[
            {
                "content": "Temp task",
                "category": "home",
                "action": "delete",
                "matchedTaskId": task_id,
                "confidence": 0.95,
            },
        ])

        with patch("routers.agent.GeminiService") as MockGemini:
            MockGemini.return_value = mock_gemini

            proposals = await e2e.post(
                "/agent/braindump",
                "Extract DELETE proposal",
                json_body={"transcription": "delete temp task"},
            )
            proposals["tasks"][0]["matched_task_id"] = task_id
            proposals["tasks"][0]["action"] = "delete"

            result = await e2e.post(
                "/agent/braindump/submit",
                "Submit DELETE",
                json_body={"tasks": proposals["tasks"]},
            )
            assert result["success"] is True

        # Verify task is gone (delete action hard-deletes in brain dump)
        await e2e.get(f"/tasks/{task_id}", "Verify task deleted", expected_status=404)

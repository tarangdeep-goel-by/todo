"""E2E test: full task lifecycle."""

import pytest


class TestTaskLifecycle:
    """Journey: create -> edit -> complete -> archive -> restore -> permanent delete."""

    @pytest.mark.asyncio
    async def test_full_lifecycle(self, e2e):
        # Step 1: Create task
        task = await e2e.post(
            "/tasks",
            "Create task",
            expected_status=201,
            json_body={
                "title": "Buy groceries",
                "category": "home",
                "transcription": "Buy groceries for the week",
            },
        )
        task_id = task["id"]
        assert task["title"] == "buy groceries"  # backend lowercases
        assert task["category"] == "home"
        assert task["status"] == "active"

        # Step 2: Get task by ID
        fetched = await e2e.get(f"/tasks/{task_id}", "Get task by ID")
        assert fetched["id"] == task_id
        assert fetched["title"] == "buy groceries"
        assert fetched["category"] == "home"
        assert fetched["status"] == "active"

        # Step 3: Edit title, priority, due_date
        updated = await e2e.patch(
            f"/tasks/{task_id}",
            "Edit task",
            json_body={
                "title": "Buy organic groceries",
                "priority": "high",
                "due_date": "2026-12-31T00:00:00Z",
            },
        )
        assert updated["title"] == "buy organic groceries"
        assert updated["priority"] == "high"
        assert updated["due_date"] is not None

        # Step 4: Get task again to verify edits persisted
        fetched2 = await e2e.get(f"/tasks/{task_id}", "Verify edits persisted")
        assert fetched2["title"] == "buy organic groceries"
        assert fetched2["priority"] == "high"

        # Step 5: Complete task
        completed = await e2e.put(f"/tasks/{task_id}/complete", "Complete task")
        assert completed["status"] == "completed"
        assert completed["completed_at"] is not None

        # Step 6: Archive task
        archive_resp = await e2e.delete(f"/tasks/{task_id}", "Archive task")
        assert archive_resp["success"] is True
        assert archive_resp["archived_count"] == 1

        # Step 7: Verify not in active list
        active_tasks = await e2e.get(
            "/tasks", "Check active list", params={"status": "active"}
        )
        active_ids = [t["id"] for t in active_tasks["tasks"]]
        assert task_id not in active_ids

        # Step 8: Verify in archived list
        archived = await e2e.get("/tasks/archived", "Check archived list")
        archived_ids = [t["id"] for t in archived["tasks"]]
        assert task_id in archived_ids

        # Step 9: Restore task
        restored = await e2e.put(f"/tasks/{task_id}/restore", "Restore task")
        assert restored["status"] == "active"

        # Step 10: Permanent delete
        perm_resp = await e2e.delete(
            f"/tasks/{task_id}/permanent", "Permanent delete"
        )
        assert perm_resp["success"] is True
        assert perm_resp["deleted_count"] == 1

        # Step 11: Get task should 404
        await e2e.get(
            f"/tasks/{task_id}", "Verify gone after permanent delete",
            expected_status=404,
        )

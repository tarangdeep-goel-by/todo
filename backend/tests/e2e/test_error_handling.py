import pytest


class TestErrorHandling:
    """Journey: all error paths (404, 422, 400)."""

    @pytest.mark.asyncio
    async def test_404_on_nonexistent_task(self, e2e):
        fake_id = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        await e2e.get(f"/tasks/{fake_id}", "GET nonexistent task", expected_status=404)
        await e2e.patch(f"/tasks/{fake_id}", "PATCH nonexistent task", expected_status=404,
            json_body={"title": "x"})
        await e2e.put(f"/tasks/{fake_id}/complete", "Complete nonexistent task", expected_status=404)
        await e2e.delete(f"/tasks/{fake_id}", "Delete nonexistent task", expected_status=404)

    @pytest.mark.asyncio
    async def test_422_missing_required_fields(self, e2e):
        # Missing all required fields
        await e2e.post("/tasks", "Create task with no fields", expected_status=422,
            json_body={})

        # Missing transcription
        await e2e.post("/tasks", "Create task without transcription", expected_status=422,
            json_body={"title": "Test", "category": "career"})

        # Missing title
        await e2e.post("/tasks", "Create task without title", expected_status=422,
            json_body={"category": "career", "transcription": "test"})

    @pytest.mark.asyncio
    async def test_422_invalid_values(self, e2e):
        # Title too long (>500 chars)
        await e2e.post("/tasks", "Create task with title >500 chars", expected_status=422,
            json_body={"title": "x" * 501, "category": "career", "transcription": "test"})

        # Empty title
        await e2e.post("/tasks", "Create task with empty title", expected_status=422,
            json_body={"title": "", "category": "career", "transcription": "test"})

        # Invalid priority
        await e2e.post("/tasks", "Create task with invalid priority", expected_status=422,
            json_body={"title": "Test", "category": "career", "transcription": "test",
                       "priority": "critical"})

    @pytest.mark.asyncio
    async def test_400_restore_non_archived_task(self, e2e):
        # Create active task
        task = await e2e.post("/tasks", "Create active task", expected_status=201,
            json_body={"title": "Active", "category": "career", "transcription": "active"})

        # Try restoring active task -> 400
        await e2e.put(f"/tasks/{task['id']}/restore", "Restore non-archived task",
            expected_status=400)

    @pytest.mark.asyncio
    async def test_400_max_categories(self, e2e):
        # Create 8 categories (the max)
        cat_names = ["career", "finance", "health", "relationships",
                     "growth", "recreation", "home", "community"]
        for name in cat_names:
            await e2e.post("/categories", f"Create category '{name}'",
                expected_status=201, json_body={"name": name})

        # 9th should fail
        await e2e.post("/categories", "Create 9th category (should fail)",
            expected_status=400, json_body={"name": "extra"})

    @pytest.mark.asyncio
    async def test_422_category_empty_name(self, e2e):
        await e2e.post("/categories", "Create category with empty name",
            expected_status=422, json_body={"name": ""})

import pytest


class TestBulkOps:
    """Journey: bulk complete/archive operations."""

    @pytest.mark.asyncio
    async def test_bulk_complete(self, e2e):
        # Create 5 tasks
        task_ids = []
        for i in range(5):
            t = await e2e.post("/tasks", f"Create task {i+1}", expected_status=201,
                json_body={"title": f"Bulk task {i+1}", "category": "career", "transcription": f"bt{i+1}"})
            task_ids.append(t["id"])

        # Bulk complete first 3
        result = await e2e.post("/tasks/bulk", "Bulk complete 3 tasks",
            json_body={"task_ids": task_ids[:3], "action": "complete"})
        assert result["affected_count"] == 3
        assert result["errors"] == []

        # Verify 3 completed, 2 still active
        for tid in task_ids[:3]:
            t = await e2e.get(f"/tasks/{tid}", f"Verify {tid} completed")
            assert t["status"] == "completed"
        for tid in task_ids[3:]:
            t = await e2e.get(f"/tasks/{tid}", f"Verify {tid} still active")
            assert t["status"] == "active"

    @pytest.mark.asyncio
    async def test_bulk_archive(self, e2e):
        # Create 2 tasks
        t1 = await e2e.post("/tasks", "Create task 1", expected_status=201,
            json_body={"title": "Archive me 1", "category": "home", "transcription": "a1"})
        t2 = await e2e.post("/tasks", "Create task 2", expected_status=201,
            json_body={"title": "Archive me 2", "category": "home", "transcription": "a2"})

        # Bulk archive
        result = await e2e.post("/tasks/bulk", "Bulk archive 2 tasks",
            json_body={"task_ids": [t1["id"], t2["id"]], "action": "archive"})
        assert result["affected_count"] == 2

        # Verify in archived list
        archived = await e2e.get("/tasks/archived", "Check archived list")
        archived_ids = [t["id"] for t in archived["tasks"]]
        assert t1["id"] in archived_ids
        assert t2["id"] in archived_ids

    @pytest.mark.asyncio
    async def test_bulk_partial_failure(self, e2e):
        # Create 1 valid task
        t = await e2e.post("/tasks", "Create valid task", expected_status=201,
            json_body={"title": "Valid task", "category": "career", "transcription": "v"})

        fake_id = "00000000-0000-0000-0000-000000000099"

        # Bulk complete with mix of valid + invalid
        result = await e2e.post("/tasks/bulk", "Bulk complete mixed IDs",
            json_body={"task_ids": [t["id"], fake_id], "action": "complete"})
        assert result["affected_count"] == 1
        assert len(result["errors"]) == 1

    @pytest.mark.asyncio
    async def test_bulk_empty_list_rejected(self, e2e):
        # Empty task_ids → 422 (Pydantic min_length=1)
        await e2e.post("/tasks/bulk", "Bulk with empty list (should fail)",
            expected_status=422,
            json_body={"task_ids": [], "action": "complete"})

    @pytest.mark.asyncio
    async def test_bulk_oversized_list_rejected(self, e2e):
        # >50 task_ids → 422 (Pydantic max_length=50)
        fake_ids = [f"00000000-0000-0000-0000-{str(i).zfill(12)}" for i in range(51)]
        await e2e.post("/tasks/bulk", "Bulk with 51 IDs (should fail)",
            expected_status=422,
            json_body={"task_ids": fake_ids, "action": "complete"})

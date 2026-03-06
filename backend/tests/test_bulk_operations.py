"""Tests for bulk operations (complete, archive)."""
import pytest
import pytest_asyncio
from tests.helpers import make_task

TEST_USER_ID = "test-user"
OTHER_USER_ID = "other-user"


class TestBulkService:
    """Test bulk operations in TaskService."""

    @pytest.mark.asyncio
    async def test_bulk_complete_multiple_tasks(self, task_service):
        """Bulk complete marks all specified tasks as completed."""
        t1 = await task_service.create_task(**make_task(title="Task 1"))
        t2 = await task_service.create_task(**make_task(title="Task 2"))
        t3 = await task_service.create_task(**make_task(title="Task 3"))

        count, errors = await task_service.bulk_complete(
            [t1.id, t2.id, t3.id], TEST_USER_ID
        )

        assert count == 3
        assert errors == []
        for tid in [t1.id, t2.id, t3.id]:
            t = await task_service.get_task(tid)
            assert t.status == "completed"
            assert t.completed_at is not None

    @pytest.mark.asyncio
    async def test_bulk_archive_multiple_tasks(self, task_service):
        """Bulk archive marks all specified tasks as archived."""
        t1 = await task_service.create_task(**make_task(title="Archive 1"))
        t2 = await task_service.create_task(**make_task(title="Archive 2"))

        count, errors = await task_service.bulk_archive(
            [t1.id, t2.id], TEST_USER_ID
        )

        assert count == 2
        assert errors == []
        for tid in [t1.id, t2.id]:
            t = await task_service.get_task(tid)
            assert t.status == "archived"
            assert t.archived_at is not None

    @pytest.mark.asyncio
    async def test_bulk_partial_failure(self, task_service):
        """One invalid ID doesn't block others from succeeding."""
        t1 = await task_service.create_task(**make_task(title="Valid"))
        fake_id = "00000000-0000-0000-0000-000000000099"

        count, errors = await task_service.bulk_complete(
            [t1.id, fake_id], TEST_USER_ID
        )

        assert count == 1
        assert len(errors) == 1
        assert fake_id in errors[0]
        t = await task_service.get_task(t1.id)
        assert t.status == "completed"

    @pytest.mark.asyncio
    async def test_bulk_validates_ownership(self, task_service):
        """Tasks owned by another user are rejected."""
        t1 = await task_service.create_task(
            **make_task(title="Other's task", user_id=OTHER_USER_ID)
        )

        count, errors = await task_service.bulk_complete(
            [t1.id], TEST_USER_ID
        )

        assert count == 0
        assert len(errors) == 1
        # Task should remain active
        t = await task_service.get_task(t1.id)
        assert t.status == "active"

    @pytest.mark.asyncio
    async def test_bulk_complete_cascades_children(self, task_service):
        """Bulk complete cascades to children of each task."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        child = await task_service.create_task(
            **make_task(title="Child", parent_id=parent.id)
        )

        count, errors = await task_service.bulk_complete(
            [parent.id], TEST_USER_ID
        )

        assert count == 2
        assert errors == []
        for tid in [parent.id, child.id]:
            t = await task_service.get_task(tid)
            assert t.status == "completed"

    @pytest.mark.asyncio
    async def test_bulk_archive_cascades_children(self, task_service):
        """Bulk archive cascades to children of each task."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        child = await task_service.create_task(
            **make_task(title="Child", parent_id=parent.id)
        )

        count, errors = await task_service.bulk_archive(
            [parent.id], TEST_USER_ID
        )

        assert count == 2
        assert errors == []
        for tid in [parent.id, child.id]:
            t = await task_service.get_task(tid)
            assert t.status == "archived"

    @pytest.mark.asyncio
    async def test_bulk_rejects_over_50(self, task_service):
        """Bulk operations reject more than 50 task IDs."""
        ids = [f"00000000-0000-0000-0000-{str(i).zfill(12)}" for i in range(51)]

        with pytest.raises(ValueError, match="50"):
            await task_service.bulk_complete(ids, TEST_USER_ID)


class TestBulkAPI:
    """Test bulk API endpoint."""

    @pytest.mark.asyncio
    async def test_bulk_complete_endpoint(self, test_client, task_service):
        """POST /tasks/bulk with action=complete works."""
        t1 = await task_service.create_task(**make_task(title="Bulk API 1"))
        t2 = await task_service.create_task(**make_task(title="Bulk API 2"))

        resp = await test_client.post("/tasks/bulk", json={
            "task_ids": [t1.id, t2.id],
            "action": "complete",
        })

        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["affected_count"] == 2
        assert data["errors"] == []

    @pytest.mark.asyncio
    async def test_bulk_archive_endpoint(self, test_client, task_service):
        """POST /tasks/bulk with action=archive works."""
        t1 = await task_service.create_task(**make_task(title="Bulk archive"))

        resp = await test_client.post("/tasks/bulk", json={
            "task_ids": [t1.id],
            "action": "archive",
        })

        assert resp.status_code == 200
        data = resp.json()
        assert data["affected_count"] == 1

    @pytest.mark.asyncio
    async def test_bulk_endpoint_rejects_over_50(self, test_client):
        """POST /tasks/bulk rejects >50 task IDs at schema level."""
        ids = [f"00000000-0000-0000-0000-{str(i).zfill(12)}" for i in range(51)]

        resp = await test_client.post("/tasks/bulk", json={
            "task_ids": ids,
            "action": "complete",
        })

        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_bulk_endpoint_partial_failure(self, test_client, task_service):
        """Partial failures return success=true with errors list."""
        t1 = await task_service.create_task(**make_task(title="Good task"))
        fake_id = "00000000-0000-0000-0000-000000000099"

        resp = await test_client.post("/tasks/bulk", json={
            "task_ids": [t1.id, fake_id],
            "action": "complete",
        })

        assert resp.status_code == 200
        data = resp.json()
        assert data["affected_count"] == 1
        assert len(data["errors"]) == 1

"""Tests for archive (soft delete) functionality."""
import pytest
import pytest_asyncio
from datetime import datetime, timezone, timedelta
from sqlalchemy import select, text

from tests.helpers import make_task
from models.task import Task

TEST_USER_ID = "test-user"


class TestArchiveTaskService:
    """Test archive operations in TaskService."""

    @pytest.mark.asyncio
    async def test_archive_sets_status_and_timestamp(self, task_service):
        """Archiving a task sets status='archived' and archived_at."""
        task = await task_service.create_task(**make_task(title="Buy milk"))

        result = await task_service.archive_task_with_children(task.id)

        assert result > 0
        archived = await task_service.get_task(task.id)
        assert archived.status == "archived"
        assert archived.archived_at is not None

    @pytest.mark.asyncio
    async def test_archive_cascades_to_children(self, task_service):
        """Archiving a parent also archives all descendants."""
        parent = await task_service.create_task(**make_task(title="Project"))
        child = await task_service.create_task(**make_task(title="Sub-task", parent_id=parent.id))
        grandchild = await task_service.create_task(**make_task(title="Sub-sub", parent_id=child.id))

        count = await task_service.archive_task_with_children(parent.id)

        assert count == 3
        for tid in [parent.id, child.id, grandchild.id]:
            t = await task_service.get_task(tid)
            assert t.status == "archived"
            assert t.archived_at is not None

    @pytest.mark.asyncio
    async def test_archived_excluded_from_get_tasks(self, task_service):
        """Default get_tasks excludes archived tasks."""
        active = await task_service.create_task(**make_task(title="Active task"))
        to_archive = await task_service.create_task(**make_task(title="Archive me"))
        await task_service.archive_task_with_children(to_archive.id)

        tasks = await task_service.get_tasks(TEST_USER_ID)

        task_ids = [t.id for t in tasks]
        assert active.id in task_ids
        assert to_archive.id not in task_ids

    @pytest.mark.asyncio
    async def test_archived_excluded_from_tree_context(self, task_service):
        """build_full_tree_context excludes archived tasks (Gemini must not see them)."""
        await task_service.create_task(**make_task(title="Visible task"))
        to_archive = await task_service.create_task(**make_task(title="Hidden archived"))
        await task_service.archive_task_with_children(to_archive.id)

        tree = await task_service.build_full_tree_context(TEST_USER_ID)

        assert "visible task" in tree
        assert "hidden archived" not in tree

    @pytest.mark.asyncio
    async def test_archived_excluded_from_search(self, task_service):
        """search_tasks excludes archived tasks."""
        active = await task_service.create_task(**make_task(title="Unique searchable"))
        to_archive = await task_service.create_task(**make_task(title="Unique searchable too"))
        await task_service.archive_task_with_children(to_archive.id)

        results = await task_service.search_tasks(TEST_USER_ID, "unique searchable")

        result_ids = [t.id for t in results]
        assert active.id in result_ids
        assert to_archive.id not in result_ids

    @pytest.mark.asyncio
    async def test_restore_clears_archived_at(self, task_service):
        """Restoring sets status back to active and clears archived_at."""
        task = await task_service.create_task(**make_task(title="Restore me"))
        await task_service.archive_task_with_children(task.id)

        count = await task_service.restore_task_with_children(task.id)

        assert count > 0
        restored = await task_service.get_task(task.id)
        assert restored.status == "active"
        assert restored.archived_at is None

    @pytest.mark.asyncio
    async def test_restore_cascades_matching_timestamp(self, task_service):
        """Restore only unarchives children archived at the same time as parent."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        child = await task_service.create_task(**make_task(title="Child", parent_id=parent.id))

        await task_service.archive_task_with_children(parent.id)

        count = await task_service.restore_task_with_children(parent.id)

        assert count == 2
        for tid in [parent.id, child.id]:
            t = await task_service.get_task(tid)
            assert t.status == "active"
            assert t.archived_at is None

    @pytest.mark.asyncio
    async def test_purge_deletes_old_archived(self, task_service, db_session):
        """purge_old_archived hard-deletes tasks archived > 30 days ago."""
        task = await task_service.create_task(**make_task(title="Old archived"))
        await task_service.archive_task_with_children(task.id)

        # Backdate archived_at to 31 days ago
        old_date = datetime.now(timezone.utc) - timedelta(days=31)
        await db_session.execute(
            text("UPDATE tasks SET archived_at = :dt WHERE id = :id"),
            {"dt": old_date, "id": task.id}
        )
        await db_session.commit()

        purged = await task_service.purge_old_archived(days=30)

        assert purged >= 1
        assert await task_service.get_task(task.id) is None

    @pytest.mark.asyncio
    async def test_purge_keeps_recent_archived(self, task_service):
        """purge_old_archived does NOT delete recently archived tasks."""
        task = await task_service.create_task(**make_task(title="Recent archived"))
        await task_service.archive_task_with_children(task.id)

        purged = await task_service.purge_old_archived(days=30)

        assert purged == 0
        assert await task_service.get_task(task.id) is not None

    @pytest.mark.asyncio
    async def test_permanent_delete_removes_from_db(self, task_service):
        """Hard delete still works for permanent removal."""
        task = await task_service.create_task(**make_task(title="Gone forever"))
        count = await task_service.delete_task_with_children(task.id)

        assert count == 1
        assert await task_service.get_task(task.id) is None

    @pytest.mark.asyncio
    async def test_permanent_delete_cascades_children(self, task_service):
        """Hard delete removes parent and all descendants."""
        parent = await task_service.create_task(**make_task(title="Parent perm"))
        child = await task_service.create_task(**make_task(title="Child perm", parent_id=parent.id))

        count = await task_service.delete_task_with_children(parent.id)

        assert count == 2
        assert await task_service.get_task(parent.id) is None
        assert await task_service.get_task(child.id) is None

    @pytest.mark.asyncio
    async def test_purge_cascades_children(self, task_service, db_session):
        """Purge deletes archived parent AND its archived children."""
        parent = await task_service.create_task(**make_task(title="Old parent"))
        child = await task_service.create_task(**make_task(title="Old child", parent_id=parent.id))
        await task_service.archive_task_with_children(parent.id)

        # Backdate both to 31 days ago
        old_date = datetime.now(timezone.utc) - timedelta(days=31)
        await db_session.execute(
            text("UPDATE tasks SET archived_at = :dt WHERE id IN (:p, :c)"),
            {"dt": old_date, "p": parent.id, "c": child.id}
        )
        await db_session.commit()

        purged = await task_service.purge_old_archived(days=30)

        assert purged == 2
        assert await task_service.get_task(parent.id) is None
        assert await task_service.get_task(child.id) is None


class TestArchiveAPI:
    """Test archive API endpoints."""

    @pytest.mark.asyncio
    async def test_archive_endpoint(self, test_client, task_service):
        """PUT /tasks/{id}/archive archives instead of hard-deleting."""
        task = await task_service.create_task(**make_task(title="API archive"))

        resp = await test_client.put(f"/tasks/{task.id}/archive")

        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["archived_count"] == 1
        archived = await task_service.get_task(task.id)
        assert archived is not None
        assert archived.status == "archived"

    @pytest.mark.asyncio
    async def test_restore_endpoint(self, test_client, task_service):
        """PUT /tasks/{id}/restore un-archives a task."""
        task = await task_service.create_task(**make_task(title="Restore via API"))
        await task_service.archive_task_with_children(task.id)

        resp = await test_client.put(f"/tasks/{task.id}/restore")

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "active"

    @pytest.mark.asyncio
    async def test_archived_endpoint(self, test_client, task_service):
        """GET /tasks/archived returns only archived tasks."""
        active = await task_service.create_task(**make_task(title="Active"))
        to_archive = await task_service.create_task(**make_task(title="Archived one"))
        await task_service.archive_task_with_children(to_archive.id)

        resp = await test_client.get("/tasks/archived")

        assert resp.status_code == 200
        data = resp.json()
        task_ids = [t["id"] for t in data["tasks"]]
        assert to_archive.id in task_ids
        assert active.id not in task_ids

    @pytest.mark.asyncio
    async def test_permanent_delete_endpoint(self, test_client, task_service):
        """DELETE /tasks/{id} hard-deletes from DB."""
        task = await task_service.create_task(**make_task(title="Perm delete"))

        resp = await test_client.delete(f"/tasks/{task.id}")

        assert resp.status_code == 200
        assert await task_service.get_task(task.id) is None

    @pytest.mark.asyncio
    async def test_permanent_delete_endpoint_cascades(self, test_client, task_service):
        """DELETE /tasks/{id} hard-deletes parent and children."""
        parent = await task_service.create_task(**make_task(title="Perm parent"))
        child = await task_service.create_task(**make_task(title="Perm child", parent_id=parent.id))

        resp = await test_client.delete(f"/tasks/{parent.id}")

        assert resp.status_code == 200
        assert resp.json()["deleted_count"] == 2
        assert await task_service.get_task(parent.id) is None
        assert await task_service.get_task(child.id) is None

    @pytest.mark.asyncio
    async def test_get_tasks_excludes_archived(self, test_client, task_service):
        """GET /tasks does not return archived tasks."""
        active = await task_service.create_task(**make_task(title="Visible"))
        to_archive = await task_service.create_task(**make_task(title="Hidden"))
        await task_service.archive_task_with_children(to_archive.id)

        resp = await test_client.get("/tasks")

        assert resp.status_code == 200
        task_ids = [t["id"] for t in resp.json()["tasks"]]
        assert active.id in task_ids
        assert to_archive.id not in task_ids

    @pytest.mark.asyncio
    async def test_stats_exclude_archived(self, test_client, task_service):
        """GET /tasks/stats does not count archived tasks."""
        await task_service.create_task(**make_task(title="Active for stats"))
        to_archive = await task_service.create_task(**make_task(title="Archived for stats"))
        await task_service.archive_task_with_children(to_archive.id)

        resp = await test_client.get("/tasks/stats")

        assert resp.status_code == 200
        stats = resp.json()
        assert stats["total_tasks"] == 1

"""Tests for TaskService (DB integration) — 16 tests."""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from sqlalchemy.exc import OperationalError
from tests.helpers import make_task, make_task_tree

# A valid UUID that won't exist in the DB
MISSING_UUID = "ffffffff-ffff-ffff-ffff-ffffffffffff"


class TestCreateTask:
    async def test_create_minimal(self, task_service):
        task = await task_service.create_task(**make_task())
        assert task.id is not None
        assert task.title == "test task"
        assert task.status == "active"

    async def test_create_all_fields(self, task_service):
        task = await task_service.create_task(**make_task(
            description="Full task",
            priority="high",
            tags=["urgent"],
            estimated_hours=2.5,
        ))
        assert task.description == "Full task"
        assert task.priority == "high"

    async def test_create_custom_id(self, task_service):
        custom_id = "11111111-1111-1111-1111-111111111111"
        task = await task_service.create_task(**make_task(task_id=custom_id))
        assert task.id == custom_id


class TestGetTask:
    async def test_get_exists(self, task_service):
        created = await task_service.create_task(**make_task())
        found = await task_service.get_task(created.id)
        assert found is not None
        assert found.id == created.id

    async def test_get_not_found(self, task_service):
        result = await task_service.get_task(MISSING_UUID)
        assert result is None


class TestGetTasks:
    async def test_get_by_user(self, task_service):
        await task_service.create_task(**make_task(user_id="alice"))
        await task_service.create_task(**make_task(user_id="bob"))
        tasks = await task_service.get_tasks("alice")
        assert len(tasks) == 1

    async def test_filter_by_category(self, task_service):
        await task_service.create_task(**make_task(category="career"))
        await task_service.create_task(**make_task(category="home"))
        tasks = await task_service.get_tasks("test-user", category="career")
        assert all(t.category == "career" for t in tasks)

    async def test_filter_by_status(self, task_service):
        t = await task_service.create_task(**make_task())
        await task_service.complete_task(t.id)
        active = await task_service.get_tasks("test-user", status="active")
        completed = await task_service.get_tasks("test-user", status="completed")
        assert len(active) == 0
        assert len(completed) == 1

    async def test_filter_by_parent(self, task_service):
        tree = await make_task_tree(task_service)
        children = await task_service.get_tasks("test-user", parent_id=tree["project_alpha"].id)
        child_ids = [c.id for c in children]
        assert tree["backend_api"].id in child_ids


class TestUpdateTask:
    async def test_update_title(self, task_service):
        t = await task_service.create_task(**make_task())
        updated = await task_service.update_task(t.id, title="New Title")
        assert updated.title == "new title"

    async def test_update_not_found(self, task_service):
        result = await task_service.update_task(MISSING_UUID, title="x")
        assert result is None


class TestCompleteTask:
    async def test_complete_single(self, task_service):
        t = await task_service.create_task(**make_task())
        completed = await task_service.complete_task(t.id)
        assert completed.status == "completed"
        assert completed.completed_at is not None

    async def test_complete_with_children(self, task_service):
        tree = await make_task_tree(task_service)
        count = await task_service.complete_task_with_children(tree["project_alpha"].id)
        assert count >= 2  # parent + at least 1 child
        child = await task_service.get_task(tree["backend_api"].id)
        assert child.status == "completed"


class TestDeleteWithChildren:
    async def test_delete_with_children(self, task_service):
        tree = await make_task_tree(task_service)
        count = await task_service.delete_task_with_children(tree["project_alpha"].id)
        assert count >= 2
        assert await task_service.get_task(tree["backend_api"].id) is None


class TestBuildTreeContext:
    async def test_build_tree_context(self, task_service):
        await make_task_tree(task_service)
        ctx = await task_service.build_full_tree_context("test-user")
        assert "Career" in ctx or "CAREER" in ctx
        assert "project alpha" in ctx


class TestSearchTasks:
    async def test_search_tasks(self, task_service):
        await make_task_tree(task_service)
        results = await task_service.search_tasks("test-user", "Backend API")
        assert len(results) >= 1
        assert results[0].title == "backend api"


class TestDeleteBatchDelete:
    """Verify delete_task_with_children uses batch delete correctly."""

    async def test_batch_deletes_parent_and_descendants(self, task_service):
        """Parent + 3 descendants → all gone after batch delete."""
        # Create a parent with 3 children
        parent = await task_service.create_task(**make_task(title="Parent"))
        child1 = await task_service.create_task(**make_task(title="Child 1", parent_id=parent.id))
        child2 = await task_service.create_task(**make_task(title="Child 2", parent_id=parent.id))
        grandchild = await task_service.create_task(**make_task(title="Grandchild", parent_id=child1.id))

        count = await task_service.delete_task_with_children(parent.id)

        assert count == 4
        assert await task_service.get_task(parent.id) is None
        assert await task_service.get_task(child1.id) is None
        assert await task_service.get_task(child2.id) is None
        assert await task_service.get_task(grandchild.id) is None

    async def test_delete_leaf_node(self, task_service):
        """Deleting a leaf node (no children) works correctly."""
        leaf = await task_service.create_task(**make_task(title="Leaf"))
        count = await task_service.delete_task_with_children(leaf.id)
        assert count == 1
        assert await task_service.get_task(leaf.id) is None


class TestDeadlockRetry:
    """Test the _with_deadlock_retry helper."""

    async def test_succeeds_on_first_try(self):
        from services.task_service import _with_deadlock_retry

        call_count = 0

        async def factory():
            nonlocal call_count
            call_count += 1
            return "ok"

        result = await _with_deadlock_retry(factory)
        assert result == "ok"
        assert call_count == 1

    async def test_retries_on_deadlock(self):
        from services.task_service import _with_deadlock_retry

        call_count = 0

        async def factory():
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                raise OperationalError("statement", {}, Exception("deadlock detected"))
            return "ok"

        result = await _with_deadlock_retry(factory, base_delay=0.01)
        assert result == "ok"
        assert call_count == 2

    async def test_raises_non_deadlock_error(self):
        from services.task_service import _with_deadlock_retry

        async def factory():
            raise OperationalError("statement", {}, Exception("connection refused"))

        with pytest.raises(OperationalError):
            await _with_deadlock_retry(factory, base_delay=0.01)

    async def test_raises_after_max_retries(self):
        from services.task_service import _with_deadlock_retry

        async def factory():
            raise OperationalError("statement", {}, Exception("deadlock detected"))

        with pytest.raises(OperationalError):
            await _with_deadlock_retry(factory, max_retries=2, base_delay=0.01)

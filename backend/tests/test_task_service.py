"""Tests for TaskService (DB integration) — 16 tests."""
import pytest
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
        await task_service.create_task(**make_task(category="work"))
        await task_service.create_task(**make_task(category="personal"))
        tasks = await task_service.get_tasks("test-user", category="work")
        assert all(t.category == "work" for t in tasks)

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
        assert "Work" in ctx or "WORK" in ctx
        assert "project alpha" in ctx


class TestSearchTasks:
    async def test_search_tasks(self, task_service):
        await make_task_tree(task_service)
        results = await task_service.search_tasks("test-user", "Backend API")
        assert len(results) >= 1
        assert results[0].title == "backend api"

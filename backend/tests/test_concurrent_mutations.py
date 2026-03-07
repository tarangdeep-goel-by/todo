"""Tests for concurrent mutation safety — 4 scenarios."""
import asyncio
import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm.exc import StaleDataError
from sqlalchemy.exc import InvalidRequestError

from services.task_service import TaskService
from tests.helpers import make_task


@pytest_asyncio.fixture
async def session_factory(db_engine):
    """Provide a session factory for creating independent sessions."""
    return async_sessionmaker(
        db_engine, class_=AsyncSession, expire_on_commit=False
    )


@pytest_asyncio.fixture
async def seed_task(task_service):
    """Create a single active task for concurrency tests."""
    return await task_service.create_task(**make_task(title="Concurrent Target"))


@pytest_asyncio.fixture
async def seed_parent_with_children(task_service):
    """Create a parent with two children for tree-operation tests."""
    parent = await task_service.create_task(**make_task(title="Parent Task"))
    child1 = await task_service.create_task(
        **make_task(title="Child 1", parent_id=parent.id)
    )
    child2 = await task_service.create_task(
        **make_task(title="Child 2", parent_id=parent.id)
    )
    return {"parent": parent, "child1": child1, "child2": child2}


class TestConcurrentCompletions:
    """Two concurrent complete_task_with_children on the same task."""

    async def test_concurrent_complete_is_idempotent(
        self, seed_parent_with_children, session_factory
    ):
        """Both calls succeed — completing an already-completed task is a no-op."""
        task_id = seed_parent_with_children["parent"].id

        async def complete_in_session():
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.complete_task_with_children(task_id)

        results = await asyncio.gather(
            complete_in_session(),
            complete_in_session(),
            return_exceptions=True,
        )

        # Neither should raise
        for r in results:
            assert not isinstance(r, Exception), f"Unexpected error: {r}"

        # Verify final state: parent + both children completed
        async with session_factory() as session:
            svc = TaskService(session)
            parent = await svc.get_task(task_id)
            assert parent.status == "completed"
            child1 = await svc.get_task(seed_parent_with_children["child1"].id)
            assert child1.status == "completed"
            child2 = await svc.get_task(seed_parent_with_children["child2"].id)
            assert child2.status == "completed"


class TestConcurrentUpdates:
    """Two concurrent update_task calls with different fields."""

    async def test_concurrent_update_different_fields(
        self, seed_task, session_factory
    ):
        """Last-write-wins for each field; both updates apply without error."""
        task_id = seed_task.id

        async def update_title():
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.update_task(task_id, title="Updated Title")

        async def update_priority():
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.update_task(task_id, priority="high")

        results = await asyncio.gather(
            update_title(),
            update_priority(),
            return_exceptions=True,
        )

        for r in results:
            assert not isinstance(r, Exception), f"Unexpected error: {r}"

        # Verify final state — both fields should reflect their updates
        async with session_factory() as session:
            svc = TaskService(session)
            task = await svc.get_task(task_id)
            assert task is not None
            # Both updates should apply since they touch different columns.
            assert task.title == "updated title", f"Expected 'updated title', got '{task.title}'"
            assert task.priority == "high", f"Expected 'high', got '{task.priority}'"


class TestConcurrentDeleteAndUpdate:
    """One request deletes, another tries to update the same task."""

    async def test_delete_and_update_no_crash(
        self, seed_task, session_factory
    ):
        """One succeeds, the other handles gracefully (no unhandled exception)."""
        task_id = seed_task.id

        async def delete_task():
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.delete_task_with_children(task_id)

        async def update_task():
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.update_task(task_id, title="Race Update")

        results = await asyncio.gather(
            delete_task(),
            update_task(),
            return_exceptions=True,
        )

        # Acceptable outcomes:
        # 1. Both succeed (update ran before delete gathered descendants)
        # 2. Update raises StaleDataError (row deleted mid-update by the other session)
        # Any other exception type is a real failure.
        for r in results:
            if isinstance(r, Exception):
                assert isinstance(r, (StaleDataError, InvalidRequestError, ValueError)), (
                    f"Expected StaleDataError/InvalidRequestError/ValueError or success, got {type(r).__name__}: {r}"
                )

        # Task should be gone after the race
        async with session_factory() as session:
            svc = TaskService(session)
            task = await svc.get_task(task_id)
            # If delete ran, task is None. If update won the race, task may exist.
            assert task is None or task.title == "race update"


class TestConcurrentBulkComplete:
    """Two bulk_complete calls with overlapping task IDs."""

    async def test_overlapping_bulk_complete(
        self, seed_parent_with_children, session_factory
    ):
        """All tasks end up completed, no double-counting errors."""
        parent_id = seed_parent_with_children["parent"].id
        child1_id = seed_parent_with_children["child1"].id
        child2_id = seed_parent_with_children["child2"].id

        # Overlapping sets: both include child1
        set_a = [parent_id, child1_id]
        set_b = [child1_id, child2_id]

        async def bulk_complete_set(task_ids):
            async with session_factory() as session:
                svc = TaskService(session)
                return await svc.bulk_complete(task_ids, user_id="test-user")

        results = await asyncio.gather(
            bulk_complete_set(set_a),
            bulk_complete_set(set_b),
            return_exceptions=True,
        )

        for r in results:
            assert not isinstance(r, Exception), f"Unexpected error: {r}"

        # Verify all three tasks are completed
        async with session_factory() as session:
            svc = TaskService(session)
            for tid in [parent_id, child1_id, child2_id]:
                task = await svc.get_task(tid)
                assert task.status == "completed", (
                    f"Task {tid} should be completed, got {task.status}"
                )

        # No errors in either result
        for r in results:
            _affected, errors = r
            assert len(errors) == 0, f"Unexpected errors: {errors}"

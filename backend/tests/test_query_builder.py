"""Tests for QueryBuilder via TaskService.get_tasks_advanced() — 18 tests."""
import pytest
from datetime import datetime, timezone, timedelta
from models.schemas import TaskFilterParams
from tests.helpers import make_task


class TestFilterByCategory:
    async def test_single_category(self, task_service, db_session):
        await task_service.create_task(**make_task(title="Work A", category="career"))
        await task_service.create_task(**make_task(title="Personal A", category="home"))
        params = TaskFilterParams(user_id="test-user", category="career")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "work a"

    async def test_multi_category(self, task_service, db_session):
        await task_service.create_task(**make_task(title="Work A", category="career"))
        await task_service.create_task(**make_task(title="Personal A", category="home"))
        await task_service.create_task(**make_task(title="Health A", category="health"))
        params = TaskFilterParams(user_id="test-user", category="career,home")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 2


class TestFilterByPriority:
    async def test_single_priority(self, task_service, db_session):
        await task_service.create_task(**make_task(title="High", priority="high"))
        await task_service.create_task(**make_task(title="Low", priority="low"))
        params = TaskFilterParams(user_id="test-user", priority="high")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "high"

    async def test_multi_priority(self, task_service, db_session):
        await task_service.create_task(**make_task(title="High", priority="high"))
        await task_service.create_task(**make_task(title="Medium", priority="medium"))
        await task_service.create_task(**make_task(title="Low", priority="low"))
        params = TaskFilterParams(user_id="test-user", priority="high,medium")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 2


class TestFilterByStatus:
    async def test_active(self, task_service, db_session):
        await task_service.create_task(**make_task(title="Active"))
        done = await task_service.create_task(**make_task(title="Done"))
        await task_service.complete_task(done.id)
        params = TaskFilterParams(user_id="test-user", status="active")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "active"

    async def test_overdue_computed(self, task_service, db_session):
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        tomorrow = datetime.now(timezone.utc) + timedelta(days=1)
        await task_service.create_task(**make_task(title="Overdue", due_date=yesterday))
        await task_service.create_task(**make_task(title="Future", due_date=tomorrow))
        params = TaskFilterParams(user_id="test-user", status="overdue")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "overdue"

    async def test_multi_status(self, task_service, db_session):
        await task_service.create_task(**make_task(title="Active"))
        t2 = await task_service.create_task(**make_task(title="Done"))
        await task_service.complete_task(t2.id)
        params = TaskFilterParams(user_id="test-user", status="active,completed")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 2


class TestFilterByParentId:
    async def test_top_level_null(self, task_service, db_session):
        parent = await task_service.create_task(**make_task(title="Parent"))
        await task_service.create_task(**make_task(title="Child", parent_id=parent.id))
        params = TaskFilterParams(user_id="test-user", parent_id="null")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "parent"

    async def test_specific_parent(self, task_service, db_session):
        parent = await task_service.create_task(**make_task(title="Parent"))
        await task_service.create_task(**make_task(title="Child A", parent_id=parent.id))
        await task_service.create_task(**make_task(title="Child B", parent_id=parent.id))
        params = TaskFilterParams(user_id="test-user", parent_id=parent.id)
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 2


class TestFilterByTags:
    async def test_tasks_created_with_tags(self, task_service, db_session):
        """Tags are stored correctly even if array filter uses dialect-specific ops."""
        t = await task_service.create_task(**make_task(title="Tagged", tags=["urgent", "review"]))
        fetched = await task_service.get_task(t.id)
        assert fetched.tags == ["urgent", "review"]


class TestFilterByDateRange:
    async def test_created_at_range(self, task_service, db_session):
        await task_service.create_task(**make_task(title="T1"))
        now = datetime.now(timezone.utc)
        params = TaskFilterParams(
            user_id="test-user",
            created_at_gte=now - timedelta(minutes=5),
            created_at_lte=now + timedelta(minutes=5),
        )
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1

    async def test_due_date_range(self, task_service, db_session):
        tomorrow = datetime.now(timezone.utc) + timedelta(days=1)
        next_week = datetime.now(timezone.utc) + timedelta(days=7)
        await task_service.create_task(**make_task(title="Soon", due_date=tomorrow))
        await task_service.create_task(**make_task(title="Later", due_date=next_week))
        params = TaskFilterParams(
            user_id="test-user",
            due_date_gte=datetime.now(timezone.utc),
            due_date_lte=datetime.now(timezone.utc) + timedelta(days=2),
        )
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 1
        assert tasks[0].title == "soon"


class TestSorting:
    async def test_due_date_desc(self, task_service, db_session):
        d1 = datetime.now(timezone.utc) + timedelta(days=1)
        d2 = datetime.now(timezone.utc) + timedelta(days=5)
        await task_service.create_task(**make_task(title="Soon", due_date=d1))
        await task_service.create_task(**make_task(title="Later", due_date=d2))
        params = TaskFilterParams(user_id="test-user", sort="due_date:desc")
        tasks, _ = await task_service.get_tasks_advanced(params)
        assert tasks[0].title == "later"
        assert tasks[1].title == "soon"

    async def test_priority_desc(self, task_service, db_session):
        await task_service.create_task(**make_task(title="Low", priority="low"))
        await task_service.create_task(**make_task(title="High", priority="high"))
        params = TaskFilterParams(user_id="test-user", sort="priority:desc")
        tasks, _ = await task_service.get_tasks_advanced(params)
        assert tasks[0].title == "high"

    async def test_default_sort_order(self, task_service, db_session):
        """Default: status:asc, due_date:asc, priority:desc, created_at:desc."""
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        tomorrow = datetime.now(timezone.utc) + timedelta(days=1)
        await task_service.create_task(**make_task(title="Overdue", due_date=yesterday, priority="low"))
        await task_service.create_task(**make_task(title="Active High", due_date=tomorrow, priority="high"))
        params = TaskFilterParams(user_id="test-user")
        tasks, _ = await task_service.get_tasks_advanced(params)
        # Overdue (status rank 0) should come before active (rank 1)
        assert tasks[0].title == "overdue"


class TestPagination:
    async def test_limit_offset(self, task_service, db_session):
        for i in range(5):
            await task_service.create_task(**make_task(title=f"Task {i}", category="career"))
        params = TaskFilterParams(user_id="test-user", limit=2, offset=0, sort="title:asc")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert len(tasks) == 2
        assert count == 5

    async def test_count_matches_total(self, task_service, db_session):
        for i in range(3):
            await task_service.create_task(**make_task(title=f"Work {i}", category="career"))
        await task_service.create_task(**make_task(title="Personal", category="home"))
        params = TaskFilterParams(user_id="test-user", category="career")
        tasks, count = await task_service.get_tasks_advanced(params)
        assert count == 3
        assert len(tasks) == 3

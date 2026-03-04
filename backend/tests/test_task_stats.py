"""Tests for GET /api/tasks/stats endpoint and TaskService.get_task_stats — 12 tests."""
import pytest
from datetime import datetime, timezone, timedelta
from tests.helpers import make_task


# ──────────────── Service-level tests ────────────────


class TestTaskStatsEmpty:
    async def test_empty_user_returns_zeros(self, task_service):
        stats = await task_service.get_task_stats("nonexistent-user")
        assert stats.total_tasks == 0
        assert stats.by_status == {"active": 0, "completed": 0, "overdue": 0}
        assert stats.by_priority == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert stats.by_category == []
        assert stats.due_soon_count == 0


class TestTaskStatsByStatus:
    async def test_active_and_completed_counts(self, task_service):
        t1 = await task_service.create_task(**make_task(title="Active 1"))
        t2 = await task_service.create_task(**make_task(title="Active 2"))
        t3 = await task_service.create_task(**make_task(title="Done"))
        await task_service.complete_task(t3.id)

        stats = await task_service.get_task_stats("test-user")
        assert stats.total_tasks == 3
        assert stats.by_status["active"] == 2
        assert stats.by_status["completed"] == 1

    async def test_overdue_counted_correctly(self, task_service):
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        # Active + past due = overdue
        await task_service.create_task(**make_task(
            title="Overdue task", due_date=yesterday,
        ))
        # Active + no due date = not overdue
        await task_service.create_task(**make_task(title="Normal active"))

        stats = await task_service.get_task_stats("test-user")
        assert stats.by_status["overdue"] == 1
        assert stats.by_status["active"] == 1  # only the non-overdue active

    async def test_completed_past_due_not_overdue(self, task_service):
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        t = await task_service.create_task(**make_task(
            title="Completed past due", due_date=yesterday,
        ))
        await task_service.complete_task(t.id)

        stats = await task_service.get_task_stats("test-user")
        assert stats.by_status["overdue"] == 0
        assert stats.by_status["completed"] == 1


class TestTaskStatsDueSoon:
    async def test_due_soon_counted_correctly(self, task_service):
        in_24h = datetime.now(timezone.utc) + timedelta(hours=24)
        in_47h = datetime.now(timezone.utc) + timedelta(hours=47)
        in_72h = datetime.now(timezone.utc) + timedelta(hours=72)

        await task_service.create_task(**make_task(title="Due 24h", due_date=in_24h))
        await task_service.create_task(**make_task(title="Due 47h", due_date=in_47h))
        await task_service.create_task(**make_task(title="Due 72h", due_date=in_72h))

        stats = await task_service.get_task_stats("test-user")
        assert stats.due_soon_count == 2  # 24h and 47h are within 48h

    async def test_due_soon_excludes_overdue(self, task_service):
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        in_24h = datetime.now(timezone.utc) + timedelta(hours=24)

        await task_service.create_task(**make_task(title="Overdue", due_date=yesterday))
        await task_service.create_task(**make_task(title="Soon", due_date=in_24h))

        stats = await task_service.get_task_stats("test-user")
        assert stats.due_soon_count == 1  # only "Soon", not the overdue one
        assert stats.by_status["overdue"] == 1


class TestTaskStatsByPriority:
    async def test_by_priority_breakdown(self, task_service):
        await task_service.create_task(**make_task(title="High", priority="high"))
        await task_service.create_task(**make_task(title="Med", priority="medium"))
        await task_service.create_task(**make_task(title="Low", priority="low"))
        await task_service.create_task(**make_task(title="None1"))  # no priority
        await task_service.create_task(**make_task(title="None2"))  # no priority

        stats = await task_service.get_task_stats("test-user")
        assert stats.by_priority["high"] == 1
        assert stats.by_priority["medium"] == 1
        assert stats.by_priority["low"] == 1
        assert stats.by_priority["none"] == 2


class TestTaskStatsByCategory:
    async def test_by_category_breakdown(self, task_service):
        # Create categories and tasks
        career_cat = await task_service.create_category("test-user", "career")
        home_cat = await task_service.create_category("test-user", "home")

        yesterday = datetime.now(timezone.utc) - timedelta(days=1)

        await task_service.create_task(**make_task(
            title="Career 1", category="career", category_id=career_cat.id,
        ))
        await task_service.create_task(**make_task(
            title="Career 2 overdue", category="career", category_id=career_cat.id,
            due_date=yesterday,
        ))
        t3 = await task_service.create_task(**make_task(
            title="Career 3 done", category="career", category_id=career_cat.id,
        ))
        await task_service.complete_task(t3.id)

        await task_service.create_task(**make_task(
            title="Home 1", category="home", category_id=home_cat.id,
        ))

        stats = await task_service.get_task_stats("test-user")
        assert len(stats.by_category) == 2

        career_stats = next(c for c in stats.by_category if c.category_name == "career")
        assert career_stats.total == 3
        assert career_stats.active == 1  # 1 active (non-overdue)
        assert career_stats.completed == 1
        assert career_stats.overdue == 1

        home_stats = next(c for c in stats.by_category if c.category_name == "home")
        assert home_stats.total == 1
        assert home_stats.active == 1
        assert home_stats.completed == 0
        assert home_stats.overdue == 0

    async def test_uncategorized_tasks(self, task_service):
        # Task with no category
        await task_service.create_task(**make_task(
            title="No cat", category=None,
        ))

        stats = await task_service.get_task_stats("test-user")
        uncat = next(
            (c for c in stats.by_category if c.category_name == "Uncategorized"), None
        )
        assert uncat is not None
        assert uncat.total == 1
        assert uncat.category_id is None


class TestTaskStatsUserIsolation:
    async def test_user_isolation(self, task_service):
        await task_service.create_task(**make_task(user_id="alice", title="Alice task"))
        await task_service.create_task(**make_task(user_id="bob", title="Bob task"))

        alice_stats = await task_service.get_task_stats("alice")
        bob_stats = await task_service.get_task_stats("bob")

        assert alice_stats.total_tasks == 1
        assert bob_stats.total_tasks == 1


# ──────────────── API-level tests ────────────────


class TestTaskStatsAPI:
    async def test_stats_endpoint_returns_200(self, test_client):
        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        assert resp.status_code == 200
        body = resp.json()
        assert "total_tasks" in body
        assert "by_status" in body
        assert "by_priority" in body
        assert "by_category" in body
        assert "due_soon_count" in body

    async def test_stats_endpoint_requires_user_id(self, test_client):
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 422

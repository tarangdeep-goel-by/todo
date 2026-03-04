"""Tests for GET /api/tasks/stats endpoint and TaskService.get_task_stats — 14 tests."""
import pytest
from datetime import datetime, timezone, timedelta
from tests.helpers import make_task


# ──────────────── Helper ────────────────

def _iso(dt: datetime) -> str:
    """Format datetime as ISO string for API payloads."""
    return dt.isoformat()


# ──────────────── Service-level tests ────────────────

class TestTaskStatsServiceEmpty:
    """Stats for a user with no tasks."""

    async def test_empty_user_returns_all_zeros(self, task_service):
        stats = await task_service.get_task_stats("no-tasks-user")
        assert stats["total_tasks"] == 0
        assert stats["by_status"] == {"active": 0, "completed": 0, "overdue": 0}
        assert stats["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert stats["by_category"] == []
        assert stats["due_soon_count"] == 0


class TestTaskStatsServiceCounts:
    """Correct aggregate counts across statuses, priorities, and categories."""

    async def test_active_and_completed_counts(self, task_service):
        """Mix of active/completed tasks returns correct status counts."""
        t1 = await task_service.create_task(**make_task(title="A1"))
        t2 = await task_service.create_task(**make_task(title="A2"))
        t3 = await task_service.create_task(**make_task(title="C1"))
        await task_service.complete_task(t3.id)

        stats = await task_service.get_task_stats("test-user")
        assert stats["total_tasks"] == 3
        assert stats["by_status"]["active"] == 2
        assert stats["by_status"]["completed"] == 1

    async def test_priority_breakdown(self, task_service):
        """Tasks with different priorities are counted correctly."""
        await task_service.create_task(**make_task(title="H", priority="high"))
        await task_service.create_task(**make_task(title="M", priority="medium"))
        await task_service.create_task(**make_task(title="L", priority="low"))
        await task_service.create_task(**make_task(title="N"))  # no priority

        stats = await task_service.get_task_stats("test-user")
        assert stats["by_priority"]["high"] == 1
        assert stats["by_priority"]["medium"] == 1
        assert stats["by_priority"]["low"] == 1
        assert stats["by_priority"]["none"] == 1

    async def test_overdue_counted_correctly(self, task_service):
        """Active tasks with past due_date are counted as overdue."""
        yesterday = _iso(datetime.now(timezone.utc) - timedelta(days=1))
        tomorrow = _iso(datetime.now(timezone.utc) + timedelta(days=1))

        # Active + past due → overdue
        await task_service.create_task(**make_task(title="Overdue1", due_date=yesterday))
        # Active + future due → not overdue
        await task_service.create_task(**make_task(title="Future", due_date=tomorrow))
        # Completed + past due → NOT overdue (completed tasks can't be overdue)
        t3 = await task_service.create_task(**make_task(title="DonePast", due_date=yesterday))
        await task_service.complete_task(t3.id)

        stats = await task_service.get_task_stats("test-user")
        assert stats["by_status"]["overdue"] == 1
        assert stats["total_tasks"] == 3

    async def test_due_soon_counted_correctly(self, task_service):
        """Active tasks due within 48h (but not overdue) are counted as due_soon."""
        now = datetime.now(timezone.utc)
        in_24h = _iso(now + timedelta(hours=24))
        in_47h = _iso(now + timedelta(hours=47))
        in_72h = _iso(now + timedelta(hours=72))
        yesterday = _iso(now - timedelta(days=1))

        # Due in 24h → due_soon
        await task_service.create_task(**make_task(title="Soon1", due_date=in_24h))
        # Due in 47h → due_soon
        await task_service.create_task(**make_task(title="Soon2", due_date=in_47h))
        # Due in 72h → NOT due_soon
        await task_service.create_task(**make_task(title="Later", due_date=in_72h))
        # Overdue → NOT due_soon
        await task_service.create_task(**make_task(title="Past", due_date=yesterday))

        stats = await task_service.get_task_stats("test-user")
        assert stats["due_soon_count"] == 2


class TestTaskStatsServiceCategories:
    """Per-category breakdown in stats."""

    async def test_by_category_breakdown(self, task_service):
        """Each category the user has tasks in appears in by_category."""
        await task_service.create_task(**make_task(title="C1", category="career"))
        await task_service.create_task(**make_task(title="C2", category="career"))
        await task_service.create_task(**make_task(title="H1", category="home"))
        t = await task_service.create_task(**make_task(title="H2", category="home"))
        await task_service.complete_task(t.id)

        stats = await task_service.get_task_stats("test-user")
        cats = {c["category_name"]: c for c in stats["by_category"]}

        assert "career" in cats or "Career" in cats
        career = cats.get("career") or cats.get("Career")
        assert career["total"] == 2
        assert career["active"] == 2
        assert career["completed"] == 0

        home = cats.get("home") or cats.get("Home")
        assert home["total"] == 2
        assert home["active"] == 1
        assert home["completed"] == 1

    async def test_uncategorized_tasks(self, task_service):
        """Tasks with no category appear as 'Uncategorized' in by_category."""
        await task_service.create_task(**make_task(
            title="No Cat", category=None, transcription="no cat",
        ))

        stats = await task_service.get_task_stats("test-user")
        cat_names = [c["category_name"] for c in stats["by_category"]]
        assert "Uncategorized" in cat_names

        uncat = next(c for c in stats["by_category"] if c["category_name"] == "Uncategorized")
        assert uncat["total"] == 1
        assert uncat["category_id"] is None

    async def test_category_overdue_in_breakdown(self, task_service):
        """Overdue tasks are reflected in per-category overdue counts."""
        yesterday = _iso(datetime.now(timezone.utc) - timedelta(days=1))
        await task_service.create_task(**make_task(
            title="Overdue Career", category="career", due_date=yesterday,
        ))
        await task_service.create_task(**make_task(title="Normal Career", category="career"))

        stats = await task_service.get_task_stats("test-user")
        career = next(
            c for c in stats["by_category"]
            if c["category_name"].lower() == "career"
        )
        assert career["overdue"] == 1
        assert career["total"] == 2

    async def test_user_isolation(self, task_service):
        """Stats only include tasks for the requested user."""
        await task_service.create_task(**make_task(user_id="alice", title="Alice task"))
        await task_service.create_task(**make_task(user_id="bob", title="Bob task"))

        alice_stats = await task_service.get_task_stats("alice")
        assert alice_stats["total_tasks"] == 1

        bob_stats = await task_service.get_task_stats("bob")
        assert bob_stats["total_tasks"] == 1


# ──────────────── API-level tests ────────────────

class TestTaskStatsAPI:
    """Tests against the GET /tasks/stats HTTP endpoint."""

    async def test_empty_user_api(self, test_client):
        """Empty user returns valid zero-state response via API."""
        resp = await test_client.get("/tasks/stats", params={"user_id": "ghost"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 0
        assert body["by_status"]["active"] == 0
        assert body["by_status"]["completed"] == 0
        assert body["by_status"]["overdue"] == 0
        assert body["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert body["by_category"] == []
        assert body["due_soon_count"] == 0

    async def test_stats_with_tasks_api(self, test_client):
        """Stats reflect created/completed tasks via API."""
        await test_client.post("/tasks", json={
            "user_id": "u1", "title": "T1", "category": "career",
            "transcription": "t1",
        })
        create_resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "T2", "category": "career",
            "transcription": "t2",
        })
        task_id = create_resp.json()["id"]
        await test_client.put(f"/tasks/{task_id}/complete")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 2
        assert body["by_status"]["active"] == 1
        assert body["by_status"]["completed"] == 1

    async def test_missing_user_id_returns_422(self, test_client):
        """Missing user_id query param returns validation error."""
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 422

    async def test_response_schema_shape(self, test_client):
        """Response matches TaskStatsResponse schema keys."""
        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        assert set(body.keys()) == {"total_tasks", "by_status", "by_priority", "by_category", "due_soon_count"}
        assert set(body["by_status"].keys()) == {"active", "completed", "overdue"}
        assert set(body["by_priority"].keys()) == {"high", "medium", "low", "none"}

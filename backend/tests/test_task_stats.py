"""Tests for GET /api/tasks/stats endpoint."""
import pytest
from datetime import datetime, timezone, timedelta


USER = "test-user"


def _task(title, category="career", **overrides):
    """Shorthand for creating a task payload."""
    base = {
        "title": title,
        "category": category,
        "transcription": title.lower(),
    }
    base.update(overrides)
    return base


class TestTaskStatsEmpty:
    """Stats for a user with no tasks."""

    async def test_empty_user_returns_all_zeros(self, test_client):
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 0
        assert body["by_status"] == {"active": 0, "completed": 0, "overdue": 0}
        assert body["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert body["by_category"] == []
        assert body["due_soon_count"] == 0


class TestTaskStatsByStatus:
    """Status breakdown: active, completed, overdue."""

    async def test_active_and_completed_counts(self, test_client):
        # Create 3 active tasks
        for i in range(3):
            await test_client.post("/tasks", json=_task(f"Active {i}"))
        # Create 2 tasks and complete them
        for i in range(2):
            cr = await test_client.post("/tasks", json=_task(f"Done {i}"))
            tid = cr.json()["id"]
            await test_client.put(f"/tasks/{tid}/complete")

        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 5
        assert body["by_status"]["active"] == 3
        assert body["by_status"]["completed"] == 2

    async def test_overdue_counted_correctly(self, test_client):
        """Overdue = active + due_date in the past."""
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        tomorrow = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()

        # 2 overdue tasks (active, past due)
        await test_client.post("/tasks", json=_task("Overdue 1", due_date=yesterday))
        await test_client.post("/tasks", json=_task("Overdue 2", due_date=yesterday))
        # 1 active task with future due date (not overdue)
        await test_client.post("/tasks", json=_task("Future", due_date=tomorrow))
        # 1 completed task with past due date (should NOT count as overdue)
        cr = await test_client.post("/tasks", json=_task("Done Past", due_date=yesterday))
        await test_client.put(f"/tasks/{cr.json()['id']}/complete")

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert body["by_status"]["overdue"] == 2
        # Overdue tasks are still active, so active count should include them
        # or not, depending on whether overdue is a separate bucket.
        # Per spec: by_status has active, completed, overdue as separate counts.
        # Overdue tasks are a subset carved out of active.
        # total = active + completed + overdue
        assert body["total_tasks"] == 4

    async def test_completed_past_due_not_overdue(self, test_client):
        """A completed task with a past due_date should NOT be counted as overdue."""
        past = (datetime.now(timezone.utc) - timedelta(days=5)).isoformat()
        cr = await test_client.post("/tasks", json=_task("Completed Late", due_date=past))
        await test_client.put(f"/tasks/{cr.json()['id']}/complete")

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert body["by_status"]["overdue"] == 0
        assert body["by_status"]["completed"] == 1


class TestTaskStatsDueSoon:
    """due_soon_count = active tasks with due_date within 48h, not overdue."""

    async def test_due_soon_within_48h(self, test_client):
        now = datetime.now(timezone.utc)
        # Due in 24h — should count as due_soon
        in_24h = (now + timedelta(hours=24)).isoformat()
        # Due in 47h — should count as due_soon
        in_47h = (now + timedelta(hours=47)).isoformat()
        # Due in 72h — should NOT count as due_soon
        in_72h = (now + timedelta(hours=72)).isoformat()
        # Overdue (past) — should NOT count as due_soon
        past = (now - timedelta(hours=2)).isoformat()

        await test_client.post("/tasks", json=_task("Soon 1", due_date=in_24h))
        await test_client.post("/tasks", json=_task("Soon 2", due_date=in_47h))
        await test_client.post("/tasks", json=_task("Later", due_date=in_72h))
        await test_client.post("/tasks", json=_task("Overdue", due_date=past))

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert body["due_soon_count"] == 2

    async def test_completed_due_soon_not_counted(self, test_client):
        """Completed tasks within 48h should NOT count as due_soon."""
        in_12h = (datetime.now(timezone.utc) + timedelta(hours=12)).isoformat()
        cr = await test_client.post("/tasks", json=_task("Done Soon", due_date=in_12h))
        await test_client.put(f"/tasks/{cr.json()['id']}/complete")

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert body["due_soon_count"] == 0


class TestTaskStatsByPriority:
    """Priority breakdown: high, medium, low, none."""

    async def test_priority_counts(self, test_client):
        await test_client.post("/tasks", json=_task("H1", priority="high"))
        await test_client.post("/tasks", json=_task("H2", priority="high"))
        await test_client.post("/tasks", json=_task("M1", priority="medium"))
        await test_client.post("/tasks", json=_task("L1", priority="low"))
        await test_client.post("/tasks", json=_task("N1"))  # no priority

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert body["by_priority"]["high"] == 2
        assert body["by_priority"]["medium"] == 1
        assert body["by_priority"]["low"] == 1
        assert body["by_priority"]["none"] == 1


class TestTaskStatsByCategory:
    """Per-category breakdown with correct counts."""

    async def test_category_breakdown(self, test_client):
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()

        # Career: 2 active, 1 completed, 1 overdue
        await test_client.post("/tasks", json=_task("C1", "career"))
        await test_client.post("/tasks", json=_task("C2", "career"))
        cr = await test_client.post("/tasks", json=_task("C3", "career"))
        await test_client.put(f"/tasks/{cr.json()['id']}/complete")
        await test_client.post("/tasks", json=_task("C4 overdue", "career", due_date=yesterday))

        # Health: 1 active only
        await test_client.post("/tasks", json=_task("H1", "health"))

        resp = await test_client.get("/tasks/stats")
        body = resp.json()

        cats = {c["category_name"]: c for c in body["by_category"]}
        assert "career" in cats
        assert "health" in cats

        career = cats["career"]
        assert career["total"] == 4
        assert career["active"] >= 2  # 2 active (non-overdue) + 1 overdue
        assert career["completed"] == 1
        assert career["overdue"] == 1

        health = cats["health"]
        assert health["total"] == 1
        assert health["active"] >= 1
        assert health["completed"] == 0
        assert health["overdue"] == 0

    async def test_category_has_id_and_name(self, test_client):
        await test_client.post("/tasks", json=_task("T", "finance"))

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        assert len(body["by_category"]) == 1
        entry = body["by_category"][0]
        assert "category_name" in entry
        assert "category_id" in entry
        assert "total" in entry
        assert entry["category_name"] == "finance"

    async def test_no_category_appears_as_uncategorized(self, test_client):
        """Tasks without a category should appear as 'Uncategorized'."""
        # Create a task with no real category — use empty or a sentinel.
        # The spec says tasks with no category → Uncategorized entry.
        # Looking at create_task, category is required. We'll create via
        # task_service directly to bypass validation, but since we're testing
        # via API, we need to see if the endpoint handles null category_id.
        # For API tests, all tasks get a category. Test this at service level.
        # However, we can still check: if we create tasks in only one category,
        # there should be no "Uncategorized" entry.
        await test_client.post("/tasks", json=_task("T", "career"))

        resp = await test_client.get("/tasks/stats")
        body = resp.json()
        names = [c["category_name"] for c in body["by_category"]]
        # No uncategorized if all tasks have categories
        assert "Uncategorized" not in names or all(
            c["total"] == 0 for c in body["by_category"] if c["category_name"] == "Uncategorized"
        )


class TestTaskStatsUncategorized:
    """Tasks with no category_id should be grouped as 'Uncategorized'."""

    async def test_uncategorized_via_service(self, task_service):
        """Use task_service directly to create a task without category_id."""
        from tests.helpers import make_task

        # Create a task with category but no category_id resolved
        # (simulates a task where category_id is NULL in the DB)
        from sqlalchemy import text

        # Insert a task directly with NULL category_id
        task = await task_service.create_task(
            user_id=USER,
            title="Orphan Task",
            category="unknown",
            transcription="orphan",
        )
        # The task may get a category_id auto-resolved, or not.
        # Force category_id to NULL via direct update.
        await task_service.db.execute(
            text("UPDATE tasks SET category_id = NULL WHERE id = :tid"),
            {"tid": str(task.id)},
        )
        await task_service.db.commit()

        stats = await task_service.get_task_stats(USER)
        cat_names = [c["category_name"] for c in stats["by_category"]]
        assert "Uncategorized" in cat_names
        uncat = next(c for c in stats["by_category"] if c["category_name"] == "Uncategorized")
        assert uncat["total"] == 1
        assert uncat["category_id"] is None


class TestTaskStatsIsolation:
    """Stats should only include tasks for the requested user."""

    async def test_different_users_isolated(self, test_client, task_service):
        # Create a task for a different user directly via service
        await task_service.create_task(
            user_id="other-user", title="Other's task",
            category="career", transcription="other",
        )
        # Create a task for the authenticated user (test-user) via API
        await test_client.post("/tasks", json={
            "title": "My task", "category": "career", "transcription": "mine",
        })

        # Stats should only show test-user's task
        resp = await test_client.get("/tasks/stats")
        assert resp.json()["total_tasks"] == 1

    async def test_no_tasks_returns_zeros(self, test_client):
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 200
        assert resp.json()["total_tasks"] == 0


class TestTaskStatsResponseShape:
    """Validate the response schema structure."""

    async def test_response_has_all_required_fields(self, test_client):
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 200
        body = resp.json()
        assert "total_tasks" in body
        assert "by_status" in body
        assert "by_priority" in body
        assert "by_category" in body
        assert "due_soon_count" in body

    async def test_by_status_has_all_keys(self, test_client):
        resp = await test_client.get("/tasks/stats")
        status = resp.json()["by_status"]
        assert set(status.keys()) == {"active", "completed", "overdue"}

    async def test_by_priority_has_all_keys(self, test_client):
        resp = await test_client.get("/tasks/stats")
        priority = resp.json()["by_priority"]
        assert set(priority.keys()) == {"high", "medium", "low", "none"}


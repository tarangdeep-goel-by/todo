"""Tests for task statistics — service layer + API endpoint."""
import pytest
from datetime import datetime, timedelta, timezone
from tests.helpers import make_task


USER_ID = "stats-user"


# ──────────────── Service-layer tests ────────────────


class TestGetTaskStatsEmpty:
    async def test_empty_user_returns_zeros(self, task_service):
        stats = await task_service.get_task_stats("nonexistent-user")
        assert stats["total_tasks"] == 0
        assert stats["by_status"] == {"active": 0, "completed": 0, "overdue": 0}
        assert stats["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert stats["by_category"] == []
        assert stats["due_soon_count"] == 0


class TestGetTaskStatsStatusCounts:
    async def test_mixed_active_completed(self, task_service):
        """Active and completed tasks counted correctly in by_status and total."""
        t1 = await task_service.create_task(**make_task(user_id=USER_ID, title="A"))
        t2 = await task_service.create_task(**make_task(user_id=USER_ID, title="B"))
        t3 = await task_service.create_task(**make_task(user_id=USER_ID, title="C"))
        await task_service.complete_task(t2.id)

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["total_tasks"] == 3
        assert stats["by_status"]["active"] == 2
        assert stats["by_status"]["completed"] == 1

    async def test_overdue_counted_correctly(self, task_service):
        """Active tasks with past due_date are overdue."""
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Overdue 1", due_date=yesterday,
        ))
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Overdue 2", due_date=yesterday,
        ))
        # Active task with no due date — not overdue
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Normal",
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["by_status"]["overdue"] == 2
        assert stats["by_status"]["active"] == 1
        assert stats["total_tasks"] == 3

    async def test_completed_past_due_not_overdue(self, task_service):
        """Completed tasks with past due_date should NOT count as overdue."""
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        t = await task_service.create_task(**make_task(
            user_id=USER_ID, title="Done late", due_date=yesterday,
        ))
        await task_service.complete_task(t.id)

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["by_status"]["overdue"] == 0
        assert stats["by_status"]["completed"] == 1


class TestGetTaskStatsDueSoon:
    async def test_due_soon_within_48h(self, task_service):
        """Active tasks due within 48 hours (not overdue) count as due_soon."""
        tomorrow = datetime.now(timezone.utc) + timedelta(hours=24)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Due tomorrow", due_date=tomorrow,
        ))
        # Due in 47 hours — still within 48h window
        soon = datetime.now(timezone.utc) + timedelta(hours=47)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Due soon", due_date=soon,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["due_soon_count"] == 2

    async def test_due_soon_excludes_overdue(self, task_service):
        """Overdue tasks (past due) should NOT count as due_soon."""
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Overdue", due_date=yesterday,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["due_soon_count"] == 0
        assert stats["by_status"]["overdue"] == 1

    async def test_due_soon_excludes_beyond_48h(self, task_service):
        """Tasks due beyond 48 hours should NOT count as due_soon."""
        far_future = datetime.now(timezone.utc) + timedelta(hours=72)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Later", due_date=far_future,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["due_soon_count"] == 0

    async def test_due_soon_excludes_completed(self, task_service):
        """Completed tasks due within 48h should NOT count as due_soon."""
        tomorrow = datetime.now(timezone.utc) + timedelta(hours=24)
        t = await task_service.create_task(**make_task(
            user_id=USER_ID, title="Done soon", due_date=tomorrow,
        ))
        await task_service.complete_task(t.id)

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["due_soon_count"] == 0


class TestGetTaskStatsByPriority:
    async def test_priority_breakdown(self, task_service):
        """Each priority level counted correctly."""
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="H", priority="high",
        ))
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="M1", priority="medium",
        ))
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="M2", priority="medium",
        ))
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="L", priority="low",
        ))
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="N",  # no priority
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert stats["by_priority"]["high"] == 1
        assert stats["by_priority"]["medium"] == 2
        assert stats["by_priority"]["low"] == 1
        assert stats["by_priority"]["none"] == 1


class TestGetTaskStatsByCategory:
    async def test_category_breakdown(self, task_service):
        """Per-category counts match actual task distribution."""
        career_cat = await task_service.create_category(USER_ID, "career")
        home_cat = await task_service.create_category(USER_ID, "home")

        # 2 career tasks (1 active, 1 completed)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Work 1", category="career",
            category_id=career_cat.id,
        ))
        t2 = await task_service.create_task(**make_task(
            user_id=USER_ID, title="Work 2", category="career",
            category_id=career_cat.id,
        ))
        await task_service.complete_task(t2.id)

        # 1 home task with overdue
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Chore", category="home",
            category_id=home_cat.id, due_date=yesterday,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        by_cat = {entry["category_name"]: entry for entry in stats["by_category"]}

        assert "career" in by_cat or "Career" in by_cat
        career_key = "career" if "career" in by_cat else "Career"
        career = by_cat[career_key]
        assert career["total"] == 2
        assert career["active"] == 1
        assert career["completed"] == 1
        assert career["overdue"] == 0

        home_key = "home" if "home" in by_cat else "Home"
        home = by_cat[home_key]
        assert home["total"] == 1
        assert home["active"] == 0  # it's overdue, not plain active
        assert home["overdue"] == 1

    async def test_uncategorized_tasks(self, task_service):
        """Tasks with no category appear as 'Uncategorized'."""
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="Orphan",
            category=None, category_id=None,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        by_cat = {entry["category_name"]: entry for entry in stats["by_category"]}

        assert "Uncategorized" in by_cat
        assert by_cat["Uncategorized"]["total"] == 1

    async def test_category_entry_has_required_fields(self, task_service):
        """Each by_category entry contains all required fields."""
        career_cat = await task_service.create_category(USER_ID, "career")
        await task_service.create_task(**make_task(
            user_id=USER_ID, title="X", category="career",
            category_id=career_cat.id,
        ))

        stats = await task_service.get_task_stats(USER_ID)
        assert len(stats["by_category"]) >= 1
        entry = stats["by_category"][0]
        assert "category_id" in entry
        assert "category_name" in entry
        assert "total" in entry
        assert "active" in entry
        assert "completed" in entry
        assert "overdue" in entry


class TestGetTaskStatsUserIsolation:
    async def test_only_counts_own_tasks(self, task_service):
        """Stats for one user exclude another user's tasks."""
        await task_service.create_task(**make_task(user_id="alice", title="A"))
        await task_service.create_task(**make_task(user_id="bob", title="B"))
        await task_service.create_task(**make_task(user_id="bob", title="C"))

        alice_stats = await task_service.get_task_stats("alice")
        bob_stats = await task_service.get_task_stats("bob")

        assert alice_stats["total_tasks"] == 1
        assert bob_stats["total_tasks"] == 2


# ──────────────── API endpoint tests ────────────────


class TestGetTaskStatsAPI:
    async def test_empty_user(self, test_client):
        resp = await test_client.get("/tasks/stats", params={"user_id": "nobody"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 0
        assert body["by_status"]["active"] == 0
        assert body["by_status"]["completed"] == 0
        assert body["by_status"]["overdue"] == 0
        assert body["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert body["by_category"] == []
        assert body["due_soon_count"] == 0

    async def test_response_schema_with_data(self, test_client):
        """API returns correct schema shape with mixed data."""
        # Create tasks
        await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Active", "category": "career",
            "transcription": "active", "priority": "high",
        })
        create2 = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Done", "category": "career",
            "transcription": "done",
        })
        task_id = create2.json()["id"]
        await test_client.put(f"/tasks/{task_id}/complete")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        assert resp.status_code == 200
        body = resp.json()

        # Validate schema shape
        assert isinstance(body["total_tasks"], int)
        assert body["total_tasks"] == 2
        assert isinstance(body["by_status"], dict)
        assert isinstance(body["by_priority"], dict)
        assert isinstance(body["by_category"], list)
        assert isinstance(body["due_soon_count"], int)

        # Validate counts
        assert body["by_status"]["active"] == 1
        assert body["by_status"]["completed"] == 1
        assert body["by_priority"]["high"] == 1

    async def test_overdue_via_api(self, test_client):
        """Overdue tasks counted correctly through the API."""
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Late", "category": "career",
            "transcription": "late", "due_date": yesterday,
        })
        await test_client.post("/tasks", json={
            "user_id": "u1", "title": "On time", "category": "career",
            "transcription": "on time",
        })

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        assert body["by_status"]["overdue"] == 1
        assert body["by_status"]["active"] == 1
        assert body["total_tasks"] == 2

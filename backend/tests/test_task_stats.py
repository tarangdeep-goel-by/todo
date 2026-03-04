"""Tests for GET /api/tasks/stats endpoint — task statistics."""
from datetime import datetime, timedelta, timezone

from tests.helpers import make_task


USER = "stats-user"


async def _create_task(test_client, **overrides):
    """Helper to create a task via the API and return the response JSON."""
    payload = {
        "user_id": USER,
        "title": "Task",
        "category": "career",
        "transcription": "task",
    }
    payload.update(overrides)
    resp = await test_client.post("/tasks", json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()


async def _complete_task(test_client, task_id: str):
    """Complete a task and return the response JSON."""
    resp = await test_client.put(f"/tasks/{task_id}/complete")
    assert resp.status_code == 200, resp.text
    return resp.json()


async def _set_due_date(test_client, task_id: str, due_date: str):
    """Set due_date on a task via PATCH."""
    resp = await test_client.patch(f"/tasks/{task_id}", json={"due_date": due_date})
    assert resp.status_code == 200, resp.text
    return resp.json()


class TestStatsEmpty:
    """Empty user returns all zeros."""

    async def test_empty_user_returns_zeros(self, test_client):
        resp = await test_client.get("/tasks/stats", params={"user_id": "nobody"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 0
        assert body["by_status"]["active"] == 0
        assert body["by_status"]["completed"] == 0
        assert body["by_status"]["overdue"] == 0
        assert body["by_priority"]["high"] == 0
        assert body["by_priority"]["medium"] == 0
        assert body["by_priority"]["low"] == 0
        assert body["by_priority"]["none"] == 0
        assert body["by_category"] == []
        assert body["due_soon_count"] == 0


class TestStatsStatusBreakdown:
    """Mix of active/completed tasks returns correct counts."""

    async def test_active_and_completed_counts(self, test_client):
        # Create 3 active tasks
        t1 = await _create_task(test_client, title="Active 1")
        t2 = await _create_task(test_client, title="Active 2")
        t3 = await _create_task(test_client, title="To Complete")

        # Complete one
        await _complete_task(test_client, t3["id"])

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        assert resp.status_code == 200
        body = resp.json()

        assert body["total_tasks"] == 3
        assert body["by_status"]["active"] == 2
        assert body["by_status"]["completed"] == 1


class TestStatsOverdue:
    """Overdue tasks counted correctly (active + past due_date)."""

    async def test_overdue_counted_in_status(self, test_client):
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()

        # Task with past due date (overdue)
        t1 = await _create_task(test_client, title="Overdue Task")
        await _set_due_date(test_client, t1["id"], yesterday)

        # Task with future due date (not overdue)
        t2 = await _create_task(test_client, title="Future Task")
        await _set_due_date(test_client, t2["id"], tomorrow)

        # Active task with no due date (not overdue)
        await _create_task(test_client, title="No Due Date")

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["by_status"]["overdue"] == 1
        assert body["total_tasks"] == 3

    async def test_completed_past_due_not_overdue(self, test_client):
        """A completed task with a past due date is NOT overdue."""
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()

        t1 = await _create_task(test_client, title="Completed Past Due")
        await _set_due_date(test_client, t1["id"], yesterday)
        await _complete_task(test_client, t1["id"])

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["by_status"]["overdue"] == 0
        assert body["by_status"]["completed"] == 1


class TestStatsDueSoon:
    """Due soon tasks counted correctly (active + due_date within 48h, not overdue)."""

    async def test_due_soon_within_48h(self, test_client):
        now = datetime.now(timezone.utc)
        in_24h = (now + timedelta(hours=24)).isoformat()
        in_47h = (now + timedelta(hours=47)).isoformat()
        in_72h = (now + timedelta(hours=72)).isoformat()
        yesterday = (now - timedelta(days=1)).isoformat()

        # Due in 24h — due soon
        t1 = await _create_task(test_client, title="Due Soon 1")
        await _set_due_date(test_client, t1["id"], in_24h)

        # Due in 47h — due soon
        t2 = await _create_task(test_client, title="Due Soon 2")
        await _set_due_date(test_client, t2["id"], in_47h)

        # Due in 72h — NOT due soon
        t3 = await _create_task(test_client, title="Not Due Soon")
        await _set_due_date(test_client, t3["id"], in_72h)

        # Overdue — NOT due soon (it's overdue, different bucket)
        t4 = await _create_task(test_client, title="Overdue")
        await _set_due_date(test_client, t4["id"], yesterday)

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["due_soon_count"] == 2

    async def test_completed_task_not_due_soon(self, test_client):
        """Completed task within 48h should NOT count as due soon."""
        in_24h = (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat()

        t1 = await _create_task(test_client, title="Completed Soon")
        await _set_due_date(test_client, t1["id"], in_24h)
        await _complete_task(test_client, t1["id"])

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["due_soon_count"] == 0


class TestStatsByPriority:
    """Priority breakdown is correct."""

    async def test_priority_counts(self, test_client):
        await _create_task(test_client, title="High 1", priority="high")
        await _create_task(test_client, title="High 2", priority="high")
        await _create_task(test_client, title="Medium 1", priority="medium")
        await _create_task(test_client, title="Low 1", priority="low")
        await _create_task(test_client, title="No Priority")  # priority=None

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["by_priority"]["high"] == 2
        assert body["by_priority"]["medium"] == 1
        assert body["by_priority"]["low"] == 1
        assert body["by_priority"]["none"] == 1


class TestStatsByCategory:
    """By-category breakdown matches per-category counts."""

    async def test_category_breakdown(self, test_client):
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()

        # Career: 2 active, 1 completed, 1 overdue
        await _create_task(test_client, title="Career 1", category="career")
        await _create_task(test_client, title="Career 2", category="career")
        t_career_done = await _create_task(test_client, title="Career Done", category="career")
        await _complete_task(test_client, t_career_done["id"])
        t_career_overdue = await _create_task(test_client, title="Career Overdue", category="career")
        await _set_due_date(test_client, t_career_overdue["id"], yesterday)

        # Home: 1 active
        await _create_task(test_client, title="Home 1", category="home")

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        cats = {c["category_name"]: c for c in body["by_category"]}
        assert len(cats) == 2

        career = cats["career"]
        assert career["total"] == 4
        assert career["active"] == 2  # 2 active (overdue is separate)
        assert career["completed"] == 1
        assert career["overdue"] == 1

        home = cats["home"]
        assert home["total"] == 1
        assert home["active"] == 1
        assert home["completed"] == 0
        assert home["overdue"] == 0

    async def test_category_has_id_and_name(self, test_client):
        """Each by_category entry has category_id and category_name."""
        await _create_task(test_client, title="Task", category="health")

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert len(body["by_category"]) >= 1
        entry = body["by_category"][0]
        assert "category_id" in entry
        assert "category_name" in entry
        assert entry["category_name"] == "health"


class TestStatsUncategorized:
    """Tasks with no category appear as 'Uncategorized'."""

    async def test_uncategorized_tasks(self, task_service, test_client):
        """Tasks created without a category should be grouped under Uncategorized."""
        # Create a task with no category via the service directly
        # (API may auto-assign categories, so use service for control)
        task = await task_service.create_task(
            user_id=USER,
            title="No Category Task",
            category=None,
            transcription="uncategorized",
            category_id=None,
        )

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert body["total_tasks"] == 1
        cats = {c["category_name"]: c for c in body["by_category"]}
        assert "Uncategorized" in cats
        assert cats["Uncategorized"]["total"] == 1
        assert cats["Uncategorized"]["active"] == 1


class TestStatsResponseShape:
    """Validate response structure matches the schema."""

    async def test_response_has_all_required_fields(self, test_client):
        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        assert resp.status_code == 200
        body = resp.json()

        # Top-level keys
        assert "total_tasks" in body
        assert "by_status" in body
        assert "by_priority" in body
        assert "by_category" in body
        assert "due_soon_count" in body

        # by_status keys
        assert set(body["by_status"].keys()) == {"active", "completed", "overdue"}

        # by_priority keys
        assert set(body["by_priority"].keys()) == {"high", "medium", "low", "none"}

    async def test_category_entry_shape(self, test_client):
        await _create_task(test_client, title="Shape Test", category="finance")

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        assert len(body["by_category"]) >= 1
        entry = body["by_category"][0]
        expected_keys = {"category_id", "category_name", "total", "active", "completed", "overdue"}
        assert set(entry.keys()) == expected_keys


class TestStatsIsolation:
    """Stats are scoped to the requested user_id."""

    async def test_different_users_isolated(self, test_client):
        # Create tasks for two different users
        await _create_task(test_client, title="User A Task", user_id="user-a")
        await _create_task(test_client, title="User B Task 1", user_id="user-b")
        await _create_task(test_client, title="User B Task 2", user_id="user-b")

        resp_a = await test_client.get("/tasks/stats", params={"user_id": "user-a"})
        resp_b = await test_client.get("/tasks/stats", params={"user_id": "user-b"})

        assert resp_a.json()["total_tasks"] == 1
        assert resp_b.json()["total_tasks"] == 2


class TestStatsCombined:
    """End-to-end test with a realistic mix of data."""

    async def test_full_scenario(self, test_client):
        now = datetime.now(timezone.utc)
        yesterday = (now - timedelta(days=1)).isoformat()
        in_12h = (now + timedelta(hours=12)).isoformat()
        in_72h = (now + timedelta(hours=72)).isoformat()

        # Career: 1 active high, 1 completed medium, 1 overdue low
        t1 = await _create_task(test_client, title="Career Active", category="career", priority="high")
        t2 = await _create_task(test_client, title="Career Done", category="career", priority="medium")
        await _complete_task(test_client, t2["id"])
        t3 = await _create_task(test_client, title="Career Overdue", category="career", priority="low")
        await _set_due_date(test_client, t3["id"], yesterday)

        # Health: 1 active due soon, 1 active not due soon
        t4 = await _create_task(test_client, title="Health Soon", category="health")
        await _set_due_date(test_client, t4["id"], in_12h)
        t5 = await _create_task(test_client, title="Health Later", category="health")
        await _set_due_date(test_client, t5["id"], in_72h)

        resp = await test_client.get("/tasks/stats", params={"user_id": USER})
        body = resp.json()

        # Total: 5 tasks
        assert body["total_tasks"] == 5

        # Status: 3 active (Career Active, Health Soon, Health Later), 1 completed, 1 overdue
        assert body["by_status"]["active"] == 3
        assert body["by_status"]["completed"] == 1
        assert body["by_status"]["overdue"] == 1

        # Due soon: only Health Soon (in 12h, active, not overdue)
        assert body["due_soon_count"] == 1

        # Priority: 1 high, 1 medium, 1 low, 2 none
        assert body["by_priority"]["high"] == 1
        assert body["by_priority"]["medium"] == 1
        assert body["by_priority"]["low"] == 1
        assert body["by_priority"]["none"] == 2

        # Categories: career and health
        cats = {c["category_name"]: c for c in body["by_category"]}
        assert len(cats) == 2
        assert cats["career"]["total"] == 3
        assert cats["health"]["total"] == 2

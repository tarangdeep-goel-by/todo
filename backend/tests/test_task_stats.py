"""Tests for GET /api/tasks/stats endpoint."""
import pytest
from datetime import datetime, timezone, timedelta


async def _create(client, *, user_id="u1", title, category="career", status=None,
                  priority=None, due_date=None):
    resp = await client.post("/tasks", json={
        "user_id": user_id,
        "title": title,
        "category": category,
        "transcription": title,
        **({"priority": priority} if priority else {}),
        **({"due_date": due_date.isoformat()} if due_date else {}),
    })
    assert resp.status_code == 201, resp.text
    task = resp.json()
    if status == "completed":
        await client.put(f"/tasks/{task['id']}/complete")
    return task


@pytest.mark.asyncio
class TestTaskStats:

    async def test_empty_user_returns_zeros(self, test_client):
        resp = await test_client.get("/tasks/stats", params={"user_id": "empty-user"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 0
        assert body["by_status"] == {"active": 0, "completed": 0, "overdue": 0}
        assert body["by_priority"] == {"high": 0, "medium": 0, "low": 0, "none": 0}
        assert body["by_category"] == []
        assert body["due_soon_count"] == 0

    async def test_active_and_completed_counts(self, test_client):
        await _create(test_client, title="active task")
        await _create(test_client, title="done task", status="completed")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_tasks"] == 2
        assert body["by_status"]["active"] == 1
        assert body["by_status"]["completed"] == 1
        assert body["by_status"]["overdue"] == 0

    async def test_overdue_tasks_counted_correctly(self, test_client):
        past = datetime.now(timezone.utc) - timedelta(days=1)
        await _create(test_client, title="overdue task", due_date=past)
        await _create(test_client, title="normal active task")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        assert body["by_status"]["overdue"] == 1
        # overdue is active in DB so total active (not-overdue) = 1, overdue = 1
        assert body["by_status"]["active"] == 1
        assert body["total_tasks"] == 2

    async def test_due_soon_count(self, test_client):
        soon = datetime.now(timezone.utc) + timedelta(hours=24)
        far = datetime.now(timezone.utc) + timedelta(days=7)
        past = datetime.now(timezone.utc) - timedelta(hours=1)

        await _create(test_client, title="due soon", due_date=soon)
        await _create(test_client, title="due later", due_date=far)
        await _create(test_client, title="overdue", due_date=past)
        await _create(test_client, title="no due date")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        assert body["due_soon_count"] == 1
        assert body["by_status"]["overdue"] == 1

    async def test_by_category_breakdown(self, test_client):
        await _create(test_client, title="career a", category="career")
        await _create(test_client, title="career b", category="career", status="completed")
        await _create(test_client, title="health a", category="health")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()

        cats = {c["category_name"]: c for c in body["by_category"]}
        assert "career" in cats
        assert cats["career"]["total"] == 2
        assert cats["career"]["active"] == 1
        assert cats["career"]["completed"] == 1

        assert "health" in cats
        assert cats["health"]["total"] == 1
        assert cats["health"]["active"] == 1

    async def test_priority_breakdown(self, test_client):
        await _create(test_client, title="high pri", priority="high")
        await _create(test_client, title="medium pri", priority="medium")
        await _create(test_client, title="no pri")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        assert body["by_priority"]["high"] == 1
        assert body["by_priority"]["medium"] == 1
        assert body["by_priority"]["none"] == 1
        assert body["by_priority"]["low"] == 0

    async def test_overdue_in_category_breakdown(self, test_client):
        past = datetime.now(timezone.utc) - timedelta(days=2)
        await _create(test_client, title="overdue career", category="career", due_date=past)
        await _create(test_client, title="active career", category="career")

        resp = await test_client.get("/tasks/stats", params={"user_id": "u1"})
        body = resp.json()
        cats = {c["category_name"]: c for c in body["by_category"]}
        assert cats["career"]["overdue"] == 1
        assert cats["career"]["active"] == 1
        assert cats["career"]["total"] == 2

"""Tests for /api/tasks endpoints — 10 tests."""
import pytest


class TestGetTasks:
    async def test_empty(self, test_client):
        resp = await test_client.get("/tasks")
        assert resp.status_code == 200
        body = resp.json()
        assert body["tasks"] == []
        assert body["total_count"] == 0

    async def test_with_data(self, test_client):
        # Create a task first
        await test_client.post("/tasks", json={
            "title": "Task A", "category": "career",
            "transcription": "task a",
        })
        resp = await test_client.get("/tasks")
        assert resp.status_code == 200
        assert len(resp.json()["tasks"]) == 1


class TestGetTaskById:
    async def test_found(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "T1", "category": "career",
            "transcription": "t1",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.get(f"/tasks/{task_id}")
        assert resp.status_code == 200
        assert resp.json()["title"] == "t1"

    async def test_not_found(self, test_client):
        resp = await test_client.get("/tasks/ffffffff-ffff-ffff-ffff-ffffffffffff")
        assert resp.status_code == 404


class TestCreateTask:
    async def test_success(self, test_client):
        resp = await test_client.post("/tasks", json={
            "title": "New Task", "category": "home",
            "transcription": "new task",
        })
        assert resp.status_code == 201
        assert resp.json()["title"] == "new task"
        assert resp.json()["category"] == "home"

    async def test_validation_error(self, test_client):
        resp = await test_client.post("/tasks", json={
            # missing required fields
        })
        assert resp.status_code == 422


class TestUpdateTask:
    async def test_success(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "Old", "category": "career",
            "transcription": "old",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"title": "New"})
        assert resp.status_code == 200
        assert resp.json()["title"] == "new"

    async def test_not_found(self, test_client):
        resp = await test_client.patch("/tasks/ffffffff-ffff-ffff-ffff-ffffffffffff", json={"title": "x"})
        assert resp.status_code == 404

    async def test_update_priority(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "T", "category": "career",
            "transcription": "t",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"priority": "high"})
        assert resp.status_code == 200
        assert resp.json()["priority"] == "high"

    async def test_update_tags(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "T", "category": "career",
            "transcription": "t",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"tags": ["urgent", "review"]})
        assert resp.status_code == 200
        assert resp.json()["tags"] == ["urgent", "review"]

    async def test_update_estimated_hours(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "T", "category": "career",
            "transcription": "t",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"estimated_hours": 2.5})
        assert resp.status_code == 200
        assert resp.json()["estimated_hours"] == 2.5


class TestCompleteTask:
    async def test_complete(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "Do it", "category": "career",
            "transcription": "do it",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.put(f"/tasks/{task_id}/complete")
        assert resp.status_code == 200
        assert resp.json()["status"] == "completed"

    async def test_complete_with_active_children(self, test_client):
        parent = await test_client.post("/tasks", json={
            "title": "Parent", "category": "career",
            "transcription": "parent",
        })
        parent_id = parent.json()["id"]
        await test_client.post("/tasks", json={
            "title": "Child", "category": "career",
            "transcription": "child", "parent_id": parent_id,
        })
        resp = await test_client.put(f"/tasks/{parent_id}/complete")
        assert resp.status_code == 200
        assert resp.json()["status"] == "completed"


class TestDeleteTask:
    async def test_delete(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "title": "Remove me", "category": "career",
            "transcription": "remove me",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.delete(f"/tasks/{task_id}")
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    async def test_delete_wrong_user(self, test_client, task_service):
        """API is authenticated as 'test-user'; task owned by 'other-user' should 403."""
        task = await task_service.create_task(
            user_id="other-user",
            title="Not yours",
            category="career",
            transcription="not yours",
        )
        resp = await test_client.delete(f"/tasks/{task.id}")
        assert resp.status_code == 403

"""Tests for /api/tasks endpoints — 10 tests."""
import pytest


class TestGetTasks:
    async def test_empty(self, test_client):
        resp = await test_client.get("/tasks", params={"user_id": "u1"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["tasks"] == []
        assert body["total_count"] == 0

    async def test_with_data(self, test_client):
        # Create a task first
        await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Task A", "category": "work",
            "transcription": "task a",
        })
        resp = await test_client.get("/tasks", params={"user_id": "u1"})
        assert resp.status_code == 200
        assert len(resp.json()["tasks"]) == 1


class TestGetTaskById:
    async def test_found(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "T1", "category": "work",
            "transcription": "t1",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.get(f"/tasks/{task_id}")
        assert resp.status_code == 200
        assert resp.json()["title"] == "T1"

    async def test_not_found(self, test_client):
        resp = await test_client.get("/tasks/ffffffff-ffff-ffff-ffff-ffffffffffff")
        assert resp.status_code == 404


class TestCreateTask:
    async def test_success(self, test_client):
        resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "New Task", "category": "personal",
            "transcription": "new task",
        })
        assert resp.status_code == 201
        assert resp.json()["title"] == "New Task"
        assert resp.json()["category"] == "personal"

    async def test_validation_error(self, test_client):
        resp = await test_client.post("/tasks", json={
            "user_id": "u1",
            # missing required fields
        })
        assert resp.status_code == 422


class TestUpdateTask:
    async def test_success(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Old", "category": "work",
            "transcription": "old",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"title": "New"})
        assert resp.status_code == 200
        assert resp.json()["title"] == "New"

    async def test_not_found(self, test_client):
        resp = await test_client.patch("/tasks/ffffffff-ffff-ffff-ffff-ffffffffffff", json={"title": "x"})
        assert resp.status_code == 404


class TestCompleteTask:
    async def test_complete(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Do it", "category": "work",
            "transcription": "do it",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.put(f"/tasks/{task_id}/complete")
        assert resp.status_code == 200
        assert resp.json()["status"] == "completed"


class TestDeleteTask:
    async def test_delete(self, test_client):
        create_resp = await test_client.post("/tasks", json={
            "user_id": "u1", "title": "Remove me", "category": "work",
            "transcription": "remove me",
        })
        task_id = create_resp.json()["id"]
        resp = await test_client.delete(f"/tasks/{task_id}", params={"user_id": "u1"})
        assert resp.status_code == 200
        assert resp.json()["success"] is True

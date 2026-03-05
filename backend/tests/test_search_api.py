"""Tests for GET /api/tasks/search endpoint."""
import pytest


class TestSearchTasks:
    """Tests for the search endpoint."""

    async def test_empty_query_returns_422(self, test_client):
        """Empty query string should fail validation (min_length=1)."""
        resp = await test_client.get("/tasks/search", params={"q": ""})
        assert resp.status_code == 422

    async def test_missing_query_returns_422(self, test_client):
        """Missing q parameter should fail validation."""
        resp = await test_client.get("/tasks/search", params={})
        assert resp.status_code == 422

    async def test_no_results(self, test_client):
        """Search with no matching tasks returns empty list."""
        resp = await test_client.get("/tasks/search", params={
            "q": "nonexistent xyz",
        })
        assert resp.status_code == 200
        body = resp.json()
        assert body["results"] == []
        assert body["query"] == "nonexistent xyz"
        assert body["total_count"] == 0

    async def test_title_match_returns_results(self, test_client):
        """Search matching a task title returns results with scores."""
        # Create tasks
        await test_client.post("/tasks", json={
            "title": "Buy groceries from store",
            "category": "home", "transcription": "buy groceries",
        })
        await test_client.post("/tasks", json={
            "title": "Finish project report",
            "category": "career", "transcription": "finish report",
        })

        resp = await test_client.get("/tasks/search", params={
            "q": "groceries",
        })
        assert resp.status_code == 200
        body = resp.json()
        assert body["total_count"] >= 1
        assert body["query"] == "groceries"

        # First result should be the groceries task
        titles = [r["task"]["title"] for r in body["results"]]
        assert any("groceries" in t for t in titles)

        # Each result has a score
        for result in body["results"]:
            assert "score" in result
            assert isinstance(result["score"], float)
            assert result["score"] > 0

    async def test_user_isolation(self, test_client, task_service):
        """Other user's tasks should not appear in authenticated user's search."""
        # Create a task owned by a different user directly via service
        await task_service.create_task(
            user_id="other-user", title="Secret project alpha",
            category="career", transcription="secret project",
        )
        # Create a task via API (owned by "test-user" via auth override)
        await test_client.post("/tasks", json={
            "title": "Public project beta",
            "category": "career", "transcription": "public project",
        })

        # Search via API — should NOT see the other-user's task
        resp = await test_client.get("/tasks/search", params={
            "q": "secret project alpha",
        })
        assert resp.status_code == 200
        body = resp.json()
        task_ids = [r["task"]["user_id"] for r in body["results"]]
        assert "other-user" not in task_ids

    async def test_limit_parameter(self, test_client):
        """Limit parameter caps the number of results."""
        # Create several tasks with similar titles
        for i in range(5):
            await test_client.post("/tasks", json={
                "title": f"Review document {i}",
                "category": "career", "transcription": f"review doc {i}",
            })

        resp = await test_client.get("/tasks/search", params={
            "q": "review document", "limit": 2,
        })
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["results"]) <= 2

    async def test_completed_tasks_excluded(self, test_client):
        """Completed tasks should not appear in search results."""
        create_resp = await test_client.post("/tasks", json={
            "title": "Completed task cleanup",
            "category": "home", "transcription": "cleanup",
        })
        task_id = create_resp.json()["id"]

        # Complete the task
        await test_client.put(f"/tasks/{task_id}/complete")

        resp = await test_client.get("/tasks/search", params={
            "q": "completed task cleanup",
        })
        assert resp.status_code == 200
        body = resp.json()
        result_ids = [r["task"]["id"] for r in body["results"]]
        assert task_id not in result_ids

    async def test_response_structure(self, test_client):
        """Verify full response structure matches TaskSearchResponse schema."""
        await test_client.post("/tasks", json={
            "title": "Structure test task",
            "category": "career", "transcription": "structure test",
        })

        resp = await test_client.get("/tasks/search", params={
            "q": "structure test",
        })
        assert resp.status_code == 200
        body = resp.json()

        # Top-level keys
        assert "results" in body
        assert "query" in body
        assert "total_count" in body

        if body["results"]:
            result = body["results"][0]
            assert "task" in result
            assert "score" in result

            task = result["task"]
            assert "id" in task
            assert "title" in task
            assert "user_id" in task
            assert "category" in task
            assert "status" in task

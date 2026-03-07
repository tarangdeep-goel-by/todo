"""Tests for tasks API router — covers filtering, search, archive, bulk, restore, permanent delete."""
import pytest
from tests.conftest import TEST_USER_ID


def _t(title, category="career", **kwargs):
    """Task payload with required fields."""
    return {"title": title, "category": category, "transcription": title, **kwargs}


class TestGetTasksFiltering:
    """GET /tasks with various filters."""

    @pytest.mark.asyncio
    async def test_filter_by_category(self, test_client):
        await test_client.post("/tasks", json=_t("Career task", "career"))
        await test_client.post("/tasks", json=_t("Health task", "health"))

        resp = await test_client.get("/tasks", params={"category": "career"})
        assert resp.status_code == 200
        data = resp.json()
        assert all(t["category"] == "career" for t in data["tasks"])
        assert data["total_count"] >= 1

    @pytest.mark.asyncio
    async def test_filter_by_priority(self, test_client):
        await test_client.post("/tasks", json=_t("High pri", priority="high"))
        await test_client.post("/tasks", json=_t("Low pri", priority="low"))

        resp = await test_client.get("/tasks", params={"priority": "high"})
        assert resp.status_code == 200
        assert all(t["priority"] == "high" for t in resp.json()["tasks"])

    @pytest.mark.asyncio
    async def test_filter_by_status(self, test_client):
        await test_client.post("/tasks", json=_t("Active one"))
        tid2 = (await test_client.post("/tasks", json=_t("Complete me"))).json()["id"]
        await test_client.put(f"/tasks/{tid2}/complete")

        resp = await test_client.get("/tasks", params={"status": "active"})
        assert resp.status_code == 200
        assert all(t["status"] == "active" for t in resp.json()["tasks"])

    @pytest.mark.asyncio
    async def test_pagination_limit_offset(self, test_client):
        for i in range(5):
            await test_client.post("/tasks", json=_t(f"Task {i}"))

        resp = await test_client.get("/tasks", params={"limit": 2, "offset": 0})
        data = resp.json()
        assert len(data["tasks"]) == 2
        assert data["has_more"] is True
        assert data["total_count"] == 5

    @pytest.mark.asyncio
    async def test_pagination_no_more(self, test_client):
        for i in range(3):
            await test_client.post("/tasks", json=_t(f"Task {i}"))

        resp = await test_client.get("/tasks", params={"limit": 10, "offset": 0})
        assert resp.json()["has_more"] is False

    @pytest.mark.asyncio
    async def test_sort_by_priority_desc(self, test_client):
        await test_client.post("/tasks", json=_t("Low", priority="low"))
        await test_client.post("/tasks", json=_t("High", priority="high"))

        resp = await test_client.get("/tasks", params={"sort": "priority:desc"})
        priorities = [t["priority"] for t in resp.json()["tasks"] if t["priority"]]
        assert priorities[0] == "high"

    @pytest.mark.asyncio
    async def test_response_shape(self, test_client):
        await test_client.post("/tasks", json=_t("Shape test"))
        resp = await test_client.get("/tasks")
        data = resp.json()
        for key in ("tasks", "total_count", "limit", "offset", "has_more"):
            assert key in data


class TestSearch:
    """GET /tasks/search."""

    @pytest.mark.asyncio
    async def test_search_returns_results(self, test_client):
        await test_client.post("/tasks", json=_t("Buy groceries from the store", "home"))
        resp = await test_client.get("/tasks/search", params={"q": "groceries"})
        assert resp.status_code == 200
        assert resp.json()["total_count"] >= 1
        assert resp.json()["query"] == "groceries"

    @pytest.mark.asyncio
    async def test_search_no_results(self, test_client):
        resp = await test_client.get("/tasks/search", params={"q": "xyznonexistentthing"})
        assert resp.status_code == 200
        assert resp.json()["total_count"] == 0

    @pytest.mark.asyncio
    async def test_search_empty_query_rejected(self, test_client):
        resp = await test_client.get("/tasks/search", params={"q": ""})
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_search_response_shape(self, test_client):
        await test_client.post("/tasks", json=_t("Important meeting tomorrow"))
        resp = await test_client.get("/tasks/search", params={"q": "meeting"})
        data = resp.json()
        if data["total_count"] > 0:
            assert "score" in data["results"][0]
            assert "task" in data["results"][0]


class TestArchivedTasks:
    """GET /tasks/archived."""

    @pytest.mark.asyncio
    async def test_archived_list(self, test_client):
        resp = await test_client.post("/tasks", json=_t("To archive"))
        task_id = resp.json()["id"]
        await test_client.delete(f"/tasks/{task_id}")

        resp = await test_client.get("/tasks/archived")
        assert resp.status_code == 200
        assert any(t["id"] == task_id for t in resp.json()["tasks"])

    @pytest.mark.asyncio
    async def test_archived_not_in_active_list(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Will archive"))
        task_id = resp.json()["id"]
        await test_client.delete(f"/tasks/{task_id}")

        resp = await test_client.get("/tasks")
        assert all(t["id"] != task_id for t in resp.json()["tasks"])

    @pytest.mark.asyncio
    async def test_archived_pagination(self, test_client):
        ids = []
        for i in range(3):
            resp = await test_client.post("/tasks", json=_t(f"Archive {i}"))
            ids.append(resp.json()["id"])
        for tid in ids:
            await test_client.delete(f"/tasks/{tid}")

        resp = await test_client.get("/tasks/archived", params={"limit": 2, "offset": 0})
        data = resp.json()
        assert len(data["tasks"]) == 2
        assert data["has_more"] is True


class TestBulkActions:
    """POST /tasks/bulk."""

    @pytest.mark.asyncio
    async def test_bulk_complete(self, test_client):
        ids = []
        for i in range(3):
            resp = await test_client.post("/tasks", json=_t(f"Bulk {i}"))
            ids.append(resp.json()["id"])

        resp = await test_client.post("/tasks/bulk", json={"action": "complete", "task_ids": ids})
        assert resp.status_code == 200
        assert resp.json()["success"] is True
        assert resp.json()["affected_count"] == 3

    @pytest.mark.asyncio
    async def test_bulk_archive(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Bulk archive"))
        task_id = resp.json()["id"]

        resp = await test_client.post("/tasks/bulk", json={"action": "archive", "task_ids": [task_id]})
        assert resp.status_code == 200
        assert resp.json()["affected_count"] == 1

    @pytest.mark.asyncio
    async def test_bulk_unknown_action(self, test_client):
        resp = await test_client.post("/tasks/bulk", json={"action": "destroy", "task_ids": ["00000000-0000-0000-0000-000000000001"]})
        assert resp.status_code in (400, 422)  # Pydantic may reject before router

    @pytest.mark.asyncio
    async def test_bulk_response_shape(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Shape"))
        task_id = resp.json()["id"]

        resp = await test_client.post("/tasks/bulk", json={"action": "complete", "task_ids": [task_id]})
        data = resp.json()
        for key in ("success", "affected_count", "errors"):
            assert key in data


class TestRestoreTask:
    """PUT /tasks/{id}/restore."""

    @pytest.mark.asyncio
    async def test_restore_archived_task(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Restore me"))
        task_id = resp.json()["id"]
        await test_client.delete(f"/tasks/{task_id}")

        resp = await test_client.put(f"/tasks/{task_id}/restore")
        assert resp.status_code == 200
        assert resp.json()["archived_at"] is None

    @pytest.mark.asyncio
    async def test_restore_non_archived_returns_400(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Not archived"))
        task_id = resp.json()["id"]
        resp = await test_client.put(f"/tasks/{task_id}/restore")
        assert resp.status_code == 400

    @pytest.mark.asyncio
    async def test_restore_not_found(self, test_client):
        resp = await test_client.put("/tasks/00000000-0000-0000-0000-000000000999/restore")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_restore_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        await task_service.archive_task_with_children(str(task.id))
        resp = await test_client.put(f"/tasks/{task.id}/restore")
        assert resp.status_code == 403


class TestPermanentDelete:
    """DELETE /tasks/{id}/permanent."""

    @pytest.mark.asyncio
    async def test_permanent_delete(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Delete forever"))
        task_id = resp.json()["id"]

        resp = await test_client.delete(f"/tasks/{task_id}/permanent")
        assert resp.status_code == 200
        assert resp.json()["deleted_count"] >= 1

        resp = await test_client.get(f"/tasks/{task_id}")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_permanent_delete_with_children(self, test_client):
        parent = await test_client.post("/tasks", json=_t("Parent"))
        parent_id = parent.json()["id"]
        await test_client.post("/tasks", json=_t("Child", parent_id=parent_id))

        resp = await test_client.delete(f"/tasks/{parent_id}/permanent")
        assert resp.status_code == 200
        assert resp.json()["deleted_count"] == 2

    @pytest.mark.asyncio
    async def test_permanent_delete_not_found(self, test_client):
        resp = await test_client.delete("/tasks/00000000-0000-0000-0000-000000000999/permanent")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_permanent_delete_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        resp = await test_client.delete(f"/tasks/{task.id}/permanent")
        assert resp.status_code == 403


class TestReparenting:
    """PATCH /tasks/{id} with parent_id changes."""

    @pytest.mark.asyncio
    async def test_reparent_success(self, test_client):
        parent = await test_client.post("/tasks", json=_t("New Parent"))
        parent_id = parent.json()["id"]
        child = await test_client.post("/tasks", json=_t("Child"))
        child_id = child.json()["id"]

        resp = await test_client.patch(f"/tasks/{child_id}", json={"parent_id": parent_id})
        assert resp.status_code == 200
        assert resp.json()["parent_id"] == parent_id

    @pytest.mark.asyncio
    async def test_reparent_nonexistent_parent(self, test_client):
        child = await test_client.post("/tasks", json=_t("Child"))
        child_id = child.json()["id"]

        resp = await test_client.patch(f"/tasks/{child_id}", json={"parent_id": "00000000-0000-0000-0000-000000000999"})
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_reparent_cross_user_parent(self, test_client, task_service):
        other = await task_service.create_task(
            user_id="other-user", title="Other's parent", category="career", transcription="other")
        child = await test_client.post("/tasks", json=_t("My child"))
        child_id = child.json()["id"]

        resp = await test_client.patch(f"/tasks/{child_id}", json={"parent_id": str(other.id)})
        assert resp.status_code == 403


class TestAuthChecks:
    """Verify 403 for cross-user access on key endpoints."""

    @pytest.mark.asyncio
    async def test_get_task_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        resp = await test_client.get(f"/tasks/{task.id}")
        assert resp.status_code == 403

    @pytest.mark.asyncio
    async def test_update_task_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        resp = await test_client.patch(f"/tasks/{task.id}", json={"title": "Hacked"})
        assert resp.status_code == 403

    @pytest.mark.asyncio
    async def test_complete_task_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        resp = await test_client.put(f"/tasks/{task.id}/complete")
        assert resp.status_code == 403

    @pytest.mark.asyncio
    async def test_delete_task_wrong_user(self, test_client, task_service):
        task = await task_service.create_task(
            user_id="other-user", title="Other's", category="career", transcription="other")
        resp = await test_client.delete(f"/tasks/{task.id}")
        assert resp.status_code == 403


class TestCreateTask:
    """POST /tasks — creation tests."""

    @pytest.mark.asyncio
    async def test_create_returns_201(self, test_client):
        resp = await test_client.post("/tasks", json=_t("New task"))
        assert resp.status_code == 201
        assert resp.json()["title"] == "new task"
        assert resp.json()["status"] == "active"

    @pytest.mark.asyncio
    async def test_create_with_all_fields(self, test_client):
        resp = await test_client.post("/tasks", json=_t(
            "Full task", priority="high", due_date="2026-06-01T10:00:00Z",
            description="A detailed description", tags=["urgent"],
        ))
        assert resp.status_code == 201
        data = resp.json()
        assert data["priority"] == "high"
        assert data["description"] == "A detailed description"

    @pytest.mark.asyncio
    async def test_create_with_parent(self, test_client):
        parent = await test_client.post("/tasks", json=_t("Parent"))
        parent_id = parent.json()["id"]
        child = await test_client.post("/tasks", json=_t("Child", parent_id=parent_id))
        assert child.status_code == 201
        assert child.json()["parent_id"] == parent_id

    @pytest.mark.asyncio
    async def test_create_missing_title_422(self, test_client):
        resp = await test_client.post("/tasks", json={"category": "career", "transcription": "x"})
        assert resp.status_code == 422


class TestGetSingleTask:
    """GET /tasks/{id}."""

    @pytest.mark.asyncio
    async def test_get_task_success(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Fetch me"))
        task_id = resp.json()["id"]
        resp = await test_client.get(f"/tasks/{task_id}")
        assert resp.status_code == 200
        assert resp.json()["title"] == "fetch me"

    @pytest.mark.asyncio
    async def test_get_task_not_found(self, test_client):
        resp = await test_client.get("/tasks/00000000-0000-0000-0000-000000000999")
        assert resp.status_code == 404


class TestUpdateTask:
    """PATCH /tasks/{id} — update tests."""

    @pytest.mark.asyncio
    async def test_update_title(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Original"))
        task_id = resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={"title": "Updated"})
        assert resp.status_code == 200
        assert resp.json()["title"] == "updated"

    @pytest.mark.asyncio
    async def test_update_multiple_fields(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Multi"))
        task_id = resp.json()["id"]
        resp = await test_client.patch(f"/tasks/{task_id}", json={
            "priority": "high",
            "description": "Updated desc",
        })
        assert resp.status_code == 200
        assert resp.json()["priority"] == "high"
        assert resp.json()["description"] == "Updated desc"

    @pytest.mark.asyncio
    async def test_update_not_found(self, test_client):
        resp = await test_client.patch("/tasks/00000000-0000-0000-0000-000000000999", json={"title": "X"})
        assert resp.status_code == 404


class TestCompleteTask:
    """PUT /tasks/{id}/complete."""

    @pytest.mark.asyncio
    async def test_complete_single(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Complete me"))
        task_id = resp.json()["id"]
        resp = await test_client.put(f"/tasks/{task_id}/complete")
        assert resp.status_code == 200
        assert resp.json()["status"] == "completed"

    @pytest.mark.asyncio
    async def test_complete_with_children(self, test_client):
        parent = await test_client.post("/tasks", json=_t("Parent"))
        pid = parent.json()["id"]
        child = await test_client.post("/tasks", json=_t("Child", parent_id=pid))
        cid = child.json()["id"]

        resp = await test_client.put(f"/tasks/{pid}/complete")
        assert resp.status_code == 200

        child_resp = await test_client.get(f"/tasks/{cid}")
        assert child_resp.json()["status"] == "completed"

    @pytest.mark.asyncio
    async def test_complete_not_found(self, test_client):
        resp = await test_client.put("/tasks/00000000-0000-0000-0000-000000000999/complete")
        assert resp.status_code == 404


class TestTaskStats:
    """GET /tasks/stats."""

    @pytest.mark.asyncio
    async def test_stats_response_shape(self, test_client):
        await test_client.post("/tasks", json=_t("Stats task"))
        resp = await test_client.get("/tasks/stats")
        assert resp.status_code == 200
        data = resp.json()
        assert "total_tasks" in data
        assert "by_status" in data
        assert "by_priority" in data

    @pytest.mark.asyncio
    async def test_stats_counts(self, test_client):
        await test_client.post("/tasks", json=_t("Active 1"))
        resp2 = await test_client.post("/tasks", json=_t("Complete me"))
        await test_client.put(f"/tasks/{resp2.json()['id']}/complete")
        resp = await test_client.get("/tasks/stats")
        data = resp.json()
        assert data["by_status"]["active"] >= 1
        assert data["by_status"]["completed"] >= 1


class TestDeleteTaskArchive:
    """DELETE /tasks/{id} — archive (soft delete)."""

    @pytest.mark.asyncio
    async def test_archive_task(self, test_client):
        resp = await test_client.post("/tasks", json=_t("Archive me"))
        task_id = resp.json()["id"]
        resp = await test_client.delete(f"/tasks/{task_id}")
        assert resp.status_code == 200
        assert resp.json()["success"] is True
        assert resp.json()["archived_count"] >= 1

    @pytest.mark.asyncio
    async def test_archive_not_found(self, test_client):
        resp = await test_client.delete("/tasks/00000000-0000-0000-0000-000000000999")
        assert resp.status_code == 404


class TestUUIDValidation:
    """Invalid UUIDs should return 422, not 500."""

    @pytest.mark.asyncio
    async def test_get_task_invalid_uuid(self, test_client):
        resp = await test_client.get("/tasks/not-a-uuid")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_update_task_invalid_uuid(self, test_client):
        resp = await test_client.patch("/tasks/not-a-uuid", json={"title": "x"})
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_complete_task_invalid_uuid(self, test_client):
        resp = await test_client.put("/tasks/not-a-uuid/complete")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_delete_task_invalid_uuid(self, test_client):
        resp = await test_client.delete("/tasks/not-a-uuid")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_restore_task_invalid_uuid(self, test_client):
        resp = await test_client.put("/tasks/not-a-uuid/restore")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_permanent_delete_invalid_uuid(self, test_client):
        resp = await test_client.delete("/tasks/not-a-uuid/permanent")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_delete_category_invalid_uuid(self, test_client):
        resp = await test_client.delete("/categories/not-a-uuid")
        assert resp.status_code == 422

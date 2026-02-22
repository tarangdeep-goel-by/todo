"""Tests for categories CRUD and API — 11 tests."""
import pytest


class TestCategoryService:
    """Service-level tests for category CRUD."""

    async def test_create_category(self, task_service):
        cat = await task_service.create_category("test-user", "work")
        assert cat.name == "work"
        assert cat.position == 0
        assert cat.user_id == "test-user"

    async def test_create_assigns_lowest_unused_position(self, task_service):
        await task_service.create_category("test-user", "work")     # pos 0
        await task_service.create_category("test-user", "personal") # pos 1
        await task_service.delete_category(
            (await task_service.get_categories_from_db("test-user"))[0].id,
            "test-user",
        )
        # Position 0 is now free
        cat = await task_service.create_category("test-user", "health")
        assert cat.position == 0

    async def test_create_duplicate_rejected(self, task_service):
        await task_service.create_category("test-user", "work")
        with pytest.raises(ValueError, match="already exists"):
            await task_service.create_category("test-user", "work")

    async def test_create_max_five(self, task_service):
        for name in ["a", "b", "c", "d", "e"]:
            await task_service.create_category("test-user", name)
        with pytest.raises(ValueError, match="Maximum"):
            await task_service.create_category("test-user", "f")

    async def test_get_categories_returns_names(self, task_service):
        await task_service.create_category("test-user", "work")
        await task_service.create_category("test-user", "personal")
        names = await task_service.get_categories("test-user")
        assert names == ["work", "personal"]

    async def test_count_categories(self, task_service):
        assert await task_service.count_categories("test-user") == 0
        await task_service.create_category("test-user", "work")
        assert await task_service.count_categories("test-user") == 1

    async def test_delete_category(self, task_service):
        cat = await task_service.create_category("test-user", "work")
        assert await task_service.delete_category(cat.id, "test-user") is True
        assert await task_service.count_categories("test-user") == 0

    async def test_delete_nonexistent(self, task_service):
        assert await task_service.delete_category(
            "ffffffff-ffff-ffff-ffff-ffffffffffff", "test-user"
        ) is False


class TestCategoryAPI:
    """HTTP endpoint tests for /api/categories."""

    async def test_list_empty(self, test_client):
        resp = await test_client.get("/categories", params={"user_id": "test-user"})
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_create_and_list(self, test_client):
        resp = await test_client.post("/categories", json={
            "user_id": "test-user", "name": "work",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "work"
        assert data["position"] == 0

        resp = await test_client.get("/categories", params={"user_id": "test-user"})
        assert len(resp.json()) == 1

    async def test_create_duplicate_400(self, test_client):
        await test_client.post("/categories", json={
            "user_id": "test-user", "name": "work",
        })
        resp = await test_client.post("/categories", json={
            "user_id": "test-user", "name": "work",
        })
        assert resp.status_code == 400

    async def test_delete_category(self, test_client):
        resp = await test_client.post("/categories", json={
            "user_id": "test-user", "name": "work",
        })
        cat_id = resp.json()["id"]
        resp = await test_client.delete(
            f"/categories/{cat_id}", params={"user_id": "test-user"}
        )
        assert resp.status_code == 200

    async def test_delete_nonexistent_404(self, test_client):
        resp = await test_client.delete(
            "/categories/ffffffff-ffff-ffff-ffff-ffffffffffff",
            params={"user_id": "test-user"},
        )
        assert resp.status_code == 404

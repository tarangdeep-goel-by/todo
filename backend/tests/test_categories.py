"""Tests for categories CRUD and API — 12 tests."""
import pytest


class TestCategoryService:
    """Service-level tests for category CRUD."""

    async def test_task_has_category_id_fk(self, task_service):
        """Created task should have category_id pointing to the category row."""
        cat = await task_service.create_category("test-user", "career")
        task = await task_service.create_task(
            user_id="test-user", title="FK test", category="career",
            transcription="fk test",
        )
        assert task.category_id == cat.id

    async def test_task_resolves_category_id_automatically(self, task_service):
        """When category_id is not passed, create_task resolves it from category string."""
        cat = await task_service.create_category("test-user", "home")
        task = await task_service.create_task(
            user_id="test-user", title="Auto resolve", category="home",
            transcription="auto resolve",
        )
        assert task.category_id == cat.id

    async def test_task_category_id_none_when_no_category_row(self, task_service):
        """When no matching category exists, category_id is None."""
        task = await task_service.create_task(
            user_id="test-user", title="No cat row", category="nonexistent",
            transcription="no cat",
        )
        assert task.category_id is None

    async def test_create_category(self, task_service):
        cat = await task_service.create_category("test-user", "career")
        assert cat.name == "career"
        assert cat.position == 0
        assert cat.user_id == "test-user"

    async def test_create_assigns_lowest_unused_position(self, task_service):
        await task_service.create_category("test-user", "career")     # pos 0
        await task_service.create_category("test-user", "home")       # pos 1
        await task_service.delete_category(
            (await task_service.get_categories_from_db("test-user"))[0].id,
            "test-user",
        )
        # Position 0 is now free
        cat = await task_service.create_category("test-user", "health")
        assert cat.position == 0

    async def test_create_duplicate_rejected(self, task_service):
        await task_service.create_category("test-user", "career")
        with pytest.raises(ValueError, match="already exists"):
            await task_service.create_category("test-user", "career")

    async def test_create_max_eight(self, task_service):
        for name in ["a", "b", "c", "d", "e", "f", "g", "h"]:
            await task_service.create_category("test-user", name)
        with pytest.raises(ValueError, match="Maximum"):
            await task_service.create_category("test-user", "i")

    async def test_get_categories_returns_names(self, task_service):
        await task_service.create_category("test-user", "career")
        await task_service.create_category("test-user", "home")
        names = await task_service.get_categories("test-user")
        assert names == ["career", "home"]

    async def test_count_categories(self, task_service):
        assert await task_service.count_categories("test-user") == 0
        await task_service.create_category("test-user", "career")
        assert await task_service.count_categories("test-user") == 1

    async def test_delete_category(self, task_service):
        cat = await task_service.create_category("test-user", "career")
        assert await task_service.delete_category(cat.id, "test-user") is True
        assert await task_service.count_categories("test-user") == 0

    async def test_delete_nonexistent(self, task_service):
        assert await task_service.delete_category(
            "ffffffff-ffff-ffff-ffff-ffffffffffff", "test-user"
        ) is False


class TestCategoryAPI:
    """HTTP endpoint tests for /api/categories."""

    async def test_list_empty(self, test_client):
        resp = await test_client.get("/categories")
        assert resp.status_code == 200
        assert resp.json() == []

    async def test_create_and_list(self, test_client):
        resp = await test_client.post("/categories", json={"name": "career"})
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "career"
        assert data["position"] == 0

        resp = await test_client.get("/categories")
        assert len(resp.json()) == 1

    async def test_create_duplicate_400(self, test_client):
        await test_client.post("/categories", json={"name": "career"})
        resp = await test_client.post("/categories", json={"name": "career"})
        assert resp.status_code == 400

    async def test_delete_category(self, test_client):
        resp = await test_client.post("/categories", json={"name": "career"})
        cat_id = resp.json()["id"]
        resp = await test_client.delete(f"/categories/{cat_id}")
        assert resp.status_code == 200

    async def test_delete_nonexistent_404(self, test_client):
        resp = await test_client.delete(
            "/categories/ffffffff-ffff-ffff-ffff-ffffffffffff",
        )
        assert resp.status_code == 404

"""Tests for categories API router."""
import pytest
from tests.conftest import TEST_USER_ID


class TestCategoriesRouter:
    """Tests for /api/categories endpoints."""

    @pytest.mark.asyncio
    async def test_list_categories_empty(self, test_client):
        """Empty list when no categories created."""
        resp = await test_client.get("/categories")
        assert resp.status_code == 200
        assert resp.json() == []

    @pytest.mark.asyncio
    async def test_create_category(self, test_client):
        """Create a category returns 201 with name."""
        resp = await test_client.post("/categories", json={"name": "career"})
        assert resp.status_code == 201
        data = resp.json()
        assert data["name"] == "career"
        assert "id" in data

    @pytest.mark.asyncio
    async def test_create_duplicate_category(self, test_client):
        """Creating same category name twice returns 400."""
        await test_client.post("/categories", json={"name": "health"})
        resp = await test_client.post("/categories", json={"name": "health"})
        assert resp.status_code == 400

    @pytest.mark.asyncio
    async def test_list_categories_after_create(self, test_client):
        """List returns created categories."""
        await test_client.post("/categories", json={"name": "finance"})
        resp = await test_client.get("/categories")
        assert resp.status_code == 200
        names = [c["name"] for c in resp.json()]
        assert "finance" in names

    @pytest.mark.asyncio
    async def test_delete_category(self, test_client):
        """Delete a category returns success."""
        resp = await test_client.post("/categories", json={"name": "recreation"})
        cat_id = resp.json()["id"]
        resp = await test_client.delete(f"/categories/{cat_id}")
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    @pytest.mark.asyncio
    async def test_delete_nonexistent_category(self, test_client):
        """Delete nonexistent category returns 404."""
        resp = await test_client.delete("/categories/00000000-0000-0000-0000-000000000999")
        assert resp.status_code == 404

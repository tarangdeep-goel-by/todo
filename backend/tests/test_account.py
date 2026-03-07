"""Tests for account deletion (GDPR)."""
import pytest
from tests.conftest import TEST_USER_ID


def _t(title, category="career", **kwargs):
    return {"title": title, "category": category, "transcription": title, **kwargs}


class TestAccountDeletion:
    """DELETE /account — removes all user data."""

    @pytest.mark.asyncio
    async def test_delete_account_removes_tasks(self, test_client):
        await test_client.post("/tasks", json=_t("Task 1"))
        await test_client.post("/tasks", json=_t("Task 2"))

        resp = await test_client.delete("/account")
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["deleted"]["tasks"] >= 2

        # Verify tasks are gone
        resp = await test_client.get("/tasks")
        assert resp.json()["total_count"] == 0

    @pytest.mark.asyncio
    async def test_delete_account_removes_categories(self, test_client):
        await test_client.post("/categories", json={"name": "career"})

        resp = await test_client.delete("/account")
        assert resp.status_code == 200
        assert resp.json()["deleted"]["categories"] >= 1

        # Verify categories are gone
        resp = await test_client.get("/categories")
        assert len(resp.json()) == 0

    @pytest.mark.asyncio
    async def test_delete_account_empty_user(self, test_client):
        """Deleting account with no data should succeed."""
        resp = await test_client.delete("/account")
        assert resp.status_code == 200
        assert resp.json()["success"] is True

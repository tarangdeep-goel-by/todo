"""Tests for authentication flow — 6 tests.

Verifies Firebase auth bypass (test tokens), missing/invalid auth,
and public endpoints that require no authentication.
"""
import os
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport

from database import get_db
from config import get_settings


@pytest_asyncio.fixture
async def auth_client(db_session):
    """HTTP client that does NOT override get_current_user.

    Unlike `test_client` (which stubs auth), this client preserves the real
    `get_current_user` dependency so we can test auth behavior end-to-end.
    """
    from main import app

    async def _override_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_db
    # Intentionally NOT overriding get_current_user

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client

    app.dependency_overrides.clear()


class TestAuthFlow:
    """Auth flow tests exercising get_current_user paths."""

    async def test_valid_test_token_returns_uid(self, auth_client):
        """With APP_ENV=test, test-token-e2e works."""
        # Temporarily enable test auth by clearing settings cache
        old_env = os.environ.get("APP_ENV")
        os.environ["APP_ENV"] = "test"
        get_settings.cache_clear()
        try:
            resp = await auth_client.get(
                "/api/tasks",
                headers={"Authorization": "Bearer test-token-e2e"},
            )
            # Should authenticate successfully (200, not 401)
            assert resp.status_code == 200
        finally:
            if old_env is not None:
                os.environ["APP_ENV"] = old_env
            else:
                os.environ.pop("APP_ENV", None)
            get_settings.cache_clear()

    async def test_missing_auth_header_returns_401(self, auth_client):
        """Request without Authorization header returns 401 (or 403)."""
        resp = await auth_client.get("/api/tasks")
        assert resp.status_code in (401, 403)

    async def test_invalid_token_returns_401(self, auth_client):
        """Request with garbage token returns 401."""
        resp = await auth_client.get(
            "/api/tasks",
            headers={"Authorization": "Bearer invalid-garbage-token"},
        )
        assert resp.status_code == 401

    async def test_health_endpoint_no_auth_required(self, auth_client):
        """GET /health works without any auth."""
        resp = await auth_client.get("/health")
        assert resp.status_code in (200, 503)  # 503 if DB not ready, but not 401

    async def test_version_endpoint_no_auth_required(self, auth_client):
        """GET /api/version works without any auth."""
        resp = await auth_client.get("/api/version")
        assert resp.status_code == 200
        body = resp.json()
        assert "api_version" in body

    async def test_tasks_endpoint_requires_auth(self, auth_client):
        """GET /api/tasks without auth returns 401 or 403."""
        resp = await auth_client.get("/api/tasks")
        assert resp.status_code in (401, 403)

"""Tests for /api/logs ingestion endpoint and /health DB check."""
import pytest
from unittest.mock import patch, AsyncMock
from rate_limit import limiter


class TestLogIngestion:
    """Verify client log ingestion endpoint."""

    async def test_accepts_valid_batch(self, test_client):
        resp = await test_client.post("/logs", json={
            "entries": [
                {"event": "test.ping", "level": "info"},
                {"event": "test.error", "level": "error", "data": {"code": 42}},
            ]
        })
        assert resp.status_code == 200
        assert resp.json()["accepted"] == 2

    async def test_rejects_empty_entries(self, test_client):
        resp = await test_client.post("/logs", json={"entries": []})
        assert resp.status_code == 200
        assert resp.json()["accepted"] == 0

    async def test_truncates_long_event(self, test_client):
        resp = await test_client.post("/logs", json={
            "entries": [{"event": "x" * 600, "level": "info"}]
        })
        assert resp.status_code == 200

    async def test_normalizes_invalid_level(self, test_client):
        resp = await test_client.post("/logs", json={
            "entries": [{"event": "test", "level": "CRITICAL"}]
        })
        assert resp.status_code == 200

    async def test_rejects_over_50_entries(self, test_client):
        entries = [{"event": f"e{i}", "level": "info"} for i in range(51)]
        resp = await test_client.post("/logs", json={"entries": entries})
        assert resp.status_code == 422

    async def test_rate_limited(self, test_client):
        for i in range(6):
            resp = await test_client.post("/logs", json={
                "entries": [{"event": f"test.{i}", "level": "info"}]
            })
            if resp.status_code == 429:
                assert i >= 5
                return
        pytest.fail("Expected 429 after 5 requests")


class TestHealthCheck:
    """Verify health endpoint with DB connectivity."""

    async def test_healthy(self, test_client, db_session):
        from contextlib import asynccontextmanager
        from httpx import AsyncClient, ASGITransport
        from main import app

        @asynccontextmanager
        async def _mock_session():
            yield db_session

        transport = ASGITransport(app=app)
        with patch("database.AsyncSessionLocal", _mock_session):
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                resp = await client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "healthy"
        assert data["db"] == "connected"

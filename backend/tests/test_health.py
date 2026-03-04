"""Tests for GET /health endpoint — timestamp feature."""

import pytest
import pytest_asyncio
from datetime import datetime, timezone, timedelta
from httpx import AsyncClient, ASGITransport

from main import app

BASE_URL = "http://test"


@pytest_asyncio.fixture
async def client():
    """Lightweight client for root-level endpoints (no DB needed)."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url=BASE_URL) as c:
        yield c


class TestHealthEndpoint:
    """GET /health returns status and UTC timestamp."""

    async def test_returns_200(self, client):
        resp = await client.get("/health")
        assert resp.status_code == 200

    async def test_status_field_present(self, client):
        resp = await client.get("/health")
        assert "status" in resp.json()
        assert isinstance(resp.json()["status"], str)
        assert len(resp.json()["status"]) > 0

    async def test_timestamp_field_present(self, client):
        body = (await client.get("/health")).json()
        assert "timestamp" in body

    async def test_timestamp_is_string(self, client):
        body = (await client.get("/health")).json()
        assert isinstance(body["timestamp"], str)

    async def test_timestamp_is_valid_iso8601(self, client):
        body = (await client.get("/health")).json()
        ts = body["timestamp"]
        # Must parse without error
        parsed = datetime.fromisoformat(ts)
        assert parsed is not None

    async def test_timestamp_is_utc(self, client):
        body = (await client.get("/health")).json()
        parsed = datetime.fromisoformat(body["timestamp"])
        assert parsed.tzinfo is not None
        assert parsed.utcoffset() == timedelta(0)

    async def test_timestamp_is_recent(self, client):
        before = datetime.now(timezone.utc)
        body = (await client.get("/health")).json()
        after = datetime.now(timezone.utc)
        parsed = datetime.fromisoformat(body["timestamp"])
        assert before <= parsed <= after

    async def test_response_contains_required_keys(self, client):
        body = (await client.get("/health")).json()
        assert "status" in body
        assert "timestamp" in body

    async def test_successive_calls_return_current_time(self, client):
        body1 = (await client.get("/health")).json()
        body2 = (await client.get("/health")).json()
        ts1 = datetime.fromisoformat(body1["timestamp"])
        ts2 = datetime.fromisoformat(body2["timestamp"])
        # Second call should be same or later
        assert ts2 >= ts1

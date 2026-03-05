"""Tests for security hardening: rate limiting, audit logging."""
import json
import logging
import pytest
from rate_limit import limiter


class TestRateLimiting:
    """Verify rate limits on expensive endpoints."""

    async def test_braindump_rate_limit(self, test_client):
        """POST /agent/braindump returns 429 after exceeding 10/minute."""
        # Reset limiter state so prior tests don't interfere
        limiter.reset()

        for i in range(11):
            resp = await test_client.post("/agent/braindump", json={
                "transcription": f"test task {i}",
            })
            if resp.status_code == 429:
                assert i >= 10  # should not hit before the 11th request
                return

        pytest.fail("Expected 429 after 10 requests, but never received it")

    async def test_search_rate_limit(self, test_client):
        """GET /tasks/search returns 429 after exceeding 30/minute."""
        limiter.reset()

        for i in range(31):
            resp = await test_client.get("/tasks/search", params={"q": "test"})
            if resp.status_code == 429:
                assert i >= 30
                return

        pytest.fail("Expected 429 after 30 requests, but never received it")


class TestAuditLogging:
    """Verify audit log entries for security-sensitive operations."""

    async def test_task_delete_audit_log(self, test_client, caplog):
        """Deleting a task emits an audit log entry."""
        # Create a task
        create_resp = await test_client.post("/tasks", json={
            "title": "To Delete", "category": "home",
            "transcription": "delete me",
        })
        task_id = create_resp.json()["id"]

        # Delete it with audit logger captured
        with caplog.at_level(logging.INFO, logger="audit"):
            resp = await test_client.delete(f"/tasks/{task_id}")
            assert resp.status_code == 200

        # Find the audit log entry
        audit_entries = [r for r in caplog.records if r.name == "audit"]
        assert len(audit_entries) >= 1
        entry = json.loads(audit_entries[-1].message)
        assert entry["event"] == "task.deleted"
        assert entry["resource_id"] == task_id

    async def test_category_delete_audit_log(self, test_client, caplog):
        """Deleting a category emits an audit log entry."""
        # Create a category
        create_resp = await test_client.post("/categories", json={"name": "TestCat"})
        cat_id = create_resp.json()["id"]

        with caplog.at_level(logging.INFO, logger="audit"):
            resp = await test_client.delete(f"/categories/{cat_id}")
            assert resp.status_code == 200

        audit_entries = [r for r in caplog.records if r.name == "audit"]
        assert len(audit_entries) >= 1
        entry = json.loads(audit_entries[-1].message)
        assert entry["event"] == "category.deleted"
        assert entry["resource_id"] == cat_id

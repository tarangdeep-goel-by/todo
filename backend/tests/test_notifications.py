"""Tests for push notification token management and due-task reminder logic."""
import pytest
import pytest_asyncio
from datetime import datetime, timedelta, timezone
from unittest.mock import patch, MagicMock

from sqlalchemy import select, text
from tests.conftest import TEST_USER_ID
from models.fcm_token import FcmToken
from models.task import Task
from services.notification_service import NotificationService


# ──────────────── Token registration (API) ────────────────


class TestTokenRegistration:
    """Tests for POST/DELETE /api/notifications/token."""

    @pytest.mark.asyncio
    async def test_register_token_creates_record(self, test_client, db_session):
        """Register a new FCM token → DB record created with correct fields."""
        resp = await test_client.post("/notifications/token", json={
            "token": "fcm-token-abc123",
            "platform": "android",
            "timezone": "Asia/Kolkata",
        })
        assert resp.status_code == 200

        result = await db_session.execute(
            select(FcmToken).where(FcmToken.token == "fcm-token-abc123")
        )
        token = result.scalar_one()
        assert token.user_id == TEST_USER_ID
        assert token.platform == "android"
        assert token.timezone == "Asia/Kolkata"

    @pytest.mark.asyncio
    async def test_register_same_token_upserts(self, test_client, db_session):
        """Register same token twice → upsert (updated_at changes, no duplicate)."""
        payload = {
            "token": "fcm-token-upsert",
            "platform": "android",
            "timezone": "UTC",
        }
        resp1 = await test_client.post("/notifications/token", json=payload)
        assert resp1.status_code == 200

        # Get first record
        result = await db_session.execute(
            select(FcmToken).where(FcmToken.token == "fcm-token-upsert")
        )
        first = result.scalar_one()
        first_updated = first.updated_at

        # Register again with different timezone
        payload["timezone"] = "America/New_York"
        resp2 = await test_client.post("/notifications/token", json=payload)
        assert resp2.status_code == 200

        # Should still be one record
        db_session.expire_all()
        result = await db_session.execute(
            select(FcmToken).where(FcmToken.token == "fcm-token-upsert")
        )
        tokens = result.scalars().all()
        assert len(tokens) == 1
        assert tokens[0].timezone == "America/New_York"

    @pytest.mark.asyncio
    async def test_delete_token_removes_record(self, test_client, db_session):
        """Delete token → record removed from DB."""
        # Register first
        await test_client.post("/notifications/token", json={
            "token": "fcm-token-delete-me",
            "platform": "ios",
            "timezone": "UTC",
        })

        # Delete
        resp = await test_client.request("DELETE", "/notifications/token", json={
            "token": "fcm-token-delete-me",
        })
        assert resp.status_code == 200

        result = await db_session.execute(
            select(FcmToken).where(FcmToken.token == "fcm-token-delete-me")
        )
        assert result.scalar_one_or_none() is None

    @pytest.mark.asyncio
    async def test_register_token_validates_platform(self, test_client):
        """Invalid platform rejected."""
        resp = await test_client.post("/notifications/token", json={
            "token": "fcm-token-bad",
            "platform": "windows",
            "timezone": "UTC",
        })
        assert resp.status_code == 422


# ──────────────── Due-task query logic ────────────────


class TestDueTaskReminders:
    """Tests for NotificationService.get_due_tasks() query windows and dedup."""

    async def _create_task(self, db_session, due_date, last_notified_at=None, status="active"):
        """Helper to create a task with specific due_date and notification state."""
        import uuid
        task = Task(
            id=str(uuid.uuid4()),
            user_id=TEST_USER_ID,
            title=f"Task due {due_date}",
            category="health",
            status=status,
            due_date=due_date,
            last_notified_at=last_notified_at,
            transcription="test",
            ai_placement_json={"action": "add"},
        )
        db_session.add(task)
        await db_session.commit()
        return task

    @pytest.mark.asyncio
    async def test_due_soon_60min_window(self, db_session):
        """Task due within 60 minutes → included in reminders."""
        now = datetime.now(timezone.utc)
        await self._create_task(db_session, due_date=now + timedelta(minutes=30))

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 1
        assert "Task due" in tasks[0].title

    @pytest.mark.asyncio
    async def test_due_tomorrow_24hr_window(self, db_session):
        """Task due in 23-24 hours → included in reminders."""
        now = datetime.now(timezone.utc)
        await self._create_task(db_session, due_date=now + timedelta(hours=23, minutes=30))

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 1

    @pytest.mark.asyncio
    async def test_task_outside_windows_excluded(self, db_session):
        """Task due in 5 hours → not in any window → excluded."""
        now = datetime.now(timezone.utc)
        await self._create_task(db_session, due_date=now + timedelta(hours=5))

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 0

    @pytest.mark.asyncio
    async def test_dedup_skip_recently_notified(self, db_session):
        """Task notified 2 hours ago (within 4hr dedup) → skipped."""
        now = datetime.now(timezone.utc)
        await self._create_task(
            db_session,
            due_date=now + timedelta(minutes=30),
            last_notified_at=now - timedelta(hours=2),
        )

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 0

    @pytest.mark.asyncio
    async def test_dedup_include_old_notification(self, db_session):
        """Task notified 5 hours ago (outside 4hr dedup) → included."""
        now = datetime.now(timezone.utc)
        await self._create_task(
            db_session,
            due_date=now + timedelta(minutes=30),
            last_notified_at=now - timedelta(hours=5),
        )

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 1

    @pytest.mark.asyncio
    async def test_completed_tasks_excluded(self, db_session):
        """Completed tasks are never included in reminders."""
        now = datetime.now(timezone.utc)
        await self._create_task(
            db_session,
            due_date=now + timedelta(minutes=30),
            status="completed",
        )

        svc = NotificationService(db_session)
        tasks = await svc.get_due_tasks()
        assert len(tasks) == 0

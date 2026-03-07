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


# ──────────────── send_to_user (mocked FCM) ────────────────


class TestSendToUser:
    """Tests for NotificationService.send_to_user() with mocked FCM."""

    async def _add_token(self, db_session, token_str="test-token-1", user_id=TEST_USER_ID):
        token = FcmToken(user_id=user_id, token=token_str, platform="android", timezone="UTC")
        db_session.add(token)
        await db_session.commit()
        return token

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_send_success(self, mock_messaging, db_session):
        """Successful send returns success_count."""
        await self._add_token(db_session, "token-a")
        await self._add_token(db_session, "token-b")

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None), MagicMock(exception=None)]
        mock_resp.success_count = 2
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        count = await svc.send_to_user(TEST_USER_ID, "Title", "Body")
        assert count == 2

    @pytest.mark.asyncio
    async def test_send_no_tokens(self, db_session):
        """No tokens for user returns 0 without calling FCM."""
        svc = NotificationService(db_session)
        count = await svc.send_to_user(TEST_USER_ID, "Title", "Body")
        assert count == 0

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_unregistered_token_cleaned_up(self, mock_messaging, db_session):
        """UnregisteredError on a token deletes it from DB."""
        await self._add_token(db_session, "good-token")
        await self._add_token(db_session, "dead-token")

        # Create a real exception class for isinstance() to work
        class _UnregisteredError(Exception):
            pass
        mock_messaging.UnregisteredError = _UnregisteredError

        mock_resp = MagicMock()
        good_send = MagicMock(exception=None)
        dead_send = MagicMock()
        dead_send.exception = _UnregisteredError("token expired")
        mock_resp.responses = [good_send, dead_send]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        count = await svc.send_to_user(TEST_USER_ID, "Title", "Body")
        assert count == 1

        # Dead token deleted
        result = await db_session.execute(select(FcmToken).where(FcmToken.token == "dead-token"))
        assert result.scalar_one_or_none() is None
        # Good token still exists
        result = await db_session.execute(select(FcmToken).where(FcmToken.token == "good-token"))
        assert result.scalar_one_or_none() is not None

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_send_with_data_payload(self, mock_messaging, db_session):
        """Data dict passed through to messaging.Message."""
        await self._add_token(db_session)

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None)]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        await svc.send_to_user(TEST_USER_ID, "Title", "Body", data={"task_id": "abc"})

        mock_messaging.send_each.assert_called_once()
        messages = mock_messaging.send_each.call_args[0][0]
        assert len(messages) == 1


# ──────────────── check_and_send_due_reminders ────────────────


class TestDueReminderConsolidation:
    """Tests for consolidated notification sending."""

    async def _create_due_task(self, db_session, title="Due task", user_id=TEST_USER_ID, minutes_from_now=30):
        import uuid
        now = datetime.now(timezone.utc)
        task = Task(
            id=str(uuid.uuid4()),
            user_id=user_id,
            title=title,
            category="health",
            status="active",
            due_date=now + timedelta(minutes=minutes_from_now),
            transcription="test",
            ai_placement_json={"action": "add"},
        )
        db_session.add(task)
        await db_session.commit()
        return task

    async def _add_token(self, db_session, token_str="reminder-token", user_id=TEST_USER_ID):
        token = FcmToken(user_id=user_id, token=token_str, platform="android", timezone="UTC")
        db_session.add(token)
        await db_session.commit()

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_single_task_title(self, mock_messaging, db_session):
        """Single due task: title='Task due soon', body=task title."""
        await self._create_due_task(db_session, title="Call dentist")
        await self._add_token(db_session)

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None)]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        total = await svc.check_and_send_due_reminders()
        assert total == 1

        call_args = mock_messaging.Notification.call_args
        title = call_args.kwargs.get("title") or call_args[1].get("title")
        assert title == "Task due soon"

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_multi_task_title(self, mock_messaging, db_session):
        """3 due tasks: title='3 tasks due soon'."""
        for t in ["Task A", "Task B", "Task C"]:
            await self._create_due_task(db_session, title=t)
        await self._add_token(db_session)

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None)]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        total = await svc.check_and_send_due_reminders()
        assert total == 3

        call_args = mock_messaging.Notification.call_args
        title = call_args.kwargs.get("title") or call_args[1].get("title")
        assert title == "3 tasks due soon"

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_more_than_3_ellipsis(self, mock_messaging, db_session):
        """5 due tasks: body contains 'and 2 more'."""
        for i in range(5):
            await self._create_due_task(db_session, title=f"Task {i}")
        await self._add_token(db_session)

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None)]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        await svc.check_and_send_due_reminders()

        call_args = mock_messaging.Notification.call_args
        body = call_args.kwargs.get("body") or call_args[1].get("body")
        assert "and 2 more" in body

    @pytest.mark.asyncio
    async def test_no_due_tasks_returns_zero(self, db_session):
        """No tasks in window returns 0."""
        svc = NotificationService(db_session)
        assert await svc.check_and_send_due_reminders() == 0

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_last_notified_at_set(self, mock_messaging, db_session):
        """After successful send, task.last_notified_at is set."""
        task = await self._create_due_task(db_session)
        await self._add_token(db_session)

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=None)]
        mock_resp.success_count = 1
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        await svc.check_and_send_due_reminders()

        await db_session.refresh(task)
        assert task.last_notified_at is not None

    @pytest.mark.asyncio
    @patch("services.notification_service.messaging")
    async def test_last_notified_at_not_set_on_failure(self, mock_messaging, db_session):
        """If send returns 0 success, last_notified_at stays None."""
        task = await self._create_due_task(db_session)
        await self._add_token(db_session)

        # Set UnregisteredError to a real class so isinstance() works in send_to_user
        class _UnregisteredError(Exception):
            pass
        mock_messaging.UnregisteredError = _UnregisteredError

        mock_resp = MagicMock()
        mock_resp.responses = [MagicMock(exception=Exception("fail"))]
        mock_resp.success_count = 0
        mock_messaging.send_each.return_value = mock_resp

        svc = NotificationService(db_session)
        await svc.check_and_send_due_reminders()

        await db_session.refresh(task)
        assert task.last_notified_at is None

"""Push notification service using Firebase Cloud Messaging."""
import asyncio
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from firebase_admin import messaging

from models.fcm_token import FcmToken
from models.task import Task
from structured_logging import get_logger

logger = get_logger(__name__)

DEDUP_HOURS = 4
DUE_SOON_MINUTES = 60
DUE_TOMORROW_HOUR_START = 23
DUE_TOMORROW_HOUR_END = 24


class NotificationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_user_tokens(self, user_id: str) -> list[FcmToken]:
        result = await self.session.execute(
            select(FcmToken).where(FcmToken.user_id == user_id)
        )
        return list(result.scalars().all())

    async def send_to_user(self, user_id: str, title: str, body: str, data: dict | None = None) -> int:
        """Send push notification to all of a user's devices. Returns count of successful sends."""
        tokens = await self.get_user_tokens(user_id)
        if not tokens:
            return 0

        messages = [
            messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                token=t.token,
            )
            for t in tokens
        ]

        loop = asyncio.get_running_loop()
        response = await loop.run_in_executor(None, messaging.send_each, messages)

        # Clean up unregistered tokens
        failed_tokens = []
        for i, send_response in enumerate(response.responses):
            if send_response.exception:
                exc = send_response.exception
                if isinstance(exc, (messaging.UnregisteredError,)) or (
                    hasattr(exc, 'code') and exc.code == 'messaging/registration-token-not-registered'
                ):
                    failed_tokens.append(tokens[i].token)
                    logger.info("notification.token_unregistered", user_id=user_id, token_prefix=tokens[i].token[:20])

        if failed_tokens:
            for token_val in failed_tokens:
                await self.session.execute(
                    select(FcmToken).where(FcmToken.token == token_val)
                )
                result = await self.session.execute(
                    select(FcmToken).where(FcmToken.token == token_val)
                )
                token_obj = result.scalar_one_or_none()
                if token_obj:
                    await self.session.delete(token_obj)

        sent_count = response.success_count
        logger.info("notification.sent", user_id=user_id, sent=sent_count, failed=len(failed_tokens))
        return sent_count

    async def get_due_tasks(self) -> list[Task]:
        """Find active tasks due within notification windows that haven't been recently notified."""
        now = datetime.now(timezone.utc)
        dedup_cutoff = now - timedelta(hours=DEDUP_HOURS)

        due_soon_end = now + timedelta(minutes=DUE_SOON_MINUTES)
        due_tomorrow_start = now + timedelta(hours=DUE_TOMORROW_HOUR_START)
        due_tomorrow_end = now + timedelta(hours=DUE_TOMORROW_HOUR_END)

        result = await self.session.execute(
            select(Task).where(
                and_(
                    Task.status == "active",
                    Task.due_date.isnot(None),
                    or_(
                        # Due within 60 minutes
                        and_(Task.due_date >= now, Task.due_date <= due_soon_end),
                        # Due within 23-24 hours (tomorrow reminder)
                        and_(Task.due_date >= due_tomorrow_start, Task.due_date <= due_tomorrow_end),
                    ),
                    or_(
                        Task.last_notified_at.is_(None),
                        Task.last_notified_at < dedup_cutoff,
                    ),
                )
            )
        )
        return list(result.scalars().all())

    async def check_and_send_due_reminders(self) -> int:
        """Check for due tasks and send consolidated notifications. Returns total tasks notified."""
        tasks = await self.get_due_tasks()
        if not tasks:
            return 0

        # Group by user
        user_tasks: dict[str, list[Task]] = {}
        for task in tasks:
            user_tasks.setdefault(task.user_id, []).append(task)

        now = datetime.now(timezone.utc)
        total_notified = 0

        for user_id, user_task_list in user_tasks.items():
            count = len(user_task_list)
            if count == 1:
                title = "Task due soon"
                body = user_task_list[0].title
            else:
                title = f"{count} tasks due soon"
                titles = [t.title for t in user_task_list[:3]]
                body = ", ".join(titles)
                if count > 3:
                    body += f" and {count - 3} more"

            sent = await self.send_to_user(user_id, title, body)
            if sent > 0:
                for task in user_task_list:
                    task.last_notified_at = now
                total_notified += count

        await self.session.commit()
        if total_notified:
            logger.info("notification.reminder_cycle", tasks_notified=total_notified, users=len(user_tasks))
        return total_notified

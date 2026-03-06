"""Test-only endpoints — guarded by APP_ENV check."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from auth import get_current_user
from config import get_settings
from database import get_db
from models.task import Task
from models.category import Category
from models.fcm_token import FcmToken
from structured_logging import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/test", tags=["test"])


@router.delete("/reset")
async def reset_test_data(
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete all tasks, categories, and FCM tokens for the authenticated user.

    Only available when APP_ENV != 'production'.
    """
    settings = get_settings()
    if settings.app_env == "production":
        raise HTTPException(status_code=404, detail="Not found")

    # Delete all tasks for this user
    result_tasks = await db.execute(
        delete(Task).where(Task.user_id == user_id)
    )
    # Delete all categories for this user
    result_cats = await db.execute(
        delete(Category).where(Category.user_id == user_id)
    )
    # Delete all FCM tokens for this user
    result_tokens = await db.execute(
        delete(FcmToken).where(FcmToken.user_id == user_id)
    )
    await db.commit()

    logger.info("test.reset", user_id=user_id,
                tasks_deleted=result_tasks.rowcount,
                categories_deleted=result_cats.rowcount,
                tokens_deleted=result_tokens.rowcount)

    return {
        "status": "reset",
        "tasks_deleted": result_tasks.rowcount,
        "categories_deleted": result_cats.rowcount,
        "tokens_deleted": result_tokens.rowcount,
    }

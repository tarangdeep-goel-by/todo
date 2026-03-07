"""Account management router — GDPR account deletion."""
from fastapi import APIRouter, Depends
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession
from database import get_db
from auth import get_current_user
from models.task import Task
from models.category import Category
from models.fcm_token import FcmToken
from audit import audit_log
from structured_logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/account", tags=["account"])


@router.delete("")
async def delete_account(
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete all user data (tasks, categories, FCM tokens).
    Firebase Auth account deletion must be done client-side."""
    task_count = (await db.execute(
        delete(Task).where(Task.user_id == user_id)
    )).rowcount
    cat_count = (await db.execute(
        delete(Category).where(Category.user_id == user_id)
    )).rowcount
    token_count = (await db.execute(
        delete(FcmToken).where(FcmToken.user_id == user_id)
    )).rowcount
    await db.commit()

    audit_log("account.deleted", user_id, "",
              tasks=task_count, categories=cat_count, tokens=token_count)
    logger.info("account.deleted", user_id=user_id,
                tasks=task_count, categories=cat_count, tokens=token_count)

    return {
        "success": True,
        "message": "All user data deleted",
        "deleted": {
            "tasks": task_count,
            "categories": cat_count,
            "fcm_tokens": token_count,
        },
    }

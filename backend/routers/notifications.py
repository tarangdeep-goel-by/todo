"""Notification token management API router."""
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from datetime import datetime, timezone

from database import get_db
from auth import get_current_user
from models.fcm_token import FcmToken
from rate_limit import limiter
from structured_logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/notifications", tags=["notifications"])


class RegisterTokenRequest(BaseModel):
    token: str = Field(..., min_length=1, max_length=4096)
    platform: str = Field(..., pattern="^(android|ios)$")
    timezone: str = Field(default="UTC", max_length=50)


class DeleteTokenRequest(BaseModel):
    token: str = Field(..., min_length=1, max_length=4096)


@router.post("/token", status_code=200)
@limiter.limit("10/minute")
async def register_token(
    request: Request,
    body: RegisterTokenRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Register or update an FCM device token."""
    result = await db.execute(
        select(FcmToken).where(FcmToken.token == body.token)
    )
    existing = result.scalar_one_or_none()

    if existing:
        existing.user_id = user_id
        existing.platform = body.platform
        existing.timezone = body.timezone
        existing.updated_at = datetime.now(timezone.utc)
    else:
        db.add(FcmToken(
            user_id=user_id,
            token=body.token,
            platform=body.platform,
            timezone=body.timezone,
        ))

    await db.commit()
    logger.info("notification.token_registered", user_id=user_id, platform=body.platform)
    return {"status": "ok"}


@router.delete("/token", status_code=200)
@limiter.limit("10/minute")
async def delete_token(
    request: Request,
    body: DeleteTokenRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove an FCM device token (on sign-out)."""
    await db.execute(
        delete(FcmToken).where(
            FcmToken.token == body.token,
            FcmToken.user_id == user_id,
        )
    )
    await db.commit()
    logger.info("notification.token_deleted", user_id=user_id)
    return {"status": "ok"}

"""FCM Token SQLAlchemy model."""
from sqlalchemy import Column, String, Text, DateTime, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func, text
from database import Base


class FcmToken(Base):
    """Stores FCM device tokens for push notifications."""

    __tablename__ = "fcm_tokens"

    id = Column(UUID(as_uuid=False), primary_key=True, server_default=text("gen_random_uuid()"))
    user_id = Column(String(255), nullable=False, index=True)
    token = Column(Text, nullable=False, unique=True)
    platform = Column(String(20), nullable=False)  # "android", "ios"
    timezone = Column(String(50), nullable=False, default="UTC")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("idx_fcm_tokens_user", "user_id"),
    )

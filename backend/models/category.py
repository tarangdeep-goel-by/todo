"""Category SQLAlchemy model."""
from sqlalchemy import Column, String, Integer, DateTime, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from database import Base
import uuid


class Category(Base):
    """Category model — first-class domain that persists independently of tasks."""

    __tablename__ = "categories"

    id = Column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = Column(String(255), nullable=False)
    name = Column(String(50), nullable=False)  # lowercase
    position = Column(Integer, nullable=False)  # 0-4 → palette index
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "name", name="uq_categories_user_name"),
        Index("idx_categories_user", "user_id"),
    )

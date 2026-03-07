"""Task SQLAlchemy model."""
from sqlalchemy import Column, String, Text, DateTime, ForeignKey, Index, CheckConstraint, Float, ARRAY
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.sql import func
from database import Base
import uuid


class Task(Base):
    """Task model for PostgreSQL."""

    __tablename__ = "tasks"

    # Primary key (UUID)
    id = Column(UUID(as_uuid=False), primary_key=True, default=lambda: str(uuid.uuid4()))

    # User and task info
    user_id = Column(String(255), nullable=False)
    title = Column(String(500), nullable=False)
    description = Column(Text, nullable=True)

    # Task metadata (all optional)
    priority = Column(String(20), nullable=True)  # high/medium/low
    tags = Column(ARRAY(String), nullable=True)  # ['urgent', 'backend', etc.]
    estimated_hours = Column(Float, nullable=True)  # Time estimate

    # Hierarchy - top-level tasks have parent_id=NULL
    parent_id = Column(
        UUID(as_uuid=False),
        ForeignKey("tasks.id", ondelete="SET NULL"),
        nullable=True
    )

    # Category and status
    category = Column(String(50), nullable=False)
    category_id = Column(
        UUID(as_uuid=False),
        ForeignKey("categories.id", ondelete="SET NULL"),
        nullable=True
    )
    status = Column(String(50), nullable=False, default="active")

    # Timestamps
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now())
    due_date = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    archived_at = Column(DateTime(timezone=True), nullable=True)
    last_notified_at = Column(DateTime(timezone=True), nullable=True)

    # Audio and AI
    audio_file_uri = Column(Text, nullable=True)
    transcription = Column(Text, nullable=False)
    ai_placement_json = Column(JSONB, nullable=False)

    # Constraints
    __table_args__ = (
        # No category constraint - allows custom categories like "fitness", "learning", etc.
        CheckConstraint("status IN ('active', 'completed', 'archived')", name="check_status"),
        Index("idx_tasks_user_category", "user_id", "category"),
        Index("idx_tasks_user_category_id", "user_id", "category_id"),
        Index("idx_tasks_user_status", "user_id", "status"),
        Index("idx_tasks_parent", "parent_id"),
        Index("idx_tasks_created", "created_at"),
        Index("idx_tasks_user_due_date", "user_id", "due_date"),
    )

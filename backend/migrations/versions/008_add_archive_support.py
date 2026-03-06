"""Add archived_at column and update status CHECK constraint for archive support.

Revision ID: 008
Revises: 007
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op

revision: str = '008'
down_revision: Union[str, None] = '007'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TABLE tasks ADD COLUMN archived_at TIMESTAMPTZ NULL")

    op.execute("ALTER TABLE tasks DROP CONSTRAINT check_status")
    op.execute(
        "ALTER TABLE tasks ADD CONSTRAINT check_status "
        "CHECK (status IN ('active', 'completed', 'archived'))"
    )

    op.execute(
        "CREATE INDEX idx_tasks_archived_at ON tasks (archived_at) "
        "WHERE archived_at IS NOT NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_tasks_archived_at")

    op.execute("ALTER TABLE tasks DROP CONSTRAINT check_status")
    op.execute(
        "ALTER TABLE tasks ADD CONSTRAINT check_status "
        "CHECK (status IN ('active', 'completed'))"
    )

    op.execute("ALTER TABLE tasks DROP COLUMN IF EXISTS archived_at")

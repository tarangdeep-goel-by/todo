"""Enable pg_trgm extension and create trigram GIN indexes for task search.

Revision ID: 007
Revises: 006
Create Date: 2026-03-02

"""
from typing import Sequence, Union
from alembic import op

revision: str = '007'
down_revision: Union[str, None] = '006'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.execute(
        "CREATE INDEX idx_tasks_title_trgm ON tasks USING gin (title gin_trgm_ops)"
    )
    op.execute(
        "CREATE INDEX idx_tasks_desc_trgm ON tasks "
        "USING gin (COALESCE(description, '') gin_trgm_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_tasks_desc_trgm")
    op.execute("DROP INDEX IF EXISTS idx_tasks_title_trgm")
    op.execute("DROP EXTENSION IF EXISTS pg_trgm")

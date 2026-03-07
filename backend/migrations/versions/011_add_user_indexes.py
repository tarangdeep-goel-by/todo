"""Add user_id indexes for query performance.

Revision ID: 011
Revises: 010
Create Date: 2026-03-07

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '011'
down_revision: Union[str, None] = '010'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index('idx_tasks_user_id', 'tasks', ['user_id'])
    op.create_index(
        'idx_tasks_user_archived',
        'tasks',
        ['user_id', 'archived_at'],
        postgresql_where=sa.text("archived_at IS NOT NULL")
    )


def downgrade() -> None:
    op.drop_index('idx_tasks_user_archived', table_name='tasks')
    op.drop_index('idx_tasks_user_id', table_name='tasks')

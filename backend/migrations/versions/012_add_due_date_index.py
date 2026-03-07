"""Add due_date index for query performance.

Revision ID: 012
Revises: 011
Create Date: 2026-03-07

"""
from typing import Sequence, Union
from alembic import op

revision: str = '012'
down_revision: Union[str, None] = '011'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index('idx_tasks_user_due_date', 'tasks', ['user_id', 'due_date'])


def downgrade() -> None:
    op.drop_index('idx_tasks_user_due_date', table_name='tasks')

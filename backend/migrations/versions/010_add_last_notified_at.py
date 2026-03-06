"""Add last_notified_at column to tasks for notification dedup.

Revision ID: 010
Revises: 009
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '010'
down_revision: Union[str, None] = '009'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('tasks', sa.Column('last_notified_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('tasks', 'last_notified_at')

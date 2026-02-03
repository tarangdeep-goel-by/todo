"""Simplify task status: remove archived, keep active/completed

Revision ID: 003
Revises: 002
Create Date: 2026-02-03

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = '003'
down_revision: Union[str, None] = '002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Convert all archived tasks to completed
    op.execute("UPDATE tasks SET status = 'completed' WHERE status = 'archived'")

    # Drop old constraint and add new one
    op.drop_constraint('check_status', 'tasks', type_='check')
    op.create_check_constraint(
        'check_status',
        'tasks',
        "status IN ('active', 'completed')"
    )


def downgrade() -> None:
    op.drop_constraint('check_status', 'tasks', type_='check')
    op.create_check_constraint(
        'check_status',
        'tasks',
        "status IN ('active', 'completed', 'archived')"
    )

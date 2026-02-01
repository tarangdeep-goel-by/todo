"""Add task metadata fields

Revision ID: 002
Revises: 001
Create Date: 2026-02-01

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY

revision: str = '002'
down_revision: Union[str, None] = '001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add new metadata fields
    op.add_column('tasks', sa.Column('priority', sa.String(20), nullable=True))
    op.add_column('tasks', sa.Column('tags', ARRAY(sa.String()), nullable=True))
    op.add_column('tasks', sa.Column('notes', sa.Text(), nullable=True))
    op.add_column('tasks', sa.Column('estimated_hours', sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column('tasks', 'estimated_hours')
    op.drop_column('tasks', 'notes')
    op.drop_column('tasks', 'tags')
    op.drop_column('tasks', 'priority')

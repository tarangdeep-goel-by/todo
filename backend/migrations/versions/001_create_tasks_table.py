"""Create tasks table

Revision ID: 001
Revises: 
Create Date: 2026-02-01

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB

revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'tasks',
        sa.Column('id', UUID(), primary_key=True, nullable=False),
        sa.Column('user_id', sa.String(255), nullable=False),
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('parent_id', UUID(), sa.ForeignKey('tasks.id', ondelete='SET NULL'), nullable=True),
        sa.Column('category', sa.String(50), nullable=False),
        sa.Column('status', sa.String(50), nullable=False, server_default='active'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('due_date', sa.DateTime(timezone=True), nullable=True),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('audio_file_uri', sa.Text(), nullable=True),
        sa.Column('transcription', sa.Text(), nullable=False),
        sa.Column('ai_placement_json', JSONB(), nullable=False),
        # No category constraint - allows custom categories
        sa.CheckConstraint("status IN ('active', 'completed', 'archived')", name='check_status'),
    )
    
    # Create indexes
    op.create_index('idx_tasks_user_category', 'tasks', ['user_id', 'category'])
    op.create_index('idx_tasks_user_status', 'tasks', ['user_id', 'status'])
    op.create_index('idx_tasks_parent', 'tasks', ['parent_id'])
    op.create_index('idx_tasks_created', 'tasks', ['created_at'])


def downgrade() -> None:
    op.drop_index('idx_tasks_created', table_name='tasks')
    op.drop_index('idx_tasks_parent', table_name='tasks')
    op.drop_index('idx_tasks_user_status', table_name='tasks')
    op.drop_index('idx_tasks_user_category', table_name='tasks')
    op.drop_table('tasks')

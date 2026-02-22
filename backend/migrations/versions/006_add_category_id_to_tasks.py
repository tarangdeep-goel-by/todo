"""Add category_id FK to tasks table

Revision ID: 006
Revises: 005
Create Date: 2026-02-22

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = '006'
down_revision: Union[str, None] = '005'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add nullable category_id column
    op.add_column('tasks', sa.Column('category_id', UUID(as_uuid=False), nullable=True))

    # 2. Backfill from categories table
    conn = op.get_bind()
    conn.execute(sa.text("""
        UPDATE tasks t
        SET category_id = c.id
        FROM categories c
        WHERE t.user_id = c.user_id AND LOWER(t.category) = c.name
    """))

    # 3. Add FK constraint
    op.create_foreign_key(
        'fk_tasks_category_id',
        'tasks', 'categories',
        ['category_id'], ['id'],
        ondelete='SET NULL',
    )

    # 4. Add index
    op.create_index('idx_tasks_user_category_id', 'tasks', ['user_id', 'category_id'])


def downgrade() -> None:
    op.drop_index('idx_tasks_user_category_id', table_name='tasks')
    op.drop_constraint('fk_tasks_category_id', 'tasks', type_='foreignkey')
    op.drop_column('tasks', 'category_id')

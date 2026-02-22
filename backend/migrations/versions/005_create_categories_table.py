"""Create categories table and backfill from tasks

Revision ID: 005
Revises: 004
Create Date: 2026-02-22

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID
import uuid

revision: str = '005'
down_revision: Union[str, None] = '004'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Namespace UUID for deterministic root category IDs (matches old agent_service.py)
_ROOT_NS = uuid.UUID("12345678-1234-5678-1234-567812345678")


def upgrade() -> None:
    # 1. Create categories table
    op.create_table(
        'categories',
        sa.Column('id', UUID(as_uuid=False), primary_key=True),
        sa.Column('user_id', sa.String(255), nullable=False),
        sa.Column('name', sa.String(50), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint('user_id', 'name', name='uq_categories_user_name'),
        sa.Index('idx_categories_user', 'user_id'),
    )

    # 2. Backfill: extract distinct (user_id, LOWER(category)) from tasks
    conn = op.get_bind()
    rows = conn.execute(
        sa.text("""
            SELECT user_id, LOWER(category) as cat, MIN(created_at) as first_seen
            FROM tasks
            GROUP BY user_id, LOWER(category)
            ORDER BY user_id, MIN(created_at)
        """)
    ).fetchall()

    # Group by user_id and assign positions (0-4)
    user_categories = {}
    for user_id, category, first_seen in rows:
        if user_id not in user_categories:
            user_categories[user_id] = []
        if len(user_categories[user_id]) < 5:
            user_categories[user_id].append(category)

    for user_id, categories in user_categories.items():
        for position, name in enumerate(categories):
            cat_id = str(uuid.uuid4())
            conn.execute(
                sa.text("""
                    INSERT INTO categories (id, user_id, name, position)
                    VALUES (:id, :user_id, :name, :position)
                """),
                {"id": cat_id, "user_id": user_id, "name": name, "position": position}
            )

    # 3. Delete root-marker tasks (tasks created with deterministic uuid5 IDs)
    # and set parent_id=NULL on tasks that pointed to them
    all_categories = set()
    for cats in user_categories.values():
        all_categories.update(cats)

    root_ids = [str(uuid.uuid5(_ROOT_NS, cat)) for cat in all_categories]
    if root_ids:
        # FK is SET NULL on delete, so children will automatically get parent_id=NULL
        for root_id in root_ids:
            conn.execute(
                sa.text("DELETE FROM tasks WHERE id = :root_id"),
                {"root_id": root_id}
            )


def downgrade() -> None:
    op.drop_table('categories')

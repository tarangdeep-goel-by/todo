"""Add fcm_tokens table for push notification device registration.

Revision ID: 009
Revises: 008
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision: str = '009'
down_revision: Union[str, None] = '008'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'fcm_tokens',
        sa.Column('id', UUID(as_uuid=False), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', sa.String(255), nullable=False),
        sa.Column('token', sa.Text(), nullable=False),
        sa.Column('platform', sa.String(20), nullable=False),
        sa.Column('timezone', sa.String(50), nullable=False, server_default='UTC'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('token', name='uq_fcm_tokens_token'),
    )
    op.create_index('idx_fcm_tokens_user', 'fcm_tokens', ['user_id'])


def downgrade() -> None:
    op.drop_index('idx_fcm_tokens_user', table_name='fcm_tokens')
    op.drop_table('fcm_tokens')

"""Dynamic query builder for task filtering and sorting."""
from datetime import datetime, timezone, timedelta
from sqlalchemy import select, func, case, and_
from typing import List
from models.task import Task
from models.schemas import TaskFilterParams


class QueryBuilder:
    """Build dynamic SQLAlchemy queries from filter parameters."""

    ALLOWED_SORT_FIELDS = {'title', 'created_at', 'updated_at', 'due_date', 'priority', 'status', 'completed_at'}

    PRIORITY_MAP = {
        'high': 3,
        'medium': 2,
        'low': 1
    }

    @staticmethod
    def build_task_query(params: TaskFilterParams) -> select:
        """Build SELECT query with filters and sorting."""
        query = select(Task).where(Task.user_id == params.user_id)
        query = QueryBuilder._apply_filters(query, params)
        query = QueryBuilder._apply_sorting(query, params)
        query = query.limit(params.limit).offset(params.offset)
        return query

    @staticmethod
    def build_count_query(params: TaskFilterParams) -> select:
        """Build COUNT query (no sorting, no pagination)."""
        query = select(func.count(Task.id)).where(Task.user_id == params.user_id)
        query = QueryBuilder._apply_filters(query, params)
        return query

    @staticmethod
    def _apply_filters(query: select, params: TaskFilterParams) -> select:
        """Apply all filters to query."""

        # Exclude archived unless explicitly requested
        if not params.include_archived:
            query = query.where(Task.archived_at.is_(None))

        # Multi-value filters (OR logic with IN clause)
        if params.category:
            values = [v.lower() for v in params.parse_multi_value(params.category)]
            query = query.where(func.lower(Task.category).in_(values))

        if params.priority:
            values = [v.lower() for v in params.parse_multi_value(params.priority)]
            query = query.where(func.lower(Task.priority).in_(values))

        if params.status:
            values = [v.lower() for v in params.parse_multi_value(params.status)]
            conditions = []
            db_statuses = [v for v in values if v not in ('overdue', 'due_soon')]
            if db_statuses:
                conditions.append(func.lower(Task.status).in_(db_statuses))
            if 'overdue' in values:
                now = datetime.now(timezone.utc)
                conditions.append(and_(
                    Task.status == 'active',
                    Task.due_date.isnot(None),
                    Task.due_date < now,
                ))
            if 'due_soon' in values:
                now = datetime.now(timezone.utc)
                soon = now + timedelta(hours=48)
                conditions.append(and_(
                    Task.status == 'active',
                    Task.due_date.isnot(None),
                    Task.due_date >= now,
                    Task.due_date < soon,
                ))
            if conditions:
                from sqlalchemy import or_
                query = query.where(or_(*conditions))

        # Parent ID (support "null" string for top-level tasks)
        if params.parent_id is not None:
            if params.parent_id.lower() == "null":
                query = query.where(Task.parent_id.is_(None))
            else:
                query = query.where(Task.parent_id == params.parent_id)

        # Tag search (PostgreSQL ARRAY contains)
        if params.tags:
            values = params.parse_multi_value(params.tags)
            for tag in values:
                query = query.where(Task.tags.contains([tag]))

        # Range filters
        if params.created_at_gte:
            query = query.where(Task.created_at >= params.created_at_gte)
        if params.created_at_lte:
            query = query.where(Task.created_at <= params.created_at_lte)

        if params.updated_at_gte:
            query = query.where(Task.updated_at >= params.updated_at_gte)
        if params.updated_at_lte:
            query = query.where(Task.updated_at <= params.updated_at_lte)

        if params.due_date_gte:
            query = query.where(Task.due_date >= params.due_date_gte)
        if params.due_date_lte:
            query = query.where(Task.due_date <= params.due_date_lte)

        if params.completed_at_gte:
            query = query.where(Task.completed_at >= params.completed_at_gte)
        if params.completed_at_lte:
            query = query.where(Task.completed_at <= params.completed_at_lte)

        return query

    @staticmethod
    def _apply_sorting(query: select, params: TaskFilterParams) -> select:
        """Apply multi-level sorting."""
        sort_fields = params.parse_sort()

        for field_name, direction in sort_fields:
            if field_name not in QueryBuilder.ALLOWED_SORT_FIELDS:
                continue  # Skip invalid sort fields
            order_clause = QueryBuilder._build_order_clause(field_name, direction)
            query = query.order_by(order_clause)

        return query

    @staticmethod
    def _build_order_clause(field_name: str, direction: str):
        """Build ORDER BY clause for a single field."""

        # Status needs special handling (overdue first, due_soon, then active, then completed)
        if field_name == "status":
            now = datetime.now(timezone.utc)
            soon = now + timedelta(hours=48)
            status_case = case(
                (and_(Task.status == "active", Task.due_date.isnot(None), Task.due_date < now), 0),
                (and_(Task.status == "active", Task.due_date.isnot(None), Task.due_date >= now, Task.due_date < soon), 1),
                (Task.status == "active", 2),
                (Task.status == "completed", 3),
                (Task.status == "archived", 4),
                else_=5
            )
            return status_case.desc() if direction == "desc" else status_case.asc()

        # Priority needs special handling (high > medium > low)
        if field_name == "priority":
            priority_case = case(
                (Task.priority == "high", 3),
                (Task.priority == "medium", 2),
                (Task.priority == "low", 1),
                else_=0
            )
            return priority_case.desc() if direction == "desc" else priority_case.asc()

        # Date fields with NULL handling (nulls last)
        if field_name in ["due_date", "completed_at"]:
            field = getattr(Task, field_name)
            if direction == "desc":
                return field.desc().nullslast()
            else:
                return field.asc().nullslast()

        # Standard fields
        field = getattr(Task, field_name)
        return field.desc() if direction == "desc" else field.asc()

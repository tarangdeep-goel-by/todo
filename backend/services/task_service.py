"""Task service for CRUD operations and tree queries."""
import asyncio
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func, case, and_, literal
from sqlalchemy.exc import OperationalError
from datetime import datetime, timezone, timedelta
from typing import List, Optional, Dict
from models.task import Task
from models.category import Category
from utils.fuzzy_matcher import FuzzyMatcher
import uuid


async def _with_deadlock_retry(coro_factory, max_retries=3, base_delay=0.1):
    """Retry a coroutine on deadlock/serialization errors with exponential backoff.

    Args:
        coro_factory: Callable that returns a new coroutine each call
        max_retries: Maximum retry attempts
        base_delay: Base delay in seconds (multiplied by attempt number)
    """
    from structured_logging import get_logger
    logger = get_logger(__name__)

    for attempt in range(max_retries + 1):
        try:
            return await coro_factory()
        except OperationalError as e:
            is_deadlock = any(s in str(e).lower() for s in ("deadlock", "serialization", "could not serialize"))
            if not is_deadlock or attempt == max_retries:
                raise
            delay = base_delay * (2 ** attempt)
            logger.warning("db.deadlock_retry", attempt=attempt + 1, max_retries=max_retries, delay=delay)
            await asyncio.sleep(delay)


class TaskService:
    """Service for task CRUD operations."""

    def __init__(self, db: AsyncSession, *, auto_commit: bool = True):
        """Initialize with database session.

        Args:
            db: Async database session.
            auto_commit: If True (default), commit after each mutation.
                Set to False for batch operations that manage their own transaction.
        """
        self.db = db
        self._auto_commit = auto_commit

    async def _maybe_commit(self):
        """Commit or flush depending on auto_commit mode.

        When auto_commit is False (batch mode), flush instead of commit
        so the caller can commit/rollback the entire batch atomically.
        """
        if self._auto_commit:
            await self.db.commit()
        else:
            await self.db.flush()

    async def create_task(
        self,
        user_id: str,
        title: str,
        category: str,
        transcription: str,
        parent_id: Optional[str] = None,
        description: Optional[str] = None,
        due_date: Optional[str] = None,
        ai_placement: Optional[Dict] = None,
        priority: Optional[str] = None,
        tags: Optional[list] = None,
        estimated_hours: Optional[float] = None,
        task_id: Optional[str] = None,
        category_id: Optional[str] = None,
    ) -> Task:
        """Create a new task. Resolves category_id from category string if not provided."""
        if not category_id:
            category_id = await self._resolve_category_id(user_id, category)

        task = Task(
            id=task_id or str(uuid.uuid4()),
            user_id=user_id,
            title=title.lower(),
            description=description,
            parent_id=parent_id,
            category=category,
            category_id=category_id,
            transcription=transcription,
            due_date=due_date,
            ai_placement_json=ai_placement or {"confidence": 0.9, "reasoning": "Manual creation"},
            priority=priority,
            tags=tags,
            estimated_hours=estimated_hours
        )

        self.db.add(task)
        await self.db.flush()

        # New child under a completed parent → activate ancestor chain
        if parent_id:
            await self._activate_ancestor_chain(task.id)

        await self._maybe_commit()
        await self.db.refresh(task)
        return task

    VALID_DOMAINS = {"career", "finance", "health", "relationships", "growth", "recreation", "home", "community"}

    async def _resolve_category_id(self, user_id: str, category: str) -> Optional[str]:
        """Look up category ID from category name string. Auto-creates valid domains."""
        name = category.lower().strip()
        result = await self.db.execute(
            select(Category.id)
            .where(Category.user_id == user_id, Category.name == name)
        )
        row = result.scalar_one_or_none()
        if row:
            return row

        # Auto-create if it's one of the 5 valid domains
        if name in self.VALID_DOMAINS:
            cat = await self.create_category(user_id, name)
            return cat.id

        return None

    async def get_task(self, task_id: str) -> Optional[Task]:
        """Get task by ID."""
        result = await self.db.execute(
            select(Task).where(Task.id == task_id)
        )
        return result.scalar_one_or_none()

    async def get_tasks(
        self,
        user_id: str,
        category: Optional[str] = None,
        status: Optional[str] = None,
        parent_id: Optional[str] = None
    ) -> List[Task]:
        """Get tasks with filters. Excludes archived by default."""
        query = select(Task).where(Task.user_id == user_id)
        query = query.where(Task.archived_at.is_(None))

        if category:
            query = query.where(Task.category == category)
        if status:
            query = query.where(Task.status == status)
        if parent_id is not None:
            query = query.where(Task.parent_id == parent_id)

        result = await self.db.execute(query.order_by(Task.created_at.desc()))
        return list(result.scalars().all())

    async def update_task(
        self,
        task_id: str,
        **updates
    ) -> Optional[Task]:
        """Update task fields."""
        task = await self.get_task(task_id)
        if not task:
            return None

        # Guard against circular parent moves
        new_parent_id = updates.get('parent_id')
        if new_parent_id is not None:
            if new_parent_id == task_id:
                raise ValueError(f"Cannot move task under itself")
            descendants = await self._get_all_descendants(task_id)
            descendant_ids = {d.id for d in descendants}
            if new_parent_id in descendant_ids:
                raise ValueError(f"Cannot move task under its own descendant")

        for key, value in updates.items():
            if hasattr(task, key):
                if key == 'title' and isinstance(value, str):
                    value = value.lower()
                setattr(task, key, value)

        # When undoing (status → active), activate completed ancestors
        if updates.get('status') == 'active':
            await self._activate_ancestor_chain(task_id)

        await self._maybe_commit()
        await self.db.refresh(task)
        return task

    async def complete_task(self, task_id: str) -> Optional[Task]:
        """Mark task as completed."""
        from datetime import datetime
        return await self.update_task(
            task_id,
            status="completed",
            completed_at=datetime.utcnow()
        )

    async def complete_task_with_children(self, task_id: str) -> int:
        """Complete task and all active descendants."""
        from datetime import datetime

        descendants = await self._get_all_descendants(task_id)
        task_ids = [task_id] + [d.id for d in descendants]

        now = datetime.utcnow()

        async def _do_complete():
            await self.db.execute(
                update(Task)
                .where(Task.id.in_(task_ids))
                .where(Task.status == "active")
                .values(status="completed", completed_at=now)
            )
            await self._maybe_commit()

        await _with_deadlock_retry(_do_complete)
        return len(task_ids)

    async def archive_task_with_children(self, task_id: str) -> int:
        """Archive task and all descendants (soft delete)."""
        descendants = await self._get_all_descendants(task_id)
        all_ids = [task_id] + [d.id for d in descendants]

        now = datetime.now(timezone.utc)

        async def _do_archive():
            await self.db.execute(
                update(Task)
                .where(Task.id.in_(all_ids))
                .where(Task.status != "archived")
                .values(status="archived", archived_at=now)
            )
            await self._maybe_commit()

        await _with_deadlock_retry(_do_archive)
        return len(all_ids)

    async def restore_task_with_children(self, task_id: str) -> int:
        """Restore archived task and children archived at the same time."""
        task = await self.get_task(task_id)
        if not task or not task.archived_at:
            return 0

        archived_at = task.archived_at
        descendants = await self._get_all_descendants(task_id)
        all_ids = [task_id] + [
            d.id for d in descendants if d.archived_at == archived_at
        ]

        await self.db.execute(
            update(Task)
            .where(Task.id.in_(all_ids))
            .values(status="active", archived_at=None)
        )
        await self._maybe_commit()

        return len(all_ids)

    async def get_archived_tasks(self, user_id: str) -> List[Task]:
        """Get all archived tasks for a user."""
        result = await self.db.execute(
            select(Task)
            .where(Task.user_id == user_id, Task.archived_at.isnot(None))
            .order_by(Task.archived_at.desc())
        )
        return list(result.scalars().all())

    async def purge_old_archived(self, days: int = 30) -> int:
        """Hard delete tasks archived more than `days` ago."""
        from sqlalchemy import delete as sql_delete

        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
        result = await self.db.execute(
            sql_delete(Task)
            .where(Task.archived_at.isnot(None))
            .where(Task.archived_at < cutoff)
        )
        await self._maybe_commit()
        return result.rowcount

    async def bulk_complete(self, task_ids: List[str], user_id: str) -> tuple[int, List[str]]:
        """Complete multiple tasks with children. Returns (affected_count, errors)."""
        if len(task_ids) > 50:
            raise ValueError("Cannot process more than 50 tasks at once")

        affected = 0
        errors = []

        for tid in task_ids:
            task = await self.get_task(tid)
            if not task:
                errors.append(f"Task {tid} not found")
                continue
            if task.user_id != user_id:
                errors.append(f"Task {tid} not authorized")
                continue
            count = await self.complete_task_with_children(tid)
            affected += count

        return affected, errors

    async def bulk_archive(self, task_ids: List[str], user_id: str) -> tuple[int, List[str]]:
        """Archive multiple tasks with children. Returns (affected_count, errors)."""
        if len(task_ids) > 50:
            raise ValueError("Cannot process more than 50 tasks at once")

        affected = 0
        errors = []

        for tid in task_ids:
            task = await self.get_task(tid)
            if not task:
                errors.append(f"Task {tid} not found")
                continue
            if task.user_id != user_id:
                errors.append(f"Task {tid} not authorized")
                continue
            count = await self.archive_task_with_children(tid)
            affected += count

        return affected, errors

    async def delete_task_with_children(self, task_id: str) -> int:
        """Hard delete task and all descendants from DB."""
        from sqlalchemy import delete as sql_delete

        descendants = await self._get_all_descendants(task_id)
        all_ids = [d.id for d in descendants] + [task_id]

        async def _do_delete():
            await self.db.execute(
                sql_delete(Task).where(Task.id.in_(all_ids))
            )
            await self._maybe_commit()

        await _with_deadlock_retry(_do_delete)
        return len(all_ids)

    async def _get_all_descendants(self, task_id: str) -> List[Task]:
        """Get all descendants recursively (cycle-safe)."""
        all_descendants = []
        seen = {task_id}
        to_process = [task_id]

        while to_process:
            current_id = to_process.pop(0)
            result = await self.db.execute(
                select(Task).where(Task.parent_id == current_id)
            )
            children = list(result.scalars().all())

            for child in children:
                if child.id not in seen:
                    seen.add(child.id)
                    all_descendants.append(child)
                    to_process.append(child.id)

        return all_descendants

    async def _activate_ancestor_chain(self, task_id: str) -> List[str]:
        """Walk up parent_id chain, set all completed ancestors to active.

        Does NOT commit — caller's commit covers it in the same transaction.
        Returns list of ancestor IDs that were activated.
        """
        activated_ids = []
        current_id = task_id

        while current_id:
            result = await self.db.execute(
                select(Task.parent_id).where(Task.id == current_id)
            )
            row = result.first()
            if not row or not row.parent_id:
                break

            parent_result = await self.db.execute(
                select(Task.id, Task.status).where(Task.id == row.parent_id)
            )
            parent = parent_result.first()
            if not parent:
                break

            if parent.status == "completed":
                activated_ids.append(parent.id)

            current_id = row.parent_id

        if activated_ids:
            await self.db.execute(
                update(Task)
                .where(Task.id.in_(activated_ids))
                .values(status="active", completed_at=None)
            )

        return activated_ids

    async def build_full_tree_context(self, user_id: str, compressed: bool = False) -> str:
        """
        Build readable task tree for Gemini context.

        Args:
            user_id: User ID
            compressed: If True, omit UUIDs for ~56% token reduction.
                        Titles + hierarchy + status are preserved.

        Returns:
            Tree structure as string with all tasks organized by category
        """
        # Get ALL tasks (active + completed) so Gemini can reference completed parents
        all_tasks = await self.get_tasks(user_id)

        # Group tasks by category
        categories = {}
        for task in all_tasks:
            if task.category not in categories:
                categories[task.category] = []
            categories[task.category].append(task)

        if compressed:
            return self._build_compressed_tree(categories)
        return self._build_full_tree(categories, user_id)

    def _build_full_tree(self, categories: Dict[str, List[Task]], user_id: str) -> str:
        """Build full tree with UUIDs (original format)."""
        tree_str = f"User: {user_id}\n\n"
        for category, tasks in sorted(categories.items()):
            tree_str += f"{category.upper()} TASKS:\n"
            top_level = [t for t in tasks if t.parent_id is None]
            for task in top_level:
                status_tag = " [COMPLETED]" if task.status == "completed" else ""
                tree_str += f"├── {task.title} (id: {task.id}){status_tag}\n"
                tree_str += self._build_subtree(tasks, task.id, indent=1)
            tree_str += "\n"
        return tree_str

    def _build_compressed_tree(self, categories: Dict[str, List[Task]]) -> str:
        """Build compressed tree without UUIDs (~56% fewer tokens)."""
        tree_str = ""
        for category, tasks in sorted(categories.items()):
            tree_str += f"{category.upper()}:\n"
            top_level = [t for t in tasks if t.parent_id is None]
            for task in top_level:
                status_tag = " [done]" if task.status == "completed" else ""
                tree_str += f"- {task.title}{status_tag}\n"
                tree_str += self._build_compressed_subtree(tasks, task.id, indent=1)
            tree_str += "\n"
        return tree_str

    def _build_compressed_subtree(self, tasks: List[Task], parent_id: str, indent: int = 0) -> str:
        """Recursively build compressed tree string."""
        result = ""
        children = [t for t in tasks if t.parent_id == parent_id]
        for child in children:
            status_tag = " [done]" if child.status == "completed" else ""
            result += "  " * indent + f"- {child.title}{status_tag}\n"
            result += self._build_compressed_subtree(tasks, child.id, indent + 1)
        return result

    def _build_subtree(self, tasks: List[Task], parent_id: str, indent: int = 0) -> str:
        """Recursively build tree string with indentation."""
        result = ""
        children = [t for t in tasks if t.parent_id == parent_id]

        for child in children:
            status_tag = " [COMPLETED]" if child.status == "completed" else ""
            result += "  " * indent + f"├── {child.title} (id: {child.id}){status_tag}\n"
            result += self._build_subtree(tasks, child.id, indent + 1)

        return result

    async def search_tasks(self, user_id: str, query: str,
                           threshold: int = 60, limit: int = 5) -> List[Task]:
        """Search with fuzzy matching."""
        ranked = await self.search_tasks_with_scores(user_id, query, threshold, limit)
        return [task for task, score in ranked]

    async def search_tasks_with_scores(self, user_id: str, query: str,
                                       threshold: int = 60, limit: int = 5) -> List[tuple]:
        """Search with fuzzy matching, returning (task, score) tuples."""
        all_tasks = await self.get_tasks(user_id, status="active")
        return FuzzyMatcher.rank_matches(query, all_tasks, threshold, limit)

    async def get_categories(self, user_id: str) -> List[str]:
        """Get list of category names for user from categories table."""
        result = await self.db.execute(
            select(Category.name)
            .where(Category.user_id == user_id)
            .order_by(Category.position)
        )
        return [row[0] for row in result.all()]

    async def count_categories(self, user_id: str) -> int:
        """Count categories for user from categories table."""
        result = await self.db.execute(
            select(func.count())
            .select_from(Category)
            .where(Category.user_id == user_id)
        )
        return result.scalar_one()

    async def get_categories_from_db(self, user_id: str) -> List[Category]:
        """Get full Category objects ordered by position."""
        result = await self.db.execute(
            select(Category)
            .where(Category.user_id == user_id)
            .order_by(Category.position)
        )
        return list(result.scalars().all())

    async def create_category(self, user_id: str, name: str) -> Category:
        """Create a category. Validates max 8, no duplicate, assigns lowest unused position."""
        from config import get_settings
        name = name.lower().strip()

        # Check duplicate
        existing = await self.db.execute(
            select(Category)
            .where(Category.user_id == user_id, Category.name == name)
        )
        if existing.scalar_one_or_none():
            raise ValueError(f"Category '{name}' already exists")

        # Check max categories
        max_cats = get_settings().max_categories
        count = await self.count_categories(user_id)
        if count >= max_cats:
            raise ValueError(f"Maximum of {max_cats} categories reached")

        # Find lowest unused position (0 to max-1)
        result = await self.db.execute(
            select(Category.position)
            .where(Category.user_id == user_id)
            .order_by(Category.position)
        )
        used_positions = {row[0] for row in result.all()}
        position = next(p for p in range(max_cats) if p not in used_positions)

        category = Category(
            id=str(uuid.uuid4()),
            user_id=user_id,
            name=name,
            position=position,
        )
        self.db.add(category)
        await self._maybe_commit()
        await self.db.refresh(category)
        return category

    async def delete_category(self, category_id: str, user_id: str) -> bool:
        """Delete a category by ID. Returns True if deleted."""
        from sqlalchemy import delete as sql_delete
        result = await self.db.execute(
            sql_delete(Category)
            .where(Category.id == category_id, Category.user_id == user_id)
        )
        await self._maybe_commit()
        return result.rowcount > 0

    async def get_tasks_advanced(
        self,
        filter_params: 'TaskFilterParams'
    ) -> tuple[List[Task], int]:
        """
        Get tasks with advanced filtering, sorting, and pagination.

        Returns:
            tuple of (tasks, total_count)
        """
        from services.query_builder import QueryBuilder

        # Build and execute main query
        query = QueryBuilder.build_task_query(filter_params)
        result = await self.db.execute(query)
        tasks = list(result.scalars().all())

        # Build and execute count query
        count_query = QueryBuilder.build_count_query(filter_params)
        count_result = await self.db.execute(count_query)
        total_count = count_result.scalar_one()

        return tasks, total_count

    async def get_task_stats(self, user_id: str) -> Dict:
        """Get aggregate task statistics using SQL-level aggregation."""
        now = datetime.now(timezone.utc)
        soon = now + timedelta(hours=48)

        is_overdue = and_(
            Task.status == 'active',
            Task.due_date.isnot(None),
            Task.due_date < now,
        )
        is_due_soon = and_(
            Task.status == 'active',
            Task.due_date.isnot(None),
            Task.due_date >= now,
            Task.due_date < soon,
        )

        base_filter = and_(Task.user_id == user_id, Task.archived_at.is_(None))

        # --- Total + by_status + due_soon in one query ---
        totals_query = select(
            func.count(Task.id).label('total'),
            func.count().filter(Task.status == 'active').label('active'),
            func.count().filter(Task.status == 'completed').label('completed'),
            func.count().filter(is_overdue).label('overdue'),
            func.count().filter(is_due_soon).label('due_soon'),
        ).where(base_filter)

        totals = (await self.db.execute(totals_query)).one()

        # --- by_priority ---
        priority_query = select(
            func.count().filter(Task.priority == 'high').label('high'),
            func.count().filter(Task.priority == 'medium').label('medium'),
            func.count().filter(Task.priority == 'low').label('low'),
            func.count().filter(
                (Task.priority.is_(None)) | (Task.priority.notin_(['high', 'medium', 'low']))
            ).label('none'),
        ).where(base_filter)

        priorities = (await self.db.execute(priority_query)).one()

        # --- by_category (GROUP BY with LEFT JOIN for category name) ---
        cat_name = func.coalesce(Category.name, literal('Uncategorized')).label('category_name')
        cat_id = Category.id.label('category_id')

        cat_query = (
            select(
                cat_id,
                cat_name,
                func.count(Task.id).label('total'),
                func.count().filter(Task.status == 'active').label('active'),
                func.count().filter(Task.status == 'completed').label('completed'),
                func.count().filter(is_overdue).label('overdue'),
            )
            .select_from(Task)
            .outerjoin(Category, Task.category_id == Category.id)
            .where(base_filter)
            .group_by(Category.id, Category.name)
        )

        cat_rows = (await self.db.execute(cat_query)).all()

        return {
            "total_tasks": totals.total,
            "by_status": {
                "active": totals.active,
                "completed": totals.completed,
                "overdue": totals.overdue,
            },
            "by_priority": {
                "high": priorities.high,
                "medium": priorities.medium,
                "low": priorities.low,
                "none": priorities.none,
            },
            "by_category": [
                {
                    "category_id": row.category_id,
                    "category_name": row.category_name,
                    "total": row.total,
                    "active": row.active,
                    "completed": row.completed,
                    "overdue": row.overdue,
                }
                for row in cat_rows
            ],
            "due_soon_count": totals.due_soon,
        }

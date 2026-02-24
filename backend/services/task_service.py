"""Task service for CRUD operations and tree queries."""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, func
from typing import List, Optional, Dict
from models.task import Task
from models.category import Category
from utils.fuzzy_matcher import FuzzyMatcher
import uuid


class TaskService:
    """Service for task CRUD operations."""

    def __init__(self, db: AsyncSession):
        """Initialize with database session."""
        self.db = db

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
            title=title,
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

        # New child under a completed parent → activate ancestor chain
        if parent_id:
            await self._activate_ancestor_chain(task.id)

        await self.db.commit()
        await self.db.refresh(task)
        return task

    async def _resolve_category_id(self, user_id: str, category: str) -> Optional[str]:
        """Look up category ID from category name string."""
        result = await self.db.execute(
            select(Category.id)
            .where(Category.user_id == user_id, Category.name == category.lower().strip())
        )
        row = result.scalar_one_or_none()
        return row

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
        """Get tasks with filters."""
        query = select(Task).where(Task.user_id == user_id)

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

        for key, value in updates.items():
            if hasattr(task, key):
                setattr(task, key, value)

        # When undoing (status → active), activate completed ancestors
        if updates.get('status') == 'active':
            await self._activate_ancestor_chain(task_id)

        await self.db.commit()
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
        await self.db.execute(
            update(Task)
            .where(Task.id.in_(task_ids))
            .where(Task.status == "active")
            .values(status="completed", completed_at=now)
        )
        await self.db.commit()

        return len(task_ids)

    async def delete_task_with_children(self, task_id: str) -> int:
        """Hard delete task and all descendants from DB."""
        from sqlalchemy import delete as sql_delete

        descendants = await self._get_all_descendants(task_id)
        # Delete descendants first (children before parents to respect FK)
        descendant_ids = [d.id for d in reversed(descendants)]
        all_ids = descendant_ids + [task_id]

        for tid in all_ids:
            await self.db.execute(
                sql_delete(Task).where(Task.id == tid)
            )
        await self.db.commit()

        return len(all_ids)

    async def _get_all_descendants(self, task_id: str) -> List[Task]:
        """Get all descendants recursively."""
        all_descendants = []
        to_process = [task_id]

        while to_process:
            current_id = to_process.pop(0)
            result = await self.db.execute(
                select(Task).where(Task.parent_id == current_id)
            )
            children = list(result.scalars().all())

            for child in children:
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

    async def build_full_tree_context(self, user_id: str) -> str:
        """
        Build readable FULL task tree for Gemini context.

        Architecture:
        - user_id is the root
        - Top-level tasks have parent_id=NULL
        - Tasks are categorized by the 'category' property

        Returns:
            Tree structure as string with all tasks organized by category
        """
        # Get all active tasks
        all_tasks = await self.get_tasks(user_id, status="active")

        # Group tasks by category
        categories = {}
        for task in all_tasks:
            if task.category not in categories:
                categories[task.category] = []
            categories[task.category].append(task)

        # Build hierarchical tree string
        tree_str = f"User: {user_id}\n\n"

        for category, tasks in sorted(categories.items()):
            tree_str += f"{category.upper()} TASKS:\n"
            # Get top-level tasks (parent_id=NULL)
            top_level = [t for t in tasks if t.parent_id is None]
            for task in top_level:
                tree_str += f"├── {task.title} (id: {task.id})\n"
                tree_str += self._build_subtree(tasks, task.id, indent=1)
            tree_str += "\n"

        return tree_str

    def _build_subtree(self, tasks: List[Task], parent_id: str, indent: int = 0) -> str:
        """Recursively build tree string with indentation."""
        result = ""
        children = [t for t in tasks if t.parent_id == parent_id]

        for child in children:
            result += "  " * indent + f"├── {child.title} (id: {child.id})\n"
            result += self._build_subtree(tasks, child.id, indent + 1)

        return result

    async def search_tasks(self, user_id: str, query: str,
                           threshold: int = 70, limit: int = 5) -> List[Task]:
        """Search with fuzzy matching."""
        all_tasks = await self.get_tasks(user_id, status="active")
        ranked = FuzzyMatcher.rank_matches(query, all_tasks, threshold, limit)
        return [task for task, score in ranked]

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
        """Create a category. Validates max 5, no duplicate, assigns lowest unused position."""
        name = name.lower().strip()

        # Check duplicate
        existing = await self.db.execute(
            select(Category)
            .where(Category.user_id == user_id, Category.name == name)
        )
        if existing.scalar_one_or_none():
            raise ValueError(f"Category '{name}' already exists")

        # Check max 5
        count = await self.count_categories(user_id)
        if count >= 5:
            raise ValueError("Maximum of 5 categories reached")

        # Find lowest unused position (0-4)
        result = await self.db.execute(
            select(Category.position)
            .where(Category.user_id == user_id)
            .order_by(Category.position)
        )
        used_positions = {row[0] for row in result.all()}
        position = next(p for p in range(5) if p not in used_positions)

        category = Category(
            id=str(uuid.uuid4()),
            user_id=user_id,
            name=name,
            position=position,
        )
        self.db.add(category)
        await self.db.commit()
        await self.db.refresh(category)
        return category

    async def delete_category(self, category_id: str, user_id: str) -> bool:
        """Delete a category by ID. Returns True if deleted."""
        from sqlalchemy import delete as sql_delete
        result = await self.db.execute(
            sql_delete(Category)
            .where(Category.id == category_id, Category.user_id == user_id)
        )
        await self.db.commit()
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

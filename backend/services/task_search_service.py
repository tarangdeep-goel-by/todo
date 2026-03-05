"""PG-native task search using pg_trgm trigram matching."""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from typing import List, Optional, Tuple
from models.task import Task
from structured_logging import get_logger

logger = get_logger(__name__)

# Confidence thresholds for resolve_single()
HIGH_CONFIDENCE_SCORE = 0.6
CONFIDENCE_GAP = 0.15


class TaskSearchService:
    """Search tasks using PostgreSQL pg_trgm trigram similarity."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def search(
        self,
        user_id: str,
        query: str,
        status_filter: str = "active",
        limit: int = 5,
    ) -> List[Tuple[Task, float]]:
        """pg_trgm weighted search: title 70% + description 30%.

        Returns list of (Task, score) tuples sorted by score descending.
        """
        if not query or not query.strip():
            return []

        sql = text("""
            SELECT t.*,
                   GREATEST(
                       similarity(t.title, :q),
                       word_similarity(:q, t.title)
                   ) * 0.7
                   + similarity(COALESCE(t.description, ''), :q) * 0.3
                   AS search_score
            FROM tasks t
            WHERE t.user_id = :uid
              AND t.status = :status
              AND (
                  t.title % :q
                  OR COALESCE(t.description, '') % :q
                  OR word_similarity(:q, t.title) > 0.3
              )
            ORDER BY search_score DESC
            LIMIT :lim
        """)

        result = await self.db.execute(sql, {
            "q": query.lower(),
            "uid": user_id,
            "status": status_filter,
            "lim": limit,
        })
        rows = result.fetchall()

        if not rows:
            return []

        # Map rows back to Task objects
        tasks_with_scores = []
        for row in rows:
            task = Task(
                id=row.id,
                user_id=row.user_id,
                title=row.title,
                description=row.description,
                priority=row.priority,
                tags=row.tags,
                estimated_hours=row.estimated_hours,
                parent_id=row.parent_id,
                category=row.category,
                category_id=row.category_id,
                status=row.status,
                created_at=row.created_at,
                updated_at=row.updated_at,
                due_date=row.due_date,
                completed_at=row.completed_at,
                audio_file_uri=row.audio_file_uri,
                transcription=row.transcription,
                ai_placement_json=row.ai_placement_json,
            )
            tasks_with_scores.append((task, float(row.search_score)))

        logger.debug("task.search", query=query, result_count=len(tasks_with_scores), top_score=round(tasks_with_scores[0][1], 3) if tasks_with_scores else 0)
        return tasks_with_scores

    async def resolve_single(
        self,
        user_id: str,
        query: str,
        status_filter: str = "active",
    ) -> Tuple[Optional[Task], List[Task]]:
        """Convenience: resolve a single task from a text query.

        Returns:
            (task, []) for confident match (score >= 0.6, gap to 2nd >= 0.15)
            (None, [candidates]) for ambiguous match
            (None, []) for no match
        """
        results = await self.search(user_id, query, status_filter=status_filter, limit=5)

        if not results:
            return None, []

        top_task, top_score = results[0]

        # Check if confident enough
        if top_score >= HIGH_CONFIDENCE_SCORE:
            if len(results) == 1:
                return top_task, []
            second_score = results[1][1]
            if top_score - second_score >= CONFIDENCE_GAP:
                return top_task, []

        # Ambiguous — return all candidates
        return None, [task for task, _ in results]

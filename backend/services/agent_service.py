"""Agent service for processing voice commands via brain dump pipeline."""
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict, Any, List, Optional, Tuple
import uuid
from .gemini_service import GeminiService
from .task_service import TaskService
from .task_search_service import TaskSearchService
from .intent_prefilter import prefilter
from models.schemas import BrainDumpResponse, BrainDumpTaskProposal, BrainDumpSubmitResponse
from utils.date_parser import parse_flexible_date
from config import get_settings
from structured_logging import get_logger

logger = get_logger(__name__)


class AgentService:
    """Service for processing voice/text commands via brain dump pipeline."""

    def __init__(self, gemini_service: GeminiService):
        """Initialize with Gemini service."""
        self.gemini = gemini_service

    async def _search_tasks(self, user_id: str, query: str, db: AsyncSession, task_service: TaskService) -> List[Tuple[Any, float]]:
        """Search for tasks by query, dispatching on configured search engine.

        Returns list of (Task, score) tuples sorted by score descending.
        """
        settings = get_settings()
        if settings.search_engine == "pg_native":
            search = TaskSearchService(db)
            results = await search.search(user_id, query, status_filter="active")
            return [(task, score) for task, score in results]
        else:
            return await task_service.search_tasks_with_scores(user_id, query)

    async def process_brain_dump(
        self,
        transcription: str,
        user_id: str,
        db: AsyncSession,
        category: str | None = None,
        parent_id: str | None = None,
    ) -> BrainDumpResponse:
        """
        Process a voice brain dump into task proposals for user review.

        All voice/text input flows through this method. Returns structured
        task proposals that the user can review, edit, and submit separately.

        Args:
            transcription: Raw voice transcription or typed text
            user_id: User ID
            db: Database session
            category: Optional pre-fill category for all tasks
            parent_id: Optional parent task ID for subtask mode

        Returns:
            BrainDumpResponse with list of proposed tasks
        """
        logger.info("braindump.process", transcription_length=len(transcription), parent_id=parent_id)

        # Pre-filter — catch gibberish before LLM
        prefilter_result = prefilter(transcription)
        if prefilter_result is not None:
            return BrainDumpResponse(
                success=False, tasks=[], transcription=transcription,
                message="Could not understand input. Please try rephrasing.",
            )

        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)

        # Build structured task list for Stage 2 parent placement
        all_tasks = await task_service.get_tasks(user_id)
        task_tree = [
            {
                "id": str(t.id),
                "title": t.title,
                "category": t.category,
                "parent_id": str(t.parent_id) if t.parent_id else None,
                "status": t.status,
            }
            for t in all_tasks
        ]

        # If parent_id provided (subtask mode), look up parent for default category
        parent_category = None
        if parent_id:
            parent_task = await task_service.get_task(parent_id)
            if parent_task:
                parent_category = parent_task.category
                logger.debug("braindump.process.subtask_mode", parent_title=parent_task.title, category=parent_category)

        # Get task proposals from Gemini (two-stage pipeline)
        raw_tasks = await self.gemini.detect_brain_dump(transcription, tree_context, task_tree=task_tree)

        if not raw_tasks:
            return BrainDumpResponse(
                success=False,
                tasks=[],
                transcription=transcription,
                message="Could not extract any tasks. Try rephrasing.",
            )

        # Deduplicate: Gemini sometimes returns identical entries
        seen = set()
        deduped = []
        for raw in raw_tasks:
            key = (raw.get("action", "add").lower(), raw.get("content", "").strip().lower())
            if key not in seen:
                seen.add(key)
                deduped.append(raw)
            else:
                logger.debug("braindump.process.dedup", content=key[1], action=key[0])
        raw_tasks = deduped

        # Get available categories for validation
        available_categories = await task_service.get_categories(user_id)

        # Convert raw Gemini output to task proposals
        proposals: List[BrainDumpTaskProposal] = []
        for raw in raw_tasks:
            content = raw.get("content", "").strip()
            if not content:
                continue

            action = raw.get("action", "add").lower()

            # Backward compat: convert old "move" actions to "edit" with changes.parent_id
            if action == "move":
                action = "edit"
                changes = raw.get("changes") or {}
                target_query = raw.get("targetParentQuery")
                if target_query:
                    changes["_targetParentQuery"] = target_query  # resolve later
                else:
                    changes["parent_id"] = None  # move to root
                raw["changes"] = changes

            confidence = raw.get("confidence", 0.5)
            # Brain dump uses flat 0.6 threshold (lower than voice commands) because
            # users review all proposals before submission — false positives are caught in UI
            if confidence < 0.6:
                logger.warning("braindump.process.low_confidence", confidence=confidence, content=content)
                continue

            task_category = category or parent_category or raw.get("category", "home")

            # For actions on existing tasks, resolve via search
            matched_task_id = None
            alternate_matches = None
            match_explanation = None
            if action in ("complete", "edit", "delete", "breakdown"):
                matched = await self._search_tasks(user_id, content, db, task_service)
                if matched:
                    top_task, top_score = matched[0]
                    matched_task_id = str(top_task.id)
                    task_category = top_task.category or task_category
                    match_explanation = f"Matched '{top_task.title}' (similarity: {int(top_score * 100)}%)"
                    content = top_task.title  # show real task title in proposal UI
                    logger.debug("braindump.process.resolved", task_id=matched_task_id, score=int(top_score))
                    if len(matched) > 1:
                        alternate_matches = [
                            {"id": str(m.id), "title": m.title, "category": m.category}
                            for m, _s in matched[1:4]  # top 3 alternatives
                        ]

                    # For COMPLETE: check active children and note in description
                    if action == "complete":
                        children = await task_service.get_tasks(user_id, parent_id=matched_task_id)
                        active_children = [c for c in children if c.status == "active"]
                        if active_children:
                            child_note = f"Will also complete {len(active_children)} sub-task{'s' if len(active_children) != 1 else ''}"
                            existing_desc = raw.get("description") or ""
                            raw["description"] = f"{child_note}. {existing_desc}".strip().rstrip(".")
                else:
                    logger.warning("braindump.process.unresolved", content=content, action=action)
                    continue

            # BREAKDOWN: expand into ADD subtask proposals inline
            if action == "breakdown" and matched_task_id:
                matched_task = await task_service.get_task(matched_task_id)
                if matched_task:
                    subtask_titles = await self.gemini.generate_subtasks(
                        matched_task.title, matched_task.description, tree_context)
                    for sub in subtask_titles:
                        proposals.append(BrainDumpTaskProposal(
                            id=str(uuid.uuid4()), action="add", content=sub,
                            category=task_category.lower(), parent_id=matched_task_id))
                continue  # don't append raw breakdown proposal

            # EDIT with reparenting: resolve changes._targetParentQuery or changes.parent_id
            if action == "edit":
                changes = raw.get("changes") or {}
                target_query = changes.pop("_targetParentQuery", None)
                if target_query:
                    targets = await self._search_tasks(user_id, target_query, db, task_service)
                    if targets:
                        changes["parent_id"] = str(targets[0][0].id)
                    else:
                        logger.warning("braindump.process.unresolved", content=target_query, action="reparent")
                        continue
                # If changes.parent_id is a search query string (from LLM), resolve it
                elif "parent_id" in changes and changes["parent_id"] is not None:
                    pid = changes["parent_id"]
                    # Check if it looks like a UUID (already resolved) or a search query
                    try:
                        uuid.UUID(str(pid))
                    except ValueError:
                        # It's a search query, resolve it
                        targets = await self._search_tasks(user_id, str(pid), db, task_service)
                        if targets:
                            changes["parent_id"] = str(targets[0][0].id)
                        else:
                            logger.warning("braindump.process.unresolved", content=str(pid), action="reparent")
                            continue
                raw["changes"] = changes

            # Resolve parent for ADD proposals
            resolved_parent_id = None
            if action == "add":
                if parent_id:
                    # Subtask mode: default to the pre-filled parent
                    resolved_parent_id = parent_id
                # Gemini's parentQuery can still override for relative nesting
                parent_query = raw.get("parentQuery")
                if parent_query:
                    parent_tasks = await self._search_tasks(user_id, parent_query, db, task_service)
                    if parent_tasks:
                        resolved_parent_id = str(parent_tasks[0][0].id)

            proposals.append(BrainDumpTaskProposal(
                id=str(uuid.uuid4()),
                action=action,
                content=content,
                description=raw.get("description"),
                category=task_category.lower(),
                due_date=parse_flexible_date(raw.get("dueDate")),
                priority=raw.get("priority"),
                parent_id=resolved_parent_id,
                labels=raw.get("labels", []),
                changes=raw.get("changes"),
                matched_task_id=matched_task_id,
                confidence=confidence,
                tags=raw.get("tags"),
                estimated_hours=raw.get("estimatedHours"),
                alternate_matches=alternate_matches,
                match_explanation=match_explanation,
            ))

        logger.info("braindump.process.done", proposal_count=len(proposals))

        return BrainDumpResponse(
            success=True,
            tasks=proposals,
            transcription=transcription,
            message=f"Found {len(proposals)} tasks",
        )

    async def _execute_action(
        self,
        proposal: BrainDumpTaskProposal,
        user_id: str,
        task_service: TaskService,
    ) -> dict:
        """Execute a single proposal action. Shared by submit_brain_dump().

        Returns:
            dict with {type, count, task_id?} describing what happened.
        """
        import time as _time
        action = proposal.action or "add"
        _t0 = _time.monotonic()
        logger.debug("braindump.action.start", action=action, content=proposal.content)

        if action == "complete" and proposal.matched_task_id:
            count = await task_service.complete_task_with_children(proposal.matched_task_id)
            logger.debug("braindump.action.done", action="complete", duration_ms=round((_time.monotonic()-_t0)*1000, 1))
            return {"type": "completed", "count": count}

        # Backward compat: convert old "move" to "edit" at execution time
        if action == "move" and proposal.matched_task_id:
            action = "edit"
            if not proposal.changes:
                proposal.changes = {}
            if hasattr(proposal, 'target_parent_id') and getattr(proposal, 'target_parent_id', None):
                proposal.changes["parent_id"] = proposal.target_parent_id
            elif "parent_id" not in proposal.changes:
                proposal.changes["parent_id"] = None  # move to root

        if action == "edit" and proposal.matched_task_id:
            changes = dict(proposal.changes or {})
            if 'dueDate' in changes:
                changes['due_date'] = parse_flexible_date(changes.pop('dueDate'))
            # Validate parent_id target exists before reparenting
            if 'parent_id' in changes and changes['parent_id'] is not None:
                target = await task_service.get_task(changes['parent_id'])
                if not target:
                    raise ValueError(f"Reparent target '{changes['parent_id']}' no longer exists")
            if changes:
                await task_service.update_task(proposal.matched_task_id, **changes)
            logger.debug("braindump.action.done", action="edit", duration_ms=round((_time.monotonic()-_t0)*1000, 1))
            return {"type": "edited", "count": 1}

        if action == "delete" and proposal.matched_task_id:
            count = await task_service.delete_task_with_children(proposal.matched_task_id)
            logger.debug("braindump.action.done", action="delete", duration_ms=round((_time.monotonic()-_t0)*1000, 1))
            return {"type": "deleted", "count": count}

        # Default: ADD — auto-create category if needed
        available_categories = await task_service.get_categories(user_id)
        cat = proposal.category.lower()
        if cat not in available_categories:
            if len(available_categories) < 8:
                await task_service.create_category(user_id, cat)
            else:
                cat = "home"  # at limit, fall back
        task = await task_service.create_task(
            user_id=user_id,
            title=proposal.content,
            category=cat,
            parent_id=proposal.parent_id,
            transcription=proposal.content,
            description=proposal.description,
            due_date=proposal.due_date,
            priority=proposal.priority,
            tags=proposal.tags,
            estimated_hours=proposal.estimated_hours,
            ai_placement={
                "confidence": proposal.confidence or 0.9,
                "reasoning": "Brain dump voice input",
            },
        )
        logger.debug("braindump.action.done", action="add", duration_ms=round((_time.monotonic()-_t0)*1000, 1))
        return {"type": "created", "count": 1, "task_id": task.id}

    async def submit_brain_dump(
        self,
        user_id: str,
        tasks: List[BrainDumpTaskProposal],
        db: AsyncSession,
    ) -> BrainDumpSubmitResponse:
        """
        Commit reviewed brain dump tasks to the database.

        All actions are executed atomically — if ANY action fails, ALL changes
        are rolled back and no tasks are created/modified/deleted.

        Args:
            user_id: User ID
            tasks: List of reviewed/edited task proposals
            db: Database session

        Returns:
            BrainDumpSubmitResponse with created task IDs
        """
        logger.info("braindump.submit.start", task_count=len(tasks))

        if not tasks:
            return BrainDumpSubmitResponse(
                success=False,
                created_count=0,
                created_task_ids=[],
                message="Failed to process any tasks",
            )

        # Use auto_commit=False so individual task_service methods flush
        # instead of committing, allowing atomic batch rollback.
        task_service = TaskService(db, auto_commit=False)
        created_ids: List[str] = []
        counts: Dict[str, int] = {}

        try:
            for proposal in tasks:
                result = await self._execute_action(proposal, user_id, task_service)
                rtype = result["type"]
                counts[rtype] = counts.get(rtype, 0) + result["count"]
                if result.get("task_id"):
                    created_ids.append(result["task_id"])

            # All actions succeeded — commit the entire batch
            await db.commit()
        except Exception as e:
            await db.rollback()
            error_msg = str(e)
            logger.error(
                "braindump.submit.rollback",
                error=error_msg,
                task_count=len(tasks),
            )
            return BrainDumpSubmitResponse(
                success=False,
                created_count=0,
                created_task_ids=[],
                message="All actions rolled back due to an internal error",
                failed_reason="internal_error",
            )

        total = sum(counts.values())

        # Build summary message with actual counts (including cascaded children)
        label_map = {"created": "Created", "completed": "completed", "edited": "edited", "deleted": "deleted"}
        parts = [f"{label_map.get(k, k)} {v}" for k, v in counts.items()]
        message = ", ".join(parts) + f" task{'s' if total != 1 else ''}"

        return BrainDumpSubmitResponse(
            success=True,
            created_count=len(created_ids),
            created_task_ids=created_ids,
            message=message,
        )

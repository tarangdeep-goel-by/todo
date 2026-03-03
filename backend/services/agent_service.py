"""Agent service for processing voice commands via brain dump pipeline."""
import logging
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict, Any, List, Optional
import uuid
from .gemini_service import GeminiService
from .task_service import TaskService
from .task_search_service import TaskSearchService
from .intent_prefilter import prefilter
from models.schemas import BrainDumpResponse, BrainDumpTaskProposal, BrainDumpSubmitResponse
from utils.date_parser import parse_flexible_date
from config import get_settings

logger = logging.getLogger(__name__)


class AgentService:
    """Service for processing voice/text commands via brain dump pipeline."""

    def __init__(self, gemini_service: GeminiService):
        """Initialize with Gemini service."""
        self.gemini = gemini_service

    async def _resolve_parent_search(self, user_id: str, query: str, db: AsyncSession, task_service: TaskService):
        """Search for a parent task by query, dispatching on search engine."""
        settings = get_settings()
        if settings.search_engine == "pg_native":
            search = TaskSearchService(db)
            results = await search.search(user_id, query, status_filter="active")
            return [task for task, score in results]
        else:
            return await task_service.search_tasks(user_id, query)

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
        logger.info("process_brain_dump: transcription='%s', user_id='%s', parent_id=%s", transcription, user_id, parent_id)

        # Pre-filter — catch gibberish before LLM
        prefilter_result = prefilter(transcription)
        if prefilter_result is not None:
            return BrainDumpResponse(
                success=False, tasks=[], transcription=transcription,
                message="Could not understand input. Please try rephrasing.",
            )

        task_service = TaskService(db)
        settings = get_settings()
        compressed = settings.search_engine == "pg_native"
        tree_context = await task_service.build_full_tree_context(user_id, compressed=compressed)

        # If parent_id provided (subtask mode), look up parent for default category
        parent_category = None
        if parent_id:
            parent_task = await task_service.get_task(parent_id)
            if parent_task:
                parent_category = parent_task.category
                logger.debug("subtask mode: parent='%s', category='%s'", parent_task.title, parent_category)

        # Get task proposals from Gemini
        raw_tasks = await self.gemini.detect_brain_dump(transcription, tree_context)

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
                logger.debug("brain dump dedup: dropped duplicate '%s' (%s)", key[1], key[0])
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

            confidence = raw.get("confidence", 0.5)
            # Brain dump uses flat 0.6 threshold (lower than voice commands) because
            # users review all proposals before submission — false positives are caught in UI
            if confidence < 0.6:
                logger.warning("brain dump skipping low-confidence (%.2f): '%s'", confidence, content)
                continue

            task_category = category or parent_category or raw.get("category", "home")

            # For actions on existing tasks, resolve via search
            matched_task_id = None
            alternate_matches = None
            if action in ("complete", "edit", "delete", "move", "breakdown"):
                if settings.search_engine == "pg_native":
                    search = TaskSearchService(db)
                    search_results = await search.search(user_id, content, status_filter="active")
                    matched = [task for task, score in search_results]
                else:
                    matched = await task_service.search_tasks(user_id, content)
                if matched:
                    matched_task_id = str(matched[0].id)
                    task_category = matched[0].category or task_category
                    content = matched[0].title  # show real task title in proposal UI
                    logger.debug("brain dump resolved '%s' → task '%s' (%s)", content, matched[0].title, matched_task_id)
                    if len(matched) > 1:
                        alternate_matches = [
                            {"id": str(m.id), "title": m.title, "category": m.category}
                            for m in matched[1:4]  # top 3 alternatives
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
                    logger.warning("brain dump could not resolve '%s' for %s, skipping", content, action)
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

            # MOVE: resolve target parent
            target_parent_id = None
            target_content = None
            if action == "move":
                target_query = raw.get("targetParentQuery")
                if target_query:
                    targets = await self._resolve_parent_search(user_id, target_query, db, task_service)
                    if targets:
                        target_parent_id = str(targets[0].id)
                        target_content = targets[0].title
                    else:
                        logger.warning("brain dump could not resolve move target '%s', skipping", target_query)
                        continue
                else:
                    target_content = "top-level"  # move to root

            # Resolve parent for ADD proposals
            resolved_parent_id = None
            if action == "add":
                if parent_id:
                    # Subtask mode: default to the pre-filled parent
                    resolved_parent_id = parent_id
                # Gemini's parentQuery can still override for relative nesting
                parent_query = raw.get("parentQuery")
                if parent_query:
                    parent_tasks = await self._resolve_parent_search(user_id, parent_query, db, task_service)
                    if parent_tasks:
                        resolved_parent_id = str(parent_tasks[0].id)

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
                target_parent_id=target_parent_id,
                target_content=target_content,
                confidence=confidence,
                tags=raw.get("tags"),
                estimated_hours=raw.get("estimatedHours"),
                alternate_matches=alternate_matches,
            ))

        logger.info("brain dump produced %d task proposals", len(proposals))

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
        logger.debug("_execute_action START: action=%s content='%s' matched=%s", action, proposal.content, proposal.matched_task_id)

        if action == "complete" and proposal.matched_task_id:
            count = await task_service.complete_task_with_children(proposal.matched_task_id)
            logger.debug("_execute_action DONE in %.0fms: completed '%s' + %d children", (_time.monotonic()-_t0)*1000, proposal.content, count - 1)
            return {"type": "completed", "count": count}

        if action == "edit" and proposal.matched_task_id:
            changes = dict(proposal.changes or {})
            if 'dueDate' in changes:
                changes['due_date'] = parse_flexible_date(changes.pop('dueDate'))
            if changes:
                await task_service.update_task(proposal.matched_task_id, **changes)
            logger.debug("_execute_action DONE in %.0fms: edited '%s': %s", (_time.monotonic()-_t0)*1000, proposal.content, changes)
            return {"type": "edited", "count": 1}

        if action == "delete" and proposal.matched_task_id:
            count = await task_service.delete_task_with_children(proposal.matched_task_id)
            logger.debug("_execute_action DONE in %.0fms: deleted '%s' + %d children", (_time.monotonic()-_t0)*1000, proposal.content, count - 1)
            return {"type": "deleted", "count": count}

        if action == "move" and proposal.matched_task_id:
            if proposal.target_parent_id:
                target = await task_service.get_task(proposal.target_parent_id)
                if not target:
                    raise ValueError(f"Move target '{proposal.target_parent_id}' no longer exists")
            await task_service.update_task(proposal.matched_task_id, parent_id=proposal.target_parent_id)
            logger.debug("_execute_action DONE in %.0fms: moved '%s' → %s", (_time.monotonic()-_t0)*1000, proposal.content, proposal.target_parent_id)
            return {"type": "moved", "count": 1}

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
        logger.debug("_execute_action DONE in %.0fms: created '%s' (%s)", (_time.monotonic()-_t0)*1000, task.title, task.id)
        return {"type": "created", "count": 1, "task_id": task.id}

    async def submit_brain_dump(
        self,
        user_id: str,
        tasks: List[BrainDumpTaskProposal],
        db: AsyncSession,
    ) -> BrainDumpSubmitResponse:
        """
        Commit reviewed brain dump tasks to the database.

        Args:
            user_id: User ID
            tasks: List of reviewed/edited task proposals
            db: Database session

        Returns:
            BrainDumpSubmitResponse with created task IDs
        """
        logger.info("submit_brain_dump: %d tasks for user '%s'", len(tasks), user_id)

        task_service = TaskService(db)
        created_ids: List[str] = []
        counts: Dict[str, int] = {}

        for proposal in tasks:
            try:
                result = await self._execute_action(proposal, user_id, task_service)
                rtype = result["type"]
                counts[rtype] = counts.get(rtype, 0) + result["count"]
                if result.get("task_id"):
                    created_ids.append(result["task_id"])
            except Exception as e:
                logger.error("failed to process '%s' (%s): %s", proposal.content, proposal.action, e)

        total = sum(counts.values())
        if total == 0:
            return BrainDumpSubmitResponse(
                success=False,
                created_count=0,
                created_task_ids=[],
                message="Failed to process any tasks",
            )

        # Build summary message with actual counts (including cascaded children)
        label_map = {"created": "Created", "completed": "completed", "edited": "edited", "deleted": "deleted", "moved": "moved"}
        parts = [f"{label_map.get(k, k)} {v}" for k, v in counts.items()]
        message = ", ".join(parts) + f" task{'s' if total != 1 else ''}"

        return BrainDumpSubmitResponse(
            success=True,
            created_count=len(created_ids),
            created_task_ids=created_ids,
            message=message,
        )

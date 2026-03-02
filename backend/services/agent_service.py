"""Agent service for processing voice commands."""
import logging
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict, Any, List, Tuple, Optional
import uuid
from .gemini_service import GeminiService
from .task_service import TaskService
from models.schemas import AgentResponse, BrainDumpResponse, BrainDumpTaskProposal, BrainDumpSubmitResponse
from utils.date_parser import parse_flexible_date

logger = logging.getLogger(__name__)


class AgentService:
    """Service for processing voice commands and executing intents."""

    def __init__(self, gemini_service: GeminiService):
        """Initialize with Gemini service."""
        self.gemini = gemini_service

    async def process_voice_command(
        self,
        transcription: str,
        user_id: str,
        db: AsyncSession
    ) -> AgentResponse:
        """
        Main entry point for voice command processing.

        Supports multi-intent commands — Gemini returns an array of intents
        that are executed sequentially. Results are aggregated into one response.

        Args:
            transcription: Cleaned transcription from frontend
            user_id: User ID
            db: Database session

        Returns:
            AgentResponse with success, message, type, and data
        """
        logger.info("process_voice_command: transcription='%s', user_id='%s'", transcription, user_id)

        # Step 1: Build FULL task tree context (both work and personal)
        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)
        logger.debug("tree context: %d chars", len(tree_context))

        # Step 2: Detect intent(s) — returns a list
        intent_list = await self.gemini.detect_intent(transcription, tree_context)
        logger.info("received %d intent(s)", len(intent_list))

        # Step 3: Execute each intent sequentially, aggregate results
        results: List[AgentResponse] = []
        for i, intent_data in enumerate(intent_list):
            logger.debug("processing intent %d/%d", i + 1, len(intent_list))
            result = await self._execute_single_intent(intent_data, user_id, db, task_service)

            # If any intent returns a question, stop and return it immediately
            if result.type == "question":
                logger.debug("intent %d returned question — stopping", i + 1)
                return result

            results.append(result)

        # Step 4: Aggregate results
        if not results:
            return AgentResponse(
                success=False,
                message="No actions detected. Try rephrasing.",
                type="error",
                data={}
            )

        if len(results) == 1:
            return results[0]

        # Multiple results — combine into one response
        return self._aggregate_results(results)

    async def _execute_single_intent(
        self,
        intent_data: Dict,
        user_id: str,
        db: AsyncSession,
        task_service: TaskService,
    ) -> AgentResponse:
        """Execute a single intent and return its response."""
        # Validate confidence
        if intent_data.get('confidence', 0) < 0.6:
            logger.warning("low confidence %.2f — rejecting", intent_data.get('confidence', 0))
            return AgentResponse(
                success=False,
                message="Not sure what you meant. Please try rephrasing.",
                type="error",
                data=intent_data
            )

        intent = intent_data['intent']
        params = intent_data.get('parameters', {})
        logger.info("routing intent=%s", intent)

        if intent == "ADD":
            return await self._handle_add(params, user_id, db, task_service)
        elif intent == "COMPLETE":
            return await self._handle_complete(params, user_id, db, task_service)
        elif intent == "DELETE":
            return await self._handle_delete(params, user_id, db, task_service)
        elif intent == "EDIT":
            return await self._handle_edit(params, user_id, db, task_service)
        elif intent == "MOVE":
            return await self._handle_move(params, user_id, db, task_service)
        elif intent == "BREAKDOWN":
            return await self._handle_breakdown(params, user_id, db, task_service)
        elif intent == "QUERY":
            return await self._handle_query(params, user_id, db, task_service)
        else:
            return AgentResponse(
                success=False,
                message="Unclear command. Try: 'Add [task]', 'Complete [task]', 'Move [task] under [parent]'",
                type="error",
                data=intent_data
            )

    def _aggregate_results(self, results: List[AgentResponse]) -> AgentResponse:
        """Combine multiple intent results into a single response."""
        successes = [r for r in results if r.success]
        failures = [r for r in results if not r.success]

        # Build combined message
        messages = [r.message for r in successes]
        combined_message = " | ".join(messages)

        if failures:
            fail_msgs = [r.message for r in failures]
            combined_message += f" (failed: {'; '.join(fail_msgs)})"

        # Collect all task data
        all_data = {
            "results": [r.data for r in results if r.data],
            "total_actions": len(results),
            "successful": len(successes),
            "failed": len(failures),
        }

        return AgentResponse(
            success=len(successes) > 0,
            message=combined_message,
            type="confirmation",
            data=all_data
        )

    async def _handle_add(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle ADD intent."""

        # Check if agent suggests creating new branch
        valid_domains = {"work", "personal", "health", "learning", "projects"}
        suggested = (params.get('suggestedBranchName') or '').lower().strip()
        if params.get('needsNewBranch') and suggested not in valid_domains:
            # Get current categories
            current_categories = await task_service.get_categories(user_id)
            category_count = len(current_categories)

            # Check if we're at the 5-category limit
            if category_count >= 5:
                categories_list = ", ".join(current_categories)
                return AgentResponse(
                    success=False,
                    message=f"You've reached the maximum of 5 categories. Current categories: {categories_list}. Which category should this task go under?",
                    type="error",
                    data={
                        "current_categories": current_categories,
                        "max_categories_reached": True,
                        "suggested_task": params['title']
                    }
                )

            # Under limit - ask for confirmation
            return AgentResponse(
                success=False,
                message=f"This task seems like it belongs in a '{params['suggestedBranchName']}' category. Current categories: {', '.join(current_categories)}. Create '{params['suggestedBranchName']}' category for this task?",
                type="question",
                data={
                    "intent": "ADD",
                    "suggested_title": params['title'],
                    "suggested_category": params['suggestedBranchName'],
                    "current_categories": current_categories,
                    "reasoning": params.get('reasoning', ''),
                    "action": "create_category"
                }
            )

        # Normal task creation (agent determined category + parent)
        # Use suggestedBranchName as category if it's a valid domain and category isn't
        category = (params.get('category') or '').lower().strip()
        if category not in valid_domains and suggested in valid_domains:
            category = suggested

        # If category is still empty/invalid after all fallbacks, ask user to pick
        if category not in valid_domains:
            current_categories = await task_service.get_categories(user_id)
            return AgentResponse(
                success=False,
                message=f"Which category should '{params['title']}' go in?",
                type="question",
                data={
                    "intent": "ADD",
                    "action": "select_category",
                    "suggested_title": params['title'],
                    "description": params.get('description'),
                    "priority": params.get('priority'),
                    "dueDate": params.get('dueDate'),
                    "suggestedParent": params.get('suggestedParent'),
                    "reasoning": params.get('reasoning', ''),
                    "current_categories": current_categories,
                }
            )

        parsed_due_date = parse_flexible_date(params.get('dueDate'))
        task = await task_service.create_task(
            user_id=user_id,
            title=params['title'],
            category=category or params['category'],
            parent_id=params.get('suggestedParent'),
            transcription=params['title'],
            ai_placement={
                "suggested_parent": params.get('suggestedParent'),
                "confidence": params.get('confidence', 0.9),
                "reasoning": params.get('reasoning', '')
            },
            description=params.get('description'),
            priority=params.get('priority'),
            tags=None,
            estimated_hours=params.get('estimatedHours'),
            due_date=parsed_due_date
        )

        # Get parent info for response message
        parent_info = ""
        if params.get('suggestedParent') and params['suggestedParent'] not in ['root-work', 'root-personal']:
            parent = await task_service.get_task(params['suggestedParent'])
            if parent:
                parent_info = f" under {parent.title}"

        return AgentResponse(
            success=True,
            message=f"Created task '{task.title}' in {task.category.title()}{parent_info}",
            type="confirmation",
            data={
                "task_id": task.id,
                "title": task.title,
                "category": task.category,
                "parent_id": task.parent_id,
                "reasoning": params.get('reasoning', '')
            }
        )

    async def _resolve_tasks(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService | None = None) -> List:
        """Resolve tasks from Gemini's matchedTasks IDs, falling back to fuzzy search."""
        task_service = task_service or TaskService(db)

        # Try Gemini's direct ID matches first
        matched_ids = params.get('matchedTasks', [])
        if matched_ids:
            tasks = []
            for tid in matched_ids:
                task = await task_service.get_task(tid)
                if task and task.status == 'active':
                    tasks.append(task)
            if tasks:
                logger.debug("resolved %d tasks via matchedTasks IDs", len(tasks))
                return tasks

        # Fallback to fuzzy search
        query = params.get('taskQuery', '')
        if query:
            tasks = await task_service.search_tasks(user_id, query)
            logger.debug("fuzzy search for '%s' found %d tasks", query, len(tasks))
            return tasks

        return []

    async def _resolve_and_disambiguate(
        self,
        params: Dict,
        user_id: str,
        db: AsyncSession,
        action: str,
        intent: str,
        extra_data: Dict | None = None,
        task_service: TaskService | None = None,
    ) -> Tuple[Optional[object], Optional[AgentResponse]]:
        """Resolve tasks and handle empty/ambiguous results.

        Returns (task, None) on single match, or (None, AgentResponse) if
        the caller should return early (no match or disambiguation needed).
        """
        query = params.get('taskQuery', '')
        matched_tasks = await self._resolve_tasks(params, user_id, db, task_service)

        if not matched_tasks:
            return None, AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query},
            )

        if len(matched_tasks) > 1:
            data = {
                "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                "action": action,
                "intent": intent,
            }
            if extra_data:
                data.update(extra_data)
            return None, AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data=data,
            )

        return matched_tasks[0], None

    async def _handle_complete(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle COMPLETE intent."""
        task, early = await self._resolve_and_disambiguate(params, user_id, db, "complete", "COMPLETE", task_service=task_service)
        if early:
            return early
        children = await task_service.get_tasks(user_id, parent_id=task.id)
        active_children = [c for c in children if c.status == "active"]

        if active_children:
            count = await task_service.complete_task_with_children(task.id)
            return AgentResponse(
                success=True,
                message=f"Completed task '{task.title}' and {count - 1} sub-tasks",
                type="confirmation",
                data={"task_id": task.id, "title": task.title, "completed_count": count}
            )

        await task_service.complete_task(task.id)
        return AgentResponse(
            success=True,
            message=f"Completed task '{task.title}'",
            type="confirmation",
            data={"task_id": task.id, "title": task.title}
        )

    async def _handle_delete(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle DELETE intent."""
        task, early = await self._resolve_and_disambiguate(params, user_id, db, "delete", "DELETE", task_service=task_service)
        if early:
            return early
        count = await task_service.delete_task_with_children(task.id)

        return AgentResponse(
            success=True,
            message=f"Deleted task '{task.title}' and {count - 1} sub-tasks",
            type="confirmation",
            data={"task_id": task.id, "deleted_count": count}
        )

    async def _handle_edit(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle EDIT intent."""
        task, early = await self._resolve_and_disambiguate(
            params, user_id, db, "edit", "EDIT",
            extra_data={"changes": params.get('changes', {})},
            task_service=task_service,
        )
        if early:
            return early
        changes = params.get('changes', {})
        if 'dueDate' in changes:
            changes['due_date'] = parse_flexible_date(changes.pop('dueDate'))
        await task_service.update_task(task.id, **changes)

        return AgentResponse(
            success=True,
            message=f"Updated task '{task.title}'",
            type="confirmation",
            data={"task_id": task.id, "changes": changes}
        )

    async def _handle_move(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle MOVE intent."""
        target_parent_query = params.get('targetParentQuery')
        target_parent_id = params.get('targetParentId')

        task, early = await self._resolve_and_disambiguate(
            params, user_id, db, "move", "MOVE",
            extra_data={"targetParentQuery": target_parent_query},
            task_service=task_service,
        )
        if early:
            return early

        # If target parent specified, search for it
        new_parent_id = target_parent_id
        parent_title = "top-level"

        if target_parent_query:
            parent_tasks = await task_service.search_tasks(user_id, target_parent_query)

            if not parent_tasks:
                return AgentResponse(
                    success=False,
                    message=f"No parent task found matching '{target_parent_query}'",
                    type="error",
                    data={"targetParentQuery": target_parent_query}
                )

            if len(parent_tasks) > 1:
                return AgentResponse(
                    success=False,
                    message=f"Found {len(parent_tasks)} possible parent tasks. Which one?",
                    type="question",
                    data={
                        "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in parent_tasks],
                        "action": "select_parent",
                        "intent": "MOVE",
                        "taskToMove": task.id
                    }
                )

            new_parent_id = parent_tasks[0].id
            parent_title = parent_tasks[0].title

        # Move the task
        await task_service.update_task(task.id, parent_id=new_parent_id)

        return AgentResponse(
            success=True,
            message=f"Moved '{task.title}' under {parent_title}",
            type="confirmation",
            data={
                "task_id": task.id,
                "title": task.title,
                "new_parent_id": new_parent_id,
                "parent_title": parent_title,
                "reasoning": params.get('reasoning', '')
            }
        )

    async def resolve_question(
        self,
        user_id: str,
        selected_task_id: str | None,
        action: str,
        data: Dict | None,
        db: AsyncSession
    ) -> AgentResponse:
        """Resolve a question response by executing the chosen action."""
        task_service = TaskService(db)
        data = data or {}

        if action == "complete":
            task = await task_service.get_task(selected_task_id)
            if not task:
                return AgentResponse(success=False, message="Task not found", type="error")

            children = await task_service.get_tasks(user_id, parent_id=task.id)
            active_children = [c for c in children if c.status == "active"]
            if active_children:
                count = await task_service.complete_task_with_children(task.id)
                return AgentResponse(
                    success=True,
                    message=f"Completed '{task.title}' and {count - 1} sub-tasks",
                    type="confirmation",
                    data={"task_id": task.id, "title": task.title}
                )
            await task_service.complete_task(task.id)
            return AgentResponse(
                success=True,
                message=f"Completed '{task.title}'",
                type="confirmation",
                data={"task_id": task.id, "title": task.title}
            )

        elif action == "delete":
            task = await task_service.get_task(selected_task_id)
            if not task:
                return AgentResponse(success=False, message="Task not found", type="error")
            count = await task_service.delete_task_with_children(task.id)
            return AgentResponse(
                success=True,
                message=f"Deleted '{task.title}' and {count - 1} sub-tasks",
                type="confirmation",
                data={"task_id": task.id, "deleted_count": count}
            )

        elif action == "edit":
            task = await task_service.get_task(selected_task_id)
            if not task:
                return AgentResponse(success=False, message="Task not found", type="error")
            changes = data.get('changes', {})
            if 'dueDate' in changes:
                changes['due_date'] = parse_flexible_date(changes.pop('dueDate'))
            await task_service.update_task(task.id, **changes)
            return AgentResponse(
                success=True,
                message=f"Updated '{task.title}'",
                type="confirmation",
                data={"task_id": task.id, "changes": changes}
            )

        elif action == "move":
            task = await task_service.get_task(selected_task_id)
            if not task:
                return AgentResponse(success=False, message="Task not found", type="error")

            target_parent_query = data.get('targetParentQuery')
            if not target_parent_query:
                return AgentResponse(success=False, message="No target parent specified", type="error")

            parent_tasks = await task_service.search_tasks(user_id, target_parent_query)
            if not parent_tasks:
                return AgentResponse(
                    success=False,
                    message=f"No parent task found matching '{target_parent_query}'",
                    type="error"
                )
            if len(parent_tasks) > 1:
                return AgentResponse(
                    success=False,
                    message=f"Found {len(parent_tasks)} possible parent tasks. Which one?",
                    type="question",
                    data={
                        "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in parent_tasks],
                        "action": "select_parent",
                        "intent": "MOVE",
                        "taskToMove": task.id
                    }
                )
            await task_service.update_task(task.id, parent_id=parent_tasks[0].id)
            return AgentResponse(
                success=True,
                message=f"Moved '{task.title}' under '{parent_tasks[0].title}'",
                type="confirmation",
                data={"task_id": task.id, "new_parent_id": parent_tasks[0].id}
            )

        elif action == "select_parent":
            task_to_move_id = data.get('taskToMove')
            task = await task_service.get_task(task_to_move_id)
            if not task:
                return AgentResponse(success=False, message="Task to move not found", type="error")
            parent = await task_service.get_task(selected_task_id)
            if not parent:
                return AgentResponse(success=False, message="Parent task not found", type="error")
            await task_service.update_task(task.id, parent_id=parent.id)
            return AgentResponse(
                success=True,
                message=f"Moved '{task.title}' under '{parent.title}'",
                type="confirmation",
                data={"task_id": task.id, "new_parent_id": parent.id}
            )

        elif action == "select_breakdown_target":
            task = await task_service.get_task(selected_task_id)
            if not task:
                return AgentResponse(success=False, message="Task not found", type="error")
            tree_context = await task_service.build_full_tree_context(user_id)
            suggestions = await self.gemini.generate_subtasks(
                task_title=task.title,
                task_description=task.description,
                context=tree_context,
            )
            if not suggestions:
                return AgentResponse(
                    success=False,
                    message=f"Could not generate subtasks for '{task.title}'",
                    type="error",
                    data={"task_id": task.id}
                )
            return AgentResponse(
                success=True,
                message=f"Suggested subtasks for '{task.title}'",
                type="question",
                data={
                    "action": "select_subtasks",
                    "parent_task": {"id": task.id, "title": task.title, "category": task.category},
                    "suggestions": suggestions,
                }
            )

        elif action == "create_subtasks":
            parent_task_id = data.get('parent_task_id')
            selected_titles = data.get('selected_titles', [])
            if not parent_task_id or not selected_titles:
                return AgentResponse(success=False, message="Missing parent task or subtask titles", type="error")

            parent = await task_service.get_task(parent_task_id)
            if not parent:
                return AgentResponse(success=False, message="Parent task not found", type="error")

            created_ids = []
            for title in selected_titles:
                sub = await task_service.create_task(
                    user_id=user_id,
                    title=title,
                    category=parent.category,
                    category_id=parent.category_id,
                    parent_id=parent.id,
                    transcription=title,
                    ai_placement={"suggested_parent": parent.id, "confidence": 0.95, "reasoning": "Breakdown subtask"},
                )
                created_ids.append(sub.id)

            return AgentResponse(
                success=True,
                message=f"Created {len(created_ids)} subtasks under '{parent.title}'",
                type="confirmation",
                data={
                    "parent_task_id": parent.id,
                    "created_count": len(created_ids),
                    "created_ids": created_ids,
                }
            )

        elif action == "select_category":
            title = data.get('suggested_title', '')
            category = data.get('selected_category', '')
            if not title or not category:
                return AgentResponse(success=False, message="Missing title or category", type="error")

            parsed_due_date = parse_flexible_date(data.get('dueDate'))
            task = await task_service.create_task(
                user_id=user_id,
                title=title,
                category=category.lower().strip(),
                parent_id=data.get('suggestedParent'),
                transcription=title,
                description=data.get('description'),
                priority=data.get('priority'),
                due_date=parsed_due_date,
                ai_placement={
                    "suggested_parent": data.get('suggestedParent'),
                    "confidence": 0.9,
                    "reasoning": data.get('reasoning', ''),
                },
            )
            return AgentResponse(
                success=True,
                message=f"Created '{task.title}' in {task.category.title()}",
                type="confirmation",
                data={"task_id": task.id, "title": task.title, "category": task.category}
            )

        elif action == "create_category":
            title = data.get('suggested_title', '')
            category = data.get('suggested_category', '')
            if not title or not category:
                return AgentResponse(success=False, message="Missing title or category", type="error")

            # Ensure category exists in categories table
            cat_name = category.lower()
            existing_cats = await task_service.get_categories(user_id)
            if cat_name not in existing_cats:
                try:
                    await task_service.create_category(user_id, cat_name)
                except ValueError as e:
                    return AgentResponse(success=False, message=str(e), type="error")

            # Create the task at top-level (parent_id=None)
            task = await task_service.create_task(
                user_id=user_id,
                title=title,
                category=cat_name,
                parent_id=None,
                transcription=title,
                ai_placement={"suggested_parent": None, "confidence": 0.9, "reasoning": "User confirmed category creation"},
            )
            return AgentResponse(
                success=True,
                message=f"Created '{title}' in new '{category.title()}' category",
                type="confirmation",
                data={"task_id": task.id, "title": task.title, "category": task.category}
            )

        return AgentResponse(success=False, message=f"Unknown action: {action}", type="error")

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

        Unlike process_voice_command() which auto-executes, this returns
        structured task proposals that the user can review, edit, and
        submit separately.

        Args:
            transcription: Raw voice transcription
            user_id: User ID
            db: Database session
            category: Optional pre-fill category for all tasks
            parent_id: Optional parent task ID for subtask mode

        Returns:
            BrainDumpResponse with list of proposed tasks
        """
        logger.info("process_brain_dump: transcription='%s', user_id='%s', parent_id=%s", transcription, user_id, parent_id)

        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)

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
            if confidence < 0.6:
                logger.warning("brain dump skipping low-confidence (%.2f): '%s'", confidence, content)
                continue

            task_category = category or parent_category or raw.get("category", "personal")

            # For actions on existing tasks, resolve via fuzzy search
            matched_task_id = None
            alternate_matches = None
            if action in ("complete", "edit", "delete", "move", "breakdown"):
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
                    targets = await task_service.search_tasks(user_id, target_query)
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
                    parent_tasks = await task_service.search_tasks(user_id, parent_query)
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
            if len(available_categories) < 5:
                await task_service.create_category(user_id, cat)
            else:
                cat = "personal"  # at limit, fall back
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

    async def _handle_breakdown(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle BREAKDOWN intent — generate subtask suggestions for a task."""
        task, early = await self._resolve_and_disambiguate(
            params, user_id, db, "select_breakdown_target", "BREAKDOWN",
            task_service=task_service,
        )
        if early:
            return early
        tree_context = await task_service.build_full_tree_context(user_id)
        suggestions = await self.gemini.generate_subtasks(
            task_title=task.title,
            task_description=task.description,
            context=tree_context,
        )

        if not suggestions:
            return AgentResponse(
                success=False,
                message=f"Could not generate subtasks for '{task.title}'",
                type="error",
                data={"task_id": task.id}
            )

        return AgentResponse(
            success=True,
            message=f"Suggested subtasks for '{task.title}'",
            type="question",
            data={
                "action": "select_subtasks",
                "parent_task": {"id": task.id, "title": task.title, "category": task.category},
                "suggestions": suggestions,
            }
        )

    async def _handle_query(self, params: Dict, user_id: str, db: AsyncSession, task_service: TaskService) -> AgentResponse:
        """Handle QUERY intent."""
        filters = params.get('filters', {})

        tasks = await task_service.get_tasks(
            user_id=user_id,
            category=filters.get('category'),
            status=filters.get('status', 'active')
        )

        if not tasks:
            return AgentResponse(
                success=True,
                message="No tasks found",
                type="confirmation",
                data={"tasks": [], "count": 0}
            )

        return AgentResponse(
            success=True,
            message=f"Found {len(tasks)} tasks",
            type="confirmation",
            data={
                "tasks": [{"id": t.id, "title": t.title, "category": t.category} for t in tasks],
                "count": len(tasks)
            }
        )

"""Agent service for processing voice commands."""
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict, Any, List
import uuid
from .gemini_service import GeminiService
from .task_service import TaskService
from models.schemas import AgentResponse, BrainDumpResponse, BrainDumpTaskProposal, BrainDumpSubmitResponse
from utils.date_parser import parse_flexible_date


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
        print(f"\n{'='*60}")
        print(f"[Agent] INPUT: transcription='{transcription}', user_id='{user_id}'")

        # Step 1: Build FULL task tree context (both work and personal)
        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)
        print(f"[Agent] tree context: {len(tree_context)} chars")

        # Step 2: Detect intent(s) — returns a list
        intent_list = await self.gemini.detect_intent(transcription, tree_context)
        print(f"[Agent] received {len(intent_list)} intent(s)")

        # Step 3: Execute each intent sequentially, aggregate results
        results: List[AgentResponse] = []
        for i, intent_data in enumerate(intent_list):
            print(f"[Agent] processing intent {i+1}/{len(intent_list)}")
            result = await self._execute_single_intent(intent_data, user_id, db)

            # If any intent returns a question, stop and return it immediately
            if result.type == "question":
                print(f"[Agent] intent {i+1} returned question — stopping")
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
        db: AsyncSession
    ) -> AgentResponse:
        """Execute a single intent and return its response."""
        # Validate confidence
        if intent_data.get('confidence', 0) < 0.6:
            print(f"[Agent] LOW CONFIDENCE: {intent_data.get('confidence')} — rejecting")
            return AgentResponse(
                success=False,
                message="Not sure what you meant. Please try rephrasing.",
                type="error",
                data=intent_data
            )

        intent = intent_data['intent']
        params = intent_data.get('parameters', {})
        print(f"[Agent] ROUTING: intent={intent}")

        if intent == "ADD":
            return await self._handle_add(params, user_id, db)
        elif intent == "COMPLETE":
            return await self._handle_complete(params, user_id, db)
        elif intent == "DELETE":
            return await self._handle_delete(params, user_id, db)
        elif intent == "EDIT":
            return await self._handle_edit(params, user_id, db)
        elif intent == "MOVE":
            return await self._handle_move(params, user_id, db)
        elif intent == "BREAKDOWN":
            return await self._handle_breakdown(params, user_id, db)
        elif intent == "QUERY":
            return await self._handle_query(params, user_id, db)
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

    async def _handle_add(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle ADD intent."""
        task_service = TaskService(db)

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

    async def _resolve_tasks(self, params: Dict, user_id: str, db: AsyncSession) -> List:
        """Resolve tasks from Gemini's matchedTasks IDs, falling back to fuzzy search."""
        task_service = TaskService(db)

        # Try Gemini's direct ID matches first
        matched_ids = params.get('matchedTasks', [])
        if matched_ids:
            tasks = []
            for tid in matched_ids:
                task = await task_service.get_task(tid)
                if task and task.status == 'active':
                    tasks.append(task)
            if tasks:
                print(f"[Agent] resolved {len(tasks)} tasks via matchedTasks IDs")
                return tasks

        # Fallback to fuzzy search
        query = params.get('taskQuery', '')
        if query:
            tasks = await task_service.search_tasks(user_id, query)
            print(f"[Agent] fuzzy search for '{query}' found {len(tasks)} tasks")
            return tasks

        return []

    async def _handle_complete(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle COMPLETE intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        matched_tasks = await self._resolve_tasks(params, user_id, db)

        if not matched_tasks:
            return AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query}
            )

        if len(matched_tasks) > 1:
            return AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data={
                    "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                    "action": "complete",
                    "intent": "COMPLETE"
                }
            )

        # Complete the task (and children if any)
        task = matched_tasks[0]
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

    async def _handle_delete(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle DELETE intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        matched_tasks = await self._resolve_tasks(params, user_id, db)

        if not matched_tasks:
            return AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query}
            )

        if len(matched_tasks) > 1:
            return AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data={
                    "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                    "action": "delete",
                    "intent": "DELETE"
                }
            )

        # Hard delete the task and descendants
        task = matched_tasks[0]
        count = await task_service.delete_task_with_children(task.id)

        return AgentResponse(
            success=True,
            message=f"Deleted task '{task.title}' and {count - 1} sub-tasks",
            type="confirmation",
            data={"task_id": task.id, "deleted_count": count}
        )

    async def _handle_edit(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle EDIT intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        matched_tasks = await self._resolve_tasks(params, user_id, db)

        if not matched_tasks:
            return AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query}
            )

        if len(matched_tasks) > 1:
            return AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data={
                    "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                    "action": "edit",
                    "intent": "EDIT",
                    "changes": params.get('changes', {})
                }
            )

        # Update the task
        task = matched_tasks[0]
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

    async def _handle_move(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle MOVE intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')
        target_parent_query = params.get('targetParentQuery')
        target_parent_id = params.get('targetParentId')

        matched_tasks = await self._resolve_tasks(params, user_id, db)

        if not matched_tasks:
            return AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query}
            )

        if len(matched_tasks) > 1:
            return AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data={
                    "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                    "action": "move",
                    "intent": "MOVE",
                    "targetParentQuery": target_parent_query
                }
            )

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
                        "taskToMove": matched_tasks[0].id
                    }
                )

            new_parent_id = parent_tasks[0].id
            parent_title = parent_tasks[0].title

        # Move the task
        task = matched_tasks[0]
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

        Returns:
            BrainDumpResponse with list of proposed tasks
        """
        print(f"\n{'='*60}")
        print(f"[Agent] BRAIN DUMP: transcription='{transcription}', user_id='{user_id}'")

        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)

        # Get task proposals from Gemini
        raw_tasks = await self.gemini.detect_brain_dump(transcription, tree_context)

        if not raw_tasks:
            return BrainDumpResponse(
                success=False,
                tasks=[],
                transcription=transcription,
                message="Could not extract any tasks. Try rephrasing.",
            )

        # Get available categories for validation
        available_categories = await task_service.get_categories(user_id)

        # Convert raw Gemini output to task proposals
        proposals: List[BrainDumpTaskProposal] = []
        for raw in raw_tasks:
            content = raw.get("content", "").strip()
            if not content:
                continue

            action = raw.get("action", "add").lower()

            task_category = category or raw.get("category", "personal")
            # Validate category exists; fall back to "personal"
            if task_category.lower() not in available_categories:
                task_category = "personal"

            # For complete/edit actions, resolve the existing task via fuzzy search
            matched_task_id = None
            if action in ("complete", "edit"):
                matched = await task_service.search_tasks(user_id, content)
                if matched:
                    matched_task_id = str(matched[0].id)
                    task_category = matched[0].category or task_category
                    print(f"[Agent] brain dump resolved '{content}' → task '{matched[0].title}' ({matched_task_id})")
                else:
                    print(f"[Agent] brain dump could not resolve '{content}' for {action}, skipping")
                    continue

            # Resolve parent if parentQuery provided (ADD only)
            parent_id = None
            if action == "add":
                parent_query = raw.get("parentQuery")
                if parent_query:
                    parent_tasks = await task_service.search_tasks(user_id, parent_query)
                    if parent_tasks:
                        parent_id = str(parent_tasks[0].id)

            proposals.append(BrainDumpTaskProposal(
                id=str(uuid.uuid4()),
                action=action,
                content=content,
                description=raw.get("description"),
                category=task_category.lower(),
                due_date=parse_flexible_date(raw.get("dueDate")),
                priority=raw.get("priority"),
                parent_id=parent_id,
                labels=raw.get("labels", []),
                changes=raw.get("changes"),
                matched_task_id=matched_task_id,
            ))

        print(f"[Agent] brain dump produced {len(proposals)} task proposals")

        return BrainDumpResponse(
            success=True,
            tasks=proposals,
            transcription=transcription,
            message=f"Found {len(proposals)} tasks",
        )

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
        print(f"\n{'='*60}")
        print(f"[Agent] SUBMIT BRAIN DUMP: {len(tasks)} tasks for user '{user_id}'")

        task_service = TaskService(db)
        created_ids: List[str] = []
        completed_count = 0
        edited_count = 0

        for proposal in tasks:
            try:
                action = proposal.action or "add"

                if action == "complete" and proposal.matched_task_id:
                    await task_service.complete_task(proposal.matched_task_id)
                    completed_count += 1
                    print(f"[Agent] completed task '{proposal.content}' ({proposal.matched_task_id})")

                elif action == "edit" and proposal.matched_task_id:
                    changes = proposal.changes or {}
                    update_data = {}
                    if "priority" in changes:
                        update_data["priority"] = changes["priority"]
                    if "dueDate" in changes:
                        update_data["due_date"] = parse_flexible_date(changes["dueDate"])
                    if "category" in changes:
                        update_data["category"] = changes["category"]
                    if "title" in changes:
                        update_data["title"] = changes["title"]
                    if update_data:
                        await task_service.update_task(proposal.matched_task_id, **update_data)
                    edited_count += 1
                    print(f"[Agent] edited task '{proposal.content}' ({proposal.matched_task_id}): {changes}")

                else:
                    # Default: ADD
                    task = await task_service.create_task(
                        user_id=user_id,
                        title=proposal.content,
                        category=proposal.category,
                        parent_id=proposal.parent_id,
                        transcription=proposal.content,
                        description=proposal.description,
                        due_date=proposal.due_date,
                        priority=proposal.priority,
                        ai_placement={
                            "confidence": 0.9,
                            "reasoning": "Brain dump voice input",
                        },
                    )
                    created_ids.append(task.id)
                    print(f"[Agent] created task '{task.title}' ({task.id})")

            except Exception as e:
                print(f"[Agent] failed to process '{proposal.content}' ({proposal.action}): {e}")

        total = len(created_ids) + completed_count + edited_count
        if total == 0:
            return BrainDumpSubmitResponse(
                success=False,
                created_count=0,
                created_task_ids=[],
                message="Failed to process any tasks",
            )

        # Build summary message
        parts = []
        if created_ids:
            parts.append(f"Created {len(created_ids)}")
        if completed_count:
            parts.append(f"completed {completed_count}")
        if edited_count:
            parts.append(f"edited {edited_count}")
        message = ", ".join(parts) + f" task{'s' if total != 1 else ''}"

        return BrainDumpSubmitResponse(
            success=True,
            created_count=len(created_ids),
            created_task_ids=created_ids,
            message=message,
        )

    async def _handle_breakdown(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle BREAKDOWN intent — generate subtask suggestions for a task."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        matched_tasks = await self._resolve_tasks(params, user_id, db)

        if not matched_tasks:
            return AgentResponse(
                success=False,
                message=f"No tasks found matching '{query}'",
                type="error",
                data={"taskQuery": query}
            )

        if len(matched_tasks) > 1:
            return AgentResponse(
                success=False,
                message=f"Found {len(matched_tasks)} tasks matching '{query}'. Which one?",
                type="question",
                data={
                    "matches": [{"id": t.id, "title": t.title, "category": t.category} for t in matched_tasks],
                    "action": "select_breakdown_target",
                    "intent": "BREAKDOWN"
                }
            )

        # Single match — generate subtask suggestions
        task = matched_tasks[0]
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

    async def _handle_query(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle QUERY intent."""
        task_service = TaskService(db)
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

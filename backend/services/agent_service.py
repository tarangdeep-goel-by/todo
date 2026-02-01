"""Agent service for processing voice commands."""
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Dict, Any
from .gemini_service import GeminiService
from .task_service import TaskService
from models.schemas import AgentResponse
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

        Args:
            transcription: Cleaned transcription from frontend
            user_id: User ID
            db: Database session

        Returns:
            AgentResponse with success, message, type, and data
        """
        # Step 1: Refine transcription
        refined = await self.gemini.refine_transcription(transcription)

        # Step 2: Build FULL task tree context (both work and personal)
        task_service = TaskService(db)
        tree_context = await task_service.build_full_tree_context(user_id)

        # Step 3: Detect intent (agent determines category, parent, everything)
        intent_data = await self.gemini.detect_intent(refined, tree_context)

        # Step 4: Validate confidence
        if intent_data['confidence'] < 0.6:
            return AgentResponse(
                success=False,
                message="Not sure what you meant. Please try rephrasing.",
                type="error",
                data=intent_data
            )

        # Step 5: Route to handler
        intent = intent_data['intent']
        params = intent_data.get('parameters', {})

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
        elif intent == "QUERY":
            return await self._handle_query(params, user_id, db)
        else:
            return AgentResponse(
                success=False,
                message="Unclear command. Try: 'Add [task]', 'Complete [task]', 'Move [task] under [parent]'",
                type="error",
                data=intent_data
            )

    async def _handle_add(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle ADD intent."""
        task_service = TaskService(db)

        # Check if agent suggests creating new branch
        if params.get('needsNewBranch'):
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
        parsed_due_date = parse_flexible_date(params.get('dueDate'))
        task = await task_service.create_task(
            user_id=user_id,
            title=params['title'],
            category=params['category'],
            parent_id=params.get('suggestedParent'),
            transcription=params['title'],
            ai_placement={
                "suggested_parent": params.get('suggestedParent'),
                "confidence": params.get('confidence', 0.9),
                "reasoning": params.get('reasoning', '')
            },
            priority=params.get('priority'),
            tags=params.get('tags'),
            notes=params.get('notes'),
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

    async def _handle_complete(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle COMPLETE intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        # Search for matching tasks
        matched_tasks = await task_service.search_tasks(user_id, query)

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
                    "matches": [{"id": t.id, "title": t.title} for t in matched_tasks],
                    "action": "complete",
                    "intent": "COMPLETE"
                }
            )

        # Complete the task
        task = matched_tasks[0]
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

        # Search for matching tasks
        matched_tasks = await task_service.search_tasks(user_id, query)

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
                    "matches": [{"id": t.id, "title": t.title} for t in matched_tasks],
                    "action": "delete",
                    "intent": "DELETE"
                }
            )

        # Archive the task and descendants
        task = matched_tasks[0]
        count = await task_service.archive_task(task.id)

        return AgentResponse(
            success=True,
            message=f"Archived task '{task.title}' and {count - 1} descendants",
            type="confirmation",
            data={"task_id": task.id, "archived_count": count}
        )

    async def _handle_edit(self, params: Dict, user_id: str, db: AsyncSession) -> AgentResponse:
        """Handle EDIT intent."""
        task_service = TaskService(db)
        query = params.get('taskQuery', '')

        # Search for matching tasks
        matched_tasks = await task_service.search_tasks(user_id, query)

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
                    "matches": [{"id": t.id, "title": t.title} for t in matched_tasks],
                    "action": "edit",
                    "intent": "EDIT"
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

        # Search for task to move
        matched_tasks = await task_service.search_tasks(user_id, query)

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
                    "matches": [{"id": t.id, "title": t.title} for t in matched_tasks],
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
                        "matches": [{"id": t.id, "title": t.title} for t in parent_tasks],
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

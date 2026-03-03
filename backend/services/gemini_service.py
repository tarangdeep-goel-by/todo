"""Gemini AI service for brain dump detection and subtask generation."""
import logging
from google import genai
from google.genai import types
from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional, Union
import json

from config import get_settings

logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────
# Schema models for structured output
# ──────────────────────────────────────────────

class EditChanges(BaseModel):
    """Fields to change on an existing task (for edit actions only)."""
    title: Optional[str] = Field(default=None, description="New title if renaming the task")
    priority: Optional[str] = Field(default=None, description="New priority: high, medium, or low")
    dueDate: Optional[str] = Field(default=None, description="New due date string, e.g. 'tomorrow', 'next monday'")
    category: Optional[str] = Field(default=None, description="New category if changing category")


class BrainDumpAction(BaseModel):
    """A single action extracted from a brain dump transcription."""
    action: str = Field(description="One of: add, complete, edit, delete, move, breakdown")
    content: str = Field(description="For add: task title using user's words. For complete/edit/delete/move/breakdown: search query to find the existing task")
    category: str = Field(description="Lowercase category from the task tree, or a sensible default like career, finance, health, relationships, growth, recreation, home, community")
    confidence: float = Field(description="0.0-1.0 confidence this is a real action, not filler/noise")
    description: Optional[str] = Field(default=None, description="Additional context, or null if speech was brief")
    dueDate: Optional[str] = Field(default=None, description="Date string if mentioned (add only)")
    priority: Optional[str] = Field(default=None, description="high/medium/low if mentioned (add only)")
    parentQuery: Optional[str] = Field(default=None, description="Search query for parent task if hierarchy implied (add only)")
    estimatedHours: Optional[float] = Field(default=None, description="Time estimate in hours if mentioned")
    tags: Optional[List[str]] = Field(default=None, description="Tag strings if mentioned")
    changes: Optional[EditChanges] = Field(default=None, description="REQUIRED for edit action — the fields being changed")
    targetParentQuery: Optional[str] = Field(default=None, description="For move: search query for destination parent. Omit or null for top-level")


class GeminiService:
    """Service for Gemini API integration."""

    MODEL = 'gemini-2.5-flash-lite'

    def __init__(self, api_key: str):
        """Initialize Gemini service with API key."""
        self.client = genai.Client(api_key=api_key)

    async def detect_brain_dump(
        self,
        transcription: str,
        task_tree_context: str
    ) -> List[Dict[str, Any]]:
        """
        Parse a voice brain dump into structured task proposals.

        Uses the new google-genai SDK with schema-enforced JSON output.

        Args:
            transcription: Raw voice transcription (may contain multiple tasks)
            task_tree_context: String representation of user's current task tree

        Returns:
            List of task proposal dicts, each with action, content, category, etc.
        """
        settings = get_settings()
        use_pg_native = settings.search_engine == "pg_native"

        if use_pg_native:
            context_desc = """The task tree below shows the user's current tasks organized by category.
Each category header (e.g. "CAREER:") represents a top-level domain — use the lowercase
form (e.g. "career") as the category value. Tasks are nested with indentation showing parent-child
relationships. [done] marks completed tasks."""
        else:
            context_desc = """The task tree below shows the user's current tasks organized by category.
Each category header (e.g. "CAREER TASKS:") represents a top-level domain — use the lowercase
form (e.g. "career") as the category value. Tasks are nested with "├──" showing parent-child
relationships. Task IDs are shown in parentheses."""

        prompt = f"""<context>
{context_desc}

{task_tree_context}
</context>

<input>
{transcription}
</input>

<instructions>
The input is a raw voice brain dump — messy, multi-action, with possible filler words and corrections.

Extract each distinct action. Action types:
- add: new task to create
- complete: existing task the user finished
- edit: change to an existing task (priority, due date, category, title)
- delete: existing task to remove
- move: reparent a task under a different parent
- breakdown: split a task into subtasks

Rules:
- Query requests ("show me", "list", "what are", "display", "how many") → return []. Brain dump is mutations only. Examples: "show me all work tasks" → []. "what's on my list?" → [].
- If a task name matches something in the tree, it's likely complete/edit/delete, not add
- COMPLETE vs EDIT: "completed X" / "finished X" / "done with X" / "X is done" / "complete the X" → ALWAYS complete (never edit). The verb complete/finished/done unambiguously means mark-as-done.
- Completion verb + NO tree match: "finish the report" but no "report" task in tree → ADD (user wants to create it, not mark complete)
- Existing task + field changes: task exists in tree AND user mentions priority/due date → EDIT (not add duplicate). E.g. "buy running shoes with high priority" where "buy new running shoes" is in tree → edit with changes.priority="high"
- "X is high/low priority" / "set X priority to high" → edit with changes
- "X belongs in Y category" → edit with changes.category (not move)
- "move X under Y" → move (reparenting, not category change)
- "move X to top level" / "put X to top level" / "X to root" → move with targetParentQuery=null (reparent to root level, NOT edit)
- "add X under Y" / "create X under Y" → add with parentQuery="Y" (MUST set parentQuery when "under Y" is specified)
- Each distinct task mentioned = separate action. Never merge different tasks into one action. E.g. "finished report, schedule meeting, set budget priority high" = 3 actions.
- Filler speech ("um", "let me think") → skip
- Self-corrections ("no wait, I mean...") → use the correction only
- Near-duplicates ("buy milk", "get milk", "purchase milk") → merge into one
- If the tree is empty, pick categories from: career, finance, health, relationships, growth, recreation, home, community
- Return [] for pure filler or nonsense with no actionable content

For edit actions, always populate the `changes` object with the modified field:
- "change X priority to low" → action: edit, changes: {{priority: "low"}}
- "reschedule X to next monday" → action: edit, changes: {{dueDate: "next monday"}}
- "X belongs in home" → action: edit, changes: {{category: "home"}}
- "rename X to Y" → action: edit, changes: {{title: "Y"}}

Common mistakes to avoid:
- "complete the payment" (task "Payment integration v2" exists) → action: COMPLETE ✓ (not edit!)
- "finished reviewing applications" (task "Review senior dev applications" exists) → action: COMPLETE ✓ (not edit!)
- "put Riverpod patterns to top level" → action: MOVE, targetParentQuery: null ✓ (not edit!)
- "buy running shoes with high priority" (task "buy new running shoes" exists) → action: EDIT, changes: {{priority: "high"}} ✓ (not add!)
- "show me all my career tasks" → return [] ✓ (query, not mutation)
</instructions>"""

        try:
            response = await self.client.aio.models.generate_content(
                model=self.MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type='application/json',
                    response_schema=list[BrainDumpAction],
                ),
            )

            logger.info("brain_dump raw response: %s", response.text)
            result = json.loads(response.text)

            # Normalize: always return a list
            if isinstance(result, dict):
                result = [result]
            if not isinstance(result, list):
                raise ValueError(f"Expected JSON array, got {type(result)}")

            for task in result:
                # Normalize category: strip tree header artifacts, lowercase
                cat = (task.get("category") or "home").lower()
                cat = cat.replace(" tasks", "").rstrip(":").strip()
                task["category"] = cat

                # For edit actions: ensure changes dict is populated from top-level fields
                if task.get("action") == "edit":
                    changes = task.get("changes") or {}
                    if not changes.get("priority") and task.get("priority"):
                        changes["priority"] = task["priority"]
                    if not changes.get("dueDate") and task.get("dueDate"):
                        changes["dueDate"] = task["dueDate"]
                    if changes:
                        task["changes"] = changes

            for i, task in enumerate(result):
                logger.info("brain_dump[%d]: content='%s' | category='%s'", i, task.get('content'), task.get('category'))

            return result

        except Exception as e:
            logger.error("brain dump detection FAILED: %s", e, exc_info=True)
            return []

    async def generate_subtasks(self, task_title: str, task_description: str | None = None, context: str = "") -> List[str]:
        """Generate 4-6 actionable subtask suggestions for a given task.

        Args:
            task_title: Title of the task to break down
            task_description: Optional description for more context
            context: Task tree context for awareness

        Returns:
            List of subtask title strings
        """
        desc_line = f"\nDescription: {task_description}" if task_description else ""
        prompt = f"""Task to break down: "{task_title}"{desc_line}

Current task tree context:
{context}

Generate 4-6 actionable subtasks for the task above. Each subtask should be:
- Specific and actionable (starts with a verb or clear action)
- Concise (2-6 words)
- Independent enough to track separately
- Together they should cover the full scope of the parent task

Respond ONLY with a valid JSON array of strings. Example:
["Research options", "Create outline", "Draft first version", "Review and revise", "Submit final"]
"""
        try:
            response = await self.client.aio.models.generate_content(
                model=self.MODEL,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type='application/json',
                    response_schema=list[str],
                ),
            )

            result = json.loads(response.text)

            if not isinstance(result, list) or not all(isinstance(s, str) for s in result):
                raise ValueError("Expected JSON array of strings")

            logger.info("generated %d subtask suggestions for '%s'", len(result), task_title)
            return result

        except Exception as e:
            logger.error("subtask generation FAILED: %s", e)
            return []

"""Gemini AI service for transcription and intent detection."""
from google import genai
from google.genai import types
from pydantic import BaseModel, Field
from typing import Dict, Any, List, Optional, Union
import json
import re


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
    category: str = Field(description="Lowercase category from the task tree, or a sensible default like work, personal, health, learning, finance, hobbies, family, home")
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

        # Keep legacy model for detect_intent/generate_subtasks until they're migrated
        import google.generativeai as genai_legacy
        genai_legacy.configure(api_key=api_key)
        self._legacy_model = genai_legacy.GenerativeModel(self.MODEL)

    async def detect_intent(
        self,
        transcription: str,
        task_tree_context: str
    ) -> List[Dict[str, Any]]:
        """
        Detect user intent(s) and extract parameters from a voice/text command.

        Handles transcription cleanup internally — no separate refine step needed.
        Returns a list of intents (single-element for simple commands, multi-element
        for compound commands like "add X and Y under Z").

        Args:
            transcription: Raw user command (voice transcription or typed text)
            task_tree_context: String representation of task tree

        Returns:
            List of intent dicts, each with intent, confidence, parameters.
        """
        prompt = f"""Current task tree:
{task_tree_context}

User said: "{transcription}"

IMPORTANT: The input may be a raw voice transcription with filler words (um, uh, like),
minor errors, or odd spacing. Mentally clean it up before analyzing, but preserve all
task names, proper nouns, and multi-word phrases EXACTLY as the user said them.
Do NOT join separate words into one (e.g. "safe drop" must stay "safe drop", not "SafeDrop").
Do NOT split a single command into multiple sentences.

Detect the user's intent. Available intents:
- ADD: Create new task (keywords: add, create, new, remember, note)
- COMPLETE: Mark task(s) as done (keywords: complete, completed, done, finish, finished, mark). IMPORTANT: "completed [task name]" or "finished [task name]" means the user wants to COMPLETE that task
- DELETE: Remove/archive task(s) (keywords: delete, remove, archive, cancel)
- EDIT: Modify existing task properties — title, priority, due date, OR category (keywords: edit, change, update, rename, reschedule, "is a [category] task", "belongs in [category]", "should be in [category]")
- MOVE: Move task to a different PARENT TASK within the tree (keywords: move under, put under, relocate under). MOVE is ONLY for changing parent-child relationships, NOT for changing categories.
- BREAKDOWN: User wants to break a task into subtasks (keywords: break down, split, decompose, break into steps, break into subtasks)
- UNKNOWN: Unclear intent

CRITICAL DISTINCTION — EDIT vs MOVE:
- Changing a task's CATEGORY (work, personal, health, etc.) = EDIT with changes.category
  Examples: "X is a work task", "X belongs in personal", "change X to work category"
- Changing a task's PARENT (putting it under another task) = MOVE
  Examples: "move X under Y", "put X under project Alpha"
- If user says "[task] is a [category] task" → this is EDIT (category change), NOT MOVE

For ADD tasks:
- Determine category based on task nature
- Default categories: "work" and "personal"
- If task clearly doesn't fit work/personal (hobbies, health, learning, community, finance, etc.), suggest new category
- Set needsNewBranch=true when suggesting new category (max 5 categories total)
- If user explicitly mentions a category name not in the tree (e.g., "Add X to Hobbies"), treat it as new category creation
- Find the best parent task in the tree, or use null for top-level tasks

When to suggest new categories (needsNewBranch=true):
- Hobbies: music practice, art projects, collections, crafts
- Health: doctor appointments, fitness goals, mental health
- Learning: courses, reading, skill development
- Finance: budgeting, investments, taxes
- Community: volunteering, local events, activism
- Travel: trip planning, vacation tasks

When user creates new category:
- "Add X to [CategoryName]" where CategoryName is NOT in current tree → category=CategoryName, needsNewBranch=false (user is explicitly creating it)
- "Create [CategoryName] category" → Just acknowledge, wait for actual task
- "Yes" or "Create it" after previous suggestion → Need explicit category mention to proceed

MULTI-TASK COMMANDS:
If the user's command contains MULTIPLE independent actions, return a JSON ARRAY with one
object per action. Each object has its own intent, confidence, and parameters.
- "add X and Y under Z" → two ADD objects, both with suggestedParent pointing to Z
- "complete A and delete B" → one COMPLETE + one DELETE object
- "add X, Y, and Z to work" → three ADD objects

For single-action commands, still return a JSON array with ONE element.

Each element in the array uses this format:
{{
  "intent": "ADD|COMPLETE|DELETE|EDIT|MOVE|UNKNOWN",
  "confidence": 0.95,
  "parameters": {{
    // For ADD:
    "title": "short concise task title (2-6 words)",  // Keep titles brief and scannable
    "description": "longer description with context and details from speech, or null if speech was already brief",
    "category": "work" or "personal" or suggest new category name,
    "suggestedParent": "task-id or null for top-level",
    "reasoning": "Why this category/parent was chosen",
    "needsNewBranch": false,  // Set to true if suggesting new top-level category
    "suggestedBranchName": "",  // Only if needsNewBranch=true
    "priority": "high|medium|low or null",  // Extract if mentioned (urgent, important, etc.)
    "dueDate": "relative date string or ISO datetime or null",  // Extract if mentioned - use strings like "tomorrow", "next monday", "in 3 days", etc. NOT ISO format
    "estimatedHours": number or null  // Time estimate if mentioned

    // For COMPLETE/DELETE:
    "taskQuery": "search terms to find the task",
    "matchedTasks": ["task-id-1", "task-id-2"]

    // For EDIT (includes category changes, priority changes, due date changes, title changes):
    "taskQuery": "search terms to find the task — use the task name as the user said it",
    "changes": {{
      "title": "new title if mentioned",
      "dueDate": "ISO date if mentioned",
      "priority": "high|medium|low if mentioned",
      "category": "work or personal if mentioned"
    }}

    // For MOVE (parent task changes ONLY — NOT category changes):
    "taskQuery": "search terms to find the task to move",
    "targetParentQuery": "search terms to find the new parent",
    "targetParentId": "task-id or null",
    "reasoning": "Why this move makes sense"

    IMPORTANT for MOVE intent:
    - If user says "move to top level", "move to main level", "move to root",
      "shouldn't be under anything", set targetParentId=null and targetParentQuery=null
    - If user specifies a parent task, set targetParentQuery with search terms
    - Use targetParentId=null to indicate top-level placement (no parent)

    // For BREAKDOWN:
    "taskQuery": "search terms to find the task to break down"

    // For QUERY:
    "query": "search criteria",
    "filters": {{
      "category": "work or personal if mentioned",
      "status": "active or completed if mentioned"
    }}
  }}
}}

Respond ONLY with a valid JSON ARRAY. Examples:

Single command (array of 1):
[{{"intent": "ADD", "confidence": 0.95, "parameters": {{"title": "Groceries", "category": "personal", "suggestedParent": null, "reasoning": "Personal errand", "needsNewBranch": false}}}}]

Multi-task command (array of N):
- "add tech spec and program plan under safe drop" →
[
  {{"intent": "ADD", "confidence": 0.95, "parameters": {{"title": "Tech spec", "category": "work", "suggestedParent": "<safe-drop-task-id>", "reasoning": "Sub-task of safe drop"}}}},
  {{"intent": "ADD", "confidence": 0.95, "parameters": {{"title": "Program plan", "category": "work", "suggestedParent": "<safe-drop-task-id>", "reasoning": "Sub-task of safe drop"}}}}
]

- "complete grocery shopping and add meal prep" →
[
  {{"intent": "COMPLETE", "confidence": 0.95, "parameters": {{"taskQuery": "grocery shopping"}}}},
  {{"intent": "ADD", "confidence": 0.95, "parameters": {{"title": "Meal prep", "category": "personal", "suggestedParent": null, "reasoning": "Personal task"}}}}
]

More examples:
- "create a new task safe drop" → [{{"intent": "ADD", ...}}]
- "Complete the backend API task" → [{{"intent": "COMPLETE", "confidence": 0.95, "parameters": {{"taskQuery": "backend API"}}}}]
- "Completed easy runs this week" → [{{"intent": "COMPLETE", ...}}]
- "safe drop is a work task" → [{{"intent": "EDIT", "confidence": 0.95, "parameters": {{"taskQuery": "safe drop", "changes": {{"category": "work"}}}}}}]
- "Move groceries under shopping list" → [{{"intent": "MOVE", ...}}]
- "add X, Y, and Z under project Alpha" → 3 ADD objects in the array, all with suggestedParent=Alpha's ID
"""

        try:
            response = self._legacy_model.generate_content(prompt)

            if not response.text:
                raise ValueError("Empty response from Gemini")

            # Extract JSON from response (handle markdown code blocks)
            json_text = self._extract_json(response.text)
            result = json.loads(json_text)

            # Normalize: always return a list
            if isinstance(result, dict):
                result = [result]

            for i, intent in enumerate(result):
                print(f"[Gemini] intent[{i}]: {intent.get('intent')} | confidence: {intent.get('confidence')} | params: {intent.get('parameters')}")

            return result

        except Exception as e:
            print(f"[Gemini] intent detection FAILED: {e}")
            # Return UNKNOWN intent on failure
            return [{
                "intent": "UNKNOWN",
                "confidence": 0.0,
                "parameters": {}
            }]

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
        prompt = f"""<context>
The task tree below shows the user's current tasks organized by category.
Each category header (e.g. "WORK TASKS:") represents a top-level domain — use the lowercase
form (e.g. "work") as the category value. Tasks are nested with "├──" showing parent-child
relationships. Task IDs are shown in parentheses.

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
- If a task name matches something in the tree, it's likely complete/edit/delete, not add
- "finished X" / "done with X" / "completed X" → complete
- "X is high/low priority" → edit with changes
- "X belongs in Y category" → edit with changes.category (not move)
- "move X under Y" → move (reparenting, not category change)
- Query requests ("show me", "list") → skip (brain dump is mutations only)
- Filler speech ("um", "let me think") → skip
- Self-corrections ("no wait, I mean...") → use the correction only
- Near-duplicates ("buy milk", "get milk", "purchase milk") → merge into one
- If the tree is empty, pick categories from: work, personal, health, learning, finance, hobbies, family, home
- Return [] for pure filler or nonsense with no actionable content

For edit actions, always populate the `changes` object with the modified field:
- "change X priority to low" → action: edit, changes: {{priority: "low"}}
- "reschedule X to next monday" → action: edit, changes: {{dueDate: "next monday"}}
- "X belongs in personal" → action: edit, changes: {{category: "personal"}}
- "rename X to Y" → action: edit, changes: {{title: "Y"}}
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

            result = json.loads(response.text)

            # Normalize: always return a list
            if isinstance(result, dict):
                result = [result]
            if not isinstance(result, list):
                raise ValueError(f"Expected JSON array, got {type(result)}")

            for task in result:
                # Normalize category: strip tree header artifacts, lowercase
                cat = (task.get("category") or "personal").lower()
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
                print(f"[Gemini] brain_dump[{i}]: content='{task.get('content')}' | category='{task.get('category')}' | due='{task.get('dueDate')}'")

            return result

        except Exception as e:
            print(f"[Gemini] brain dump detection FAILED: {e}")
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
            response = self._legacy_model.generate_content(prompt)
            if not response.text:
                raise ValueError("Empty response from Gemini")

            json_text = self._extract_json(response.text)
            result = json.loads(json_text)

            if not isinstance(result, list) or not all(isinstance(s, str) for s in result):
                raise ValueError("Expected JSON array of strings")

            print(f"[Gemini] generated {len(result)} subtask suggestions for '{task_title}'")
            return result

        except Exception as e:
            print(f"[Gemini] subtask generation FAILED: {e}")
            return []

    def _extract_json(self, text: str) -> str:
        """Extract JSON from response, handling markdown code blocks."""
        json_text = text.strip()

        # Handle markdown code blocks
        if '```json' in json_text:
            match = re.search(r'```json\s*(.*?)\s*```', json_text, re.DOTALL)
            if match:
                json_text = match.group(1)
        elif '```' in json_text:
            match = re.search(r'```\s*(.*?)\s*```', json_text, re.DOTALL)
            if match:
                json_text = match.group(1)

        return json_text.strip()

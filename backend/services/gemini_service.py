"""Gemini AI service for transcription and intent detection."""
import google.generativeai as genai
from typing import Dict, Any, List, Union
import json
import re


class GeminiService:
    """Service for Gemini API integration."""

    def __init__(self, api_key: str):
        """Initialize Gemini service with API key."""
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel('gemini-2.5-flash-lite')

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
            response = self.model.generate_content(prompt)

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

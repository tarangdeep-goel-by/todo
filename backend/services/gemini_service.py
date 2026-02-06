"""Gemini AI service for transcription and intent detection."""
import google.generativeai as genai
from typing import Dict, Any
import json
import re


class GeminiService:
    """Service for Gemini API integration."""

    def __init__(self, api_key: str):
        """Initialize Gemini service with API key."""
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel('gemini-2.0-flash')

    async def refine_transcription(self, raw_text: str) -> str:
        """
        Clean up transcription errors.

        Args:
            raw_text: Raw transcribed text

        Returns:
            Cleaned transcription text
        """
        prompt = f"""You are a text cleanup assistant. Clean up and improve the following speech-to-text transcription.

Rules:
1. Fix obvious transcription errors
2. Add proper capitalization
3. Remove filler words (um, uh, like)
4. Keep the meaning exactly the same
5. Make it concise and clear
6. Return ONLY the cleaned text, no explanations

Raw transcription: "{raw_text}"

Cleaned text:"""

        try:
            response = self.model.generate_content(prompt)
            return response.text.strip()
        except Exception as e:
            print(f"Failed to refine transcription: {e}")
            return raw_text  # Fallback to original

    async def detect_intent(
        self,
        transcription: str,
        task_tree_context: str
    ) -> Dict[str, Any]:
        """
        Detect user intent and extract parameters.

        Args:
            transcription: User's voice command (cleaned)
            task_tree_context: String representation of task tree

        Returns:
            {
                "intent": "ADD|COMPLETE|DELETE|EDIT|MOVE|QUERY|UNKNOWN",
                "confidence": 0.0-1.0,
                "parameters": {...}
            }
        """
        prompt = f"""Current task tree:
{task_tree_context}

User said: "{transcription}"

Detect the user's intent. Available intents:
- ADD: Create new task (keywords: add, create, new, remember, note)
- COMPLETE: Mark task(s) as done (keywords: complete, done, finish, mark)
- DELETE: Remove/archive task(s) (keywords: delete, remove, archive, cancel)
- EDIT: Modify existing task properties (keywords: edit, change, update, rename, reschedule)
- MOVE: Move task to different parent (keywords: move, relocate, transfer, put under)
- QUERY: Search/list tasks (keywords: show, list, what, find, search)
- UNKNOWN: Unclear intent

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

Respond ONLY with valid JSON in this exact format:
{{
  "intent": "ADD|COMPLETE|DELETE|EDIT|MOVE|QUERY|UNKNOWN",
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
    "tags": ["tag1", "tag2"] or null,  // Extract relevant tags
    "estimatedHours": number or null  // Time estimate if mentioned

    // For COMPLETE/DELETE:
    "taskQuery": "search terms to find the task",
    "matchedTasks": ["task-id-1", "task-id-2"]

    // For EDIT:
    "taskQuery": "search terms to find the task",
    "changes": {{
      "title": "new title if mentioned",
      "dueDate": "ISO date if mentioned",
      "category": "work or personal if mentioned"
    }}

    // For MOVE:
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

Examples:
- "Add groceries to shopping list" → ADD with title="Groceries", description=null, category="personal"
- "Add urgent backend API task due tomorrow that should take 3 hours" → ADD with title="Backend API", description="Urgent task to complete the backend API implementation. Estimated 3 hours.", priority="high", dueDate="tomorrow", estimatedHours=3
- "I need to call the dentist to reschedule my appointment for next week because the current one conflicts with my meeting" → ADD with title="Reschedule dentist", description="Call the dentist to reschedule. Current appointment conflicts with a meeting. Move to next week.", dueDate="next week"
- "Add task due next monday" → ADD with dueDate="next monday"
- "Complete the backend API task" → COMPLETE with taskQuery="backend API"
- "Delete the meeting prep task" → DELETE with taskQuery="meeting prep"
- "Change doctor appointment to tomorrow" → EDIT with taskQuery="doctor appointment", changes.dueDate="tomorrow"
- "Move groceries task under shopping list" → MOVE with taskQuery="groceries", targetParentQuery="shopping list"
- "Move grocery shopping to the main level" → MOVE with taskQuery="grocery shopping", targetParentId=null, targetParentQuery=null
- "Move task to root" → MOVE with targetParentId=null, targetParentQuery=null
- "Move backend API to Project Alpha" → MOVE with taskQuery="backend API", targetParentQuery="Project Alpha"
- "Show my work tasks" → QUERY with filters.category="work"

NEW CATEGORY EXAMPLES:
- "Add practice violin" → ADD with needsNewBranch=true, suggestedBranchName="Hobbies", title="Practice violin"
- "Add schedule dentist appointment" → ADD with needsNewBranch=true, suggestedBranchName="Health", title="Schedule dentist appointment"
- "Add learn Spanish course" → ADD with needsNewBranch=true, suggestedBranchName="Learning", title="Learn Spanish course"
- "Add practice violin to Hobbies" → ADD with category="Hobbies", title="Practice violin", needsNewBranch=false (user explicitly creating category)
- "Add task to Music category" → ADD with category="Music", needsNewBranch=false (user explicitly specifying new category)
"""

        try:
            response = self.model.generate_content(prompt)

            if not response.text:
                raise ValueError("Empty response from Gemini")

            # Extract JSON from response (handle markdown code blocks)
            json_text = self._extract_json(response.text)
            return json.loads(json_text)

        except Exception as e:
            print(f"Failed to detect intent: {e}")
            # Return UNKNOWN intent on failure
            return {
                "intent": "UNKNOWN",
                "confidence": 0.0,
                "parameters": {}
            }

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

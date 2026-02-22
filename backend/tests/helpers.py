"""Test helper factories."""
import uuid
from typing import Optional
from services.task_service import TaskService


def make_task(**overrides) -> dict:
    """Return kwargs for TaskService.create_task with sensible defaults."""
    defaults = {
        "user_id": "test-user",
        "title": "Test Task",
        "category": "work",
        "transcription": "test task",
        "parent_id": None,
        "description": None,
        "due_date": None,
        "ai_placement": {"confidence": 0.9, "reasoning": "test"},
        "priority": None,
        "tags": None,
        "estimated_hours": None,
        "task_id": None,
    }
    defaults.update(overrides)
    return defaults


async def make_task_tree(task_service: TaskService, user_id: str = "test-user"):
    """Create categories + sample tasks. Returns dict of created tasks."""
    tasks = {}

    # Create category rows via service (generates proper UUIDs)
    await task_service.create_category(user_id, "work")
    await task_service.create_category(user_id, "personal")

    # Top-level tasks (parent_id=None)
    tasks["project_alpha"] = await task_service.create_task(
        user_id=user_id, title="Project Alpha", category="work",
        parent_id=None, transcription="project alpha",
        ai_placement={"confidence": 0.9, "reasoning": "work project"},
    )
    tasks["backend_api"] = await task_service.create_task(
        user_id=user_id, title="Backend API", category="work",
        parent_id=tasks["project_alpha"].id, transcription="backend api",
        ai_placement={"confidence": 0.9, "reasoning": "sub-task"},
    )
    tasks["groceries"] = await task_service.create_task(
        user_id=user_id, title="Groceries", category="personal",
        parent_id=None, transcription="groceries",
        ai_placement={"confidence": 0.9, "reasoning": "personal errand"},
    )

    return tasks

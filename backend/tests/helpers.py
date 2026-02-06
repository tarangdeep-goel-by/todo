"""Test helper factories."""
import uuid
from typing import Optional
from services.task_service import TaskService

# Stable UUIDs for root categories (deterministic for test assertions)
ROOT_WORK_ID = "00000000-0000-0000-0000-000000000001"
ROOT_PERSONAL_ID = "00000000-0000-0000-0000-000000000002"


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
    """Create root categories + sample children. Returns dict of created tasks."""
    tasks = {}

    # Root categories
    tasks["root_work"] = await task_service.create_task(
        user_id=user_id, title="Work", category="work",
        transcription="Work", task_id=ROOT_WORK_ID,
        ai_placement={"confidence": 1.0, "reasoning": "root"},
    )
    tasks["root_personal"] = await task_service.create_task(
        user_id=user_id, title="Personal", category="personal",
        transcription="Personal", task_id=ROOT_PERSONAL_ID,
        ai_placement={"confidence": 1.0, "reasoning": "root"},
    )

    # Children
    tasks["project_alpha"] = await task_service.create_task(
        user_id=user_id, title="Project Alpha", category="work",
        parent_id=ROOT_WORK_ID, transcription="project alpha",
        ai_placement={"confidence": 0.9, "reasoning": "work project"},
    )
    tasks["backend_api"] = await task_service.create_task(
        user_id=user_id, title="Backend API", category="work",
        parent_id=tasks["project_alpha"].id, transcription="backend api",
        ai_placement={"confidence": 0.9, "reasoning": "sub-task"},
    )
    tasks["groceries"] = await task_service.create_task(
        user_id=user_id, title="Groceries", category="personal",
        parent_id=ROOT_PERSONAL_ID, transcription="groceries",
        ai_placement={"confidence": 0.9, "reasoning": "personal errand"},
    )

    return tasks

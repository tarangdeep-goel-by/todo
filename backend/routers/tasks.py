"""Tasks API router."""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from database import get_db
from models.schemas import TaskResponse, CreateTaskRequest, UpdateTaskRequest
from services.task_service import TaskService
from models.task import Task

router = APIRouter(prefix="/tasks", tags=["tasks"])


def task_to_response(task: Task) -> TaskResponse:
    """Convert Task model to TaskResponse."""
    return TaskResponse(
        id=task.id,
        user_id=task.user_id,
        title=task.title,
        description=task.description,
        parent_id=task.parent_id,
        category=task.category,
        status=task.status,
        created_at=task.created_at,
        updated_at=task.updated_at,
        due_date=task.due_date,
        completed_at=task.completed_at,
        transcription=task.transcription,
        ai_placement=task.ai_placement_json,
        priority=task.priority,
        tags=task.tags,
        notes=task.notes,
        estimated_hours=task.estimated_hours
    )


@router.get("", response_model=List[TaskResponse])
async def get_tasks(
    user_id: str = Query(..., description="User ID"),
    category: Optional[str] = Query(None, description="Filter by category (work/personal)"),
    status: Optional[str] = Query(None, description="Filter by status (active/completed/archived)"),
    parent_id: Optional[str] = Query(None, description="Filter by parent ID"),
    db: AsyncSession = Depends(get_db)
) -> List[TaskResponse]:
    """Get tasks with optional filters."""
    task_service = TaskService(db)
    tasks = await task_service.get_tasks(
        user_id=user_id,
        category=category,
        status=status,
        parent_id=parent_id
    )

    return [task_to_response(t) for t in tasks]


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: str,
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Get a specific task by ID."""
    task_service = TaskService(db)
    task = await task_service.get_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task_to_response(task)


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(
    request: CreateTaskRequest,
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Create a new task."""
    task_service = TaskService(db)
    task = await task_service.create_task(
        user_id=request.user_id,
        title=request.title,
        description=request.description,
        category=request.category,
        parent_id=request.parent_id,
        due_date=request.due_date,
        transcription=request.transcription,
        priority=request.priority,
        tags=request.tags,
        notes=request.notes,
        estimated_hours=request.estimated_hours
    )

    return task_to_response(task)


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    request: UpdateTaskRequest,
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Update an existing task."""
    task_service = TaskService(db)

    # Build update dict from request
    updates = {}
    if request.title is not None:
        updates['title'] = request.title
    if request.description is not None:
        updates['description'] = request.description
    if request.parent_id is not None:
        updates['parent_id'] = request.parent_id
    if request.due_date is not None:
        updates['due_date'] = request.due_date
    if request.status is not None:
        updates['status'] = request.status.value
    if request.priority is not None:
        updates['priority'] = request.priority
    if request.tags is not None:
        updates['tags'] = request.tags
    if request.notes is not None:
        updates['notes'] = request.notes
    if request.estimated_hours is not None:
        updates['estimated_hours'] = request.estimated_hours

    task = await task_service.update_task(task_id, **updates)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task_to_response(task)


@router.put("/{task_id}/complete", response_model=TaskResponse)
async def complete_task(
    task_id: str,
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Mark task as completed."""
    task_service = TaskService(db)
    task = await task_service.complete_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task_to_response(task)


@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    user_id: str = Query(..., description="User ID for verification"),
    db: AsyncSession = Depends(get_db)
):
    """Archive task and all descendants."""
    task_service = TaskService(db)

    # Verify task exists and belongs to user
    task = await task_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Archive task and descendants
    count = await task_service.archive_task(task_id)

    return {
        "success": True,
        "message": f"Archived task and {count - 1} descendants",
        "archived_count": count
    }

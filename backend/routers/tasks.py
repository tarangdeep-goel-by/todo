"""Tasks API router."""
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime
from database import get_db
from auth import get_current_user
from models.schemas import TaskResponse, CreateTaskRequest, UpdateTaskRequest, TaskFilterParams, TaskListResponse, TaskStatsResponse, TaskSearchResult, TaskSearchResponse
from services.task_service import TaskService
from models.task import Task
from rate_limit import limiter
from audit import audit_log
from structured_logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/tasks", tags=["tasks"])


def task_to_response(task: Task) -> TaskResponse:
    """Convert Task model to TaskResponse."""
    return TaskResponse(
        id=str(task.id),
        user_id=task.user_id,
        title=task.title,
        description=task.description,
        parent_id=str(task.parent_id) if task.parent_id else None,
        category=task.category,
        category_id=str(task.category_id) if task.category_id else None,
        status=task.status,
        created_at=task.created_at,
        updated_at=task.updated_at,
        due_date=task.due_date,
        completed_at=task.completed_at,
        transcription=task.transcription,
        ai_placement=task.ai_placement_json,
        priority=task.priority,
        tags=task.tags,
        estimated_hours=task.estimated_hours
    )


@router.get("", response_model=TaskListResponse)
async def get_tasks(
    # Auth
    user_id: str = Depends(get_current_user),

    # Exact match filters
    category: Optional[str] = Query(None, description="Filter by category (comma-separated)"),
    priority: Optional[str] = Query(None, description="Filter by priority (high,medium,low)"),
    status: Optional[str] = Query(None, description="Filter by status (active,completed)"),
    parent_id: Optional[str] = Query(None, description="Filter by parent ID (UUID or 'null')"),
    tags: Optional[str] = Query(None, description="Filter by tags (comma-separated)"),

    # Range filters
    created_at_gte: Optional[datetime] = Query(None, description="Created after"),
    created_at_lte: Optional[datetime] = Query(None, description="Created before"),
    updated_at_gte: Optional[datetime] = Query(None, description="Updated after"),
    updated_at_lte: Optional[datetime] = Query(None, description="Updated before"),
    due_date_gte: Optional[datetime] = Query(None, description="Due after"),
    due_date_lte: Optional[datetime] = Query(None, description="Due before"),
    completed_at_gte: Optional[datetime] = Query(None, description="Completed after"),
    completed_at_lte: Optional[datetime] = Query(None, description="Completed before"),

    # Sorting
    sort: Optional[str] = Query(
        "status:asc,due_date:asc,priority:desc,created_at:desc",
        description="Multi-level sort: field:direction,field:direction"
    ),

    # Pagination
    limit: int = Query(50, ge=1, le=100, description="Results per page"),
    offset: int = Query(0, ge=0, description="Results to skip"),

    db: AsyncSession = Depends(get_db)
) -> TaskListResponse:
    """Get tasks with advanced filtering, sorting, and pagination."""

    # Build filter params
    filter_params = TaskFilterParams(
        user_id=user_id,
        category=category,
        priority=priority,
        status=status,
        parent_id=parent_id,
        tags=tags,
        created_at_gte=created_at_gte,
        created_at_lte=created_at_lte,
        updated_at_gte=updated_at_gte,
        updated_at_lte=updated_at_lte,
        due_date_gte=due_date_gte,
        due_date_lte=due_date_lte,
        completed_at_gte=completed_at_gte,
        completed_at_lte=completed_at_lte,
        sort=sort,
        limit=limit,
        offset=offset
    )

    # Execute query
    task_service = TaskService(db)
    tasks, total_count = await task_service.get_tasks_advanced(filter_params)

    # Build response
    logger.info("task.list", total_count=total_count, limit=limit, offset=offset)
    return TaskListResponse(
        tasks=[task_to_response(t) for t in tasks],
        total_count=total_count,
        limit=limit,
        offset=offset,
        has_more=(offset + len(tasks)) < total_count
    )


@router.get("/stats", response_model=TaskStatsResponse)
async def get_task_stats(
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> TaskStatsResponse:
    """Get aggregate task statistics for a user."""
    task_service = TaskService(db)
    stats = await task_service.get_task_stats(user_id)
    return TaskStatsResponse(**stats)


@router.get("/search", response_model=TaskSearchResponse)
@limiter.limit("30/minute")
async def search_tasks(
    request: Request,
    q: str = Query(..., min_length=1, max_length=500),
    user_id: str = Depends(get_current_user),
    limit: int = Query(10, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
) -> TaskSearchResponse:
    """Full-text search across tasks by title/description."""
    from config import get_settings
    from services.task_search_service import TaskSearchService
    from utils.fuzzy_matcher import FuzzyMatcher

    settings = get_settings()

    if settings.search_engine == "pg_native":
        search_service = TaskSearchService(db)
        results = await search_service.search(user_id, q, status_filter="active", limit=limit)
    else:
        task_service = TaskService(db)
        all_tasks = await task_service.get_tasks(user_id, status="active")
        results = FuzzyMatcher.rank_matches(q, all_tasks, threshold=60, limit=limit)

    search_results = [
        TaskSearchResult(task=task_to_response(task), score=float(score))
        for task, score in results
    ]
    logger.info("task.search", query=q, result_count=len(search_results))
    return TaskSearchResponse(
        results=search_results,
        query=q,
        total_count=len(search_results),
    )


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(
    task_id: str,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Get a specific task by ID."""
    task_service = TaskService(db)
    task = await task_service.get_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    logger.info("task.get", task_id=task_id)
    return task_to_response(task)


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(
    request: CreateTaskRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Create a new task."""
    task_service = TaskService(db)

    # Validate parent ownership
    if request.parent_id:
        parent = await task_service.get_task(request.parent_id)
        if not parent:
            raise HTTPException(status_code=404, detail="Parent task not found")
        if parent.user_id != user_id:
            raise HTTPException(status_code=403, detail="Not authorized to use this parent task")

    task = await task_service.create_task(
        user_id=user_id,
        title=request.title,
        description=request.description,
        category=request.category,
        category_id=request.category_id,
        parent_id=request.parent_id,
        due_date=request.due_date,
        transcription=request.transcription,
        priority=request.priority,
        tags=request.tags,
        estimated_hours=request.estimated_hours
    )

    logger.info("task.create", task_id=str(task.id), category=request.category)
    return task_to_response(task)


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(
    task_id: str,
    request: UpdateTaskRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Update an existing task."""
    task_service = TaskService(db)

    # Verify ownership
    task = await task_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    if task.user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Build update dict from request
    updates = {}
    if request.title is not None:
        updates['title'] = request.title
    if request.description is not None:
        updates['description'] = request.description
    if request.category is not None:
        updates['category'] = request.category
    if request.parent_id is not None:
        if request.parent_id:  # non-empty string = move under a parent
            parent = await task_service.get_task(request.parent_id)
            if not parent:
                raise HTTPException(status_code=404, detail="Parent task not found")
            if parent.user_id != user_id:
                raise HTTPException(status_code=403, detail="Not authorized to use this parent task")
        updates['parent_id'] = request.parent_id
    if request.due_date is not None:
        updates['due_date'] = request.due_date
    if request.status is not None:
        updates['status'] = request.status.value
    if request.priority is not None:
        updates['priority'] = request.priority
    if request.tags is not None:
        updates['tags'] = request.tags
    if request.estimated_hours is not None:
        updates['estimated_hours'] = request.estimated_hours

    old_status = (await task_service.get_task(task_id)).status
    task = await task_service.update_task(task_id, **updates)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if "status" in updates and updates["status"] != old_status:
        audit_log("task.status_changed", user_id, task_id,
                  old_status=old_status, new_status=updates["status"])

    logger.info("task.update", task_id=task_id, fields=list(updates.keys()))
    return task_to_response(task)


@router.put("/{task_id}/complete", response_model=TaskResponse)
async def complete_task(
    task_id: str,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
) -> TaskResponse:
    """Complete task. If it has active children, completes them too."""
    task_service = TaskService(db)

    task = await task_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Check for active children
    children = await task_service.get_tasks(task.user_id, parent_id=task_id)
    active_children = [c for c in children if c.status == "active"]

    if active_children:
        await task_service.complete_task_with_children(task_id)
    else:
        await task_service.complete_task(task_id)

    # Re-fetch to get updated state
    task = await task_service.get_task(task_id)
    logger.info("task.complete", task_id=task_id)
    return task_to_response(task)


@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Hard delete task and all descendants from DB."""
    task_service = TaskService(db)

    # Verify task exists and belongs to user
    task = await task_service.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if task.user_id != user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    count = await task_service.delete_task_with_children(task_id)
    audit_log("task.deleted", user_id, task_id, deleted_count=count)

    logger.info("task.delete", task_id=task_id, deleted_count=count)
    return {
        "success": True,
        "message": f"Deleted task and {count - 1} sub-tasks",
        "deleted_count": count
    }

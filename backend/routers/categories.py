"""Categories API router."""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from database import get_db
from auth import get_current_user
from models.schemas import CategoryResponse, CreateCategoryRequest
from services.task_service import TaskService
from audit import audit_log
from rate_limit import limiter
from structured_logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("", response_model=List[CategoryResponse])
async def get_categories(
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> List[CategoryResponse]:
    """List categories ordered by position."""
    task_service = TaskService(db)
    categories = await task_service.get_categories_from_db(user_id)
    logger.info("category.list", count=len(categories))
    return [CategoryResponse.model_validate(c) for c in categories]


@router.post("", response_model=CategoryResponse, status_code=201)
@limiter.limit("10/minute")
async def create_category(
    http_request: Request,
    request: CreateCategoryRequest,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CategoryResponse:
    """Create a new category (max 5, no duplicates)."""
    task_service = TaskService(db)
    try:
        category = await task_service.create_category(user_id, request.name)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    logger.info("category.create", name=request.name)
    return CategoryResponse.model_validate(category)


@router.delete("/{category_id}")
@limiter.limit("10/minute")
async def delete_category(
    request: Request,
    category_id: str,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a category record."""
    task_service = TaskService(db)
    deleted = await task_service.delete_category(category_id, user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Category not found")
    audit_log("category.deleted", user_id, category_id)
    logger.info("category.delete", category_id=category_id)
    return {"success": True, "message": "Category deleted"}

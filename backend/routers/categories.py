"""Categories API router."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from database import get_db
from auth import get_current_user
from models.schemas import CategoryResponse, CreateCategoryRequest
from services.task_service import TaskService

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("", response_model=List[CategoryResponse])
async def get_categories(
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> List[CategoryResponse]:
    """List categories ordered by position."""
    task_service = TaskService(db)
    categories = await task_service.get_categories_from_db(user_id)
    return [CategoryResponse.model_validate(c) for c in categories]


@router.post("", response_model=CategoryResponse, status_code=201)
async def create_category(
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
    return CategoryResponse.model_validate(category)


@router.delete("/{category_id}")
async def delete_category(
    category_id: str,
    user_id: str = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a category record."""
    task_service = TaskService(db)
    deleted = await task_service.delete_category(category_id, user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Category not found")
    return {"success": True, "message": "Category deleted"}

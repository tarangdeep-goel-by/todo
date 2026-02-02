"""Pydantic schemas for request/response validation."""
from pydantic import BaseModel, Field, field_validator
from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum


class TaskStatus(str, Enum):
    """Task status enum."""
    ACTIVE = "active"
    COMPLETED = "completed"
    ARCHIVED = "archived"


class AgentProcessRequest(BaseModel):
    """Request schema for agent processing."""
    transcription: str = Field(..., min_length=1, max_length=1000)
    user_id: str = Field(..., min_length=1)


class CreateTaskRequest(BaseModel):
    """Request schema for creating a task."""
    user_id: str
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = None
    category: str  # Any category: work, personal, fitness, etc.
    parent_id: Optional[str] = None
    due_date: Optional[datetime] = None
    transcription: str

    # New optional fields
    priority: Optional[str] = None  # high/medium/low
    tags: Optional[List[str]] = None
    notes: Optional[str] = None
    estimated_hours: Optional[float] = None


class UpdateTaskRequest(BaseModel):
    """Request schema for updating a task."""
    title: Optional[str] = Field(None, min_length=1, max_length=500)
    description: Optional[str] = None
    parent_id: Optional[str] = None  # Move to different parent
    due_date: Optional[datetime] = None
    status: Optional[TaskStatus] = None
    priority: Optional[str] = None
    tags: Optional[List[str]] = None
    notes: Optional[str] = None
    estimated_hours: Optional[float] = None


class AIPlacement(BaseModel):
    """AI placement metadata."""
    suggested_parent: Optional[str] = None
    confidence: float = Field(0.9, ge=0.0, le=1.0)
    reasoning: str = "Manual creation"


class TaskResponse(BaseModel):
    """Response schema for task."""
    id: str
    user_id: str
    title: str
    description: Optional[str]
    parent_id: Optional[str]
    category: str  # Any category string
    status: TaskStatus
    created_at: datetime
    updated_at: datetime
    due_date: Optional[datetime]
    completed_at: Optional[datetime]
    transcription: str
    ai_placement: AIPlacement

    # New optional fields
    priority: Optional[str] = None
    tags: Optional[List[str]] = None
    notes: Optional[str] = None
    estimated_hours: Optional[float] = None

    class Config:
        from_attributes = True


class AgentResponse(BaseModel):
    """Response schema for agent processing."""
    success: bool
    message: str
    type: str  # "confirmation", "question", "error"
    data: Optional[Dict[str, Any]] = None


class TaskTreeNode(BaseModel):
    """Task tree node for hierarchical response."""
    id: str
    title: str
    status: TaskStatus
    children: List['TaskTreeNode'] = []


# Enable forward reference
TaskTreeNode.model_rebuild()


class SortField(str, Enum):
    """Valid sort fields."""
    CATEGORY = "category"
    PRIORITY = "priority"
    STATUS = "status"
    CREATED_AT = "created_at"
    UPDATED_AT = "updated_at"
    DUE_DATE = "due_date"
    COMPLETED_AT = "completed_at"
    TITLE = "title"


class TaskFilterParams(BaseModel):
    """Filter parameters for task queries."""

    # Required
    user_id: str

    # Exact match filters (single or multi-value)
    category: Optional[str] = None
    priority: Optional[str] = None
    status: Optional[str] = None
    parent_id: Optional[str] = None
    tags: Optional[str] = None

    # Range filters
    created_at_gte: Optional[datetime] = None
    created_at_lte: Optional[datetime] = None
    updated_at_gte: Optional[datetime] = None
    updated_at_lte: Optional[datetime] = None
    due_date_gte: Optional[datetime] = None
    due_date_lte: Optional[datetime] = None
    completed_at_gte: Optional[datetime] = None
    completed_at_lte: Optional[datetime] = None

    # Sorting
    sort: Optional[str] = "priority:desc,due_date:asc,created_at:desc"

    # Pagination
    limit: int = Field(50, ge=1, le=100)
    offset: int = Field(0, ge=0)

    @field_validator('sort')
    @classmethod
    def validate_sort(cls, v: Optional[str]) -> Optional[str]:
        """Validate sort parameter format."""
        if not v:
            return v

        for sort_item in v.split(','):
            parts = sort_item.strip().split(':')
            if len(parts) != 2:
                raise ValueError(f"Invalid sort format: {sort_item}")

            field, direction = parts
            if field not in [f.value for f in SortField]:
                raise ValueError(f"Invalid sort field: {field}")
            if direction not in ['asc', 'desc']:
                raise ValueError(f"Invalid sort direction: {direction}")

        return v

    def parse_multi_value(self, value: Optional[str]) -> Optional[List[str]]:
        """Parse comma-separated values into list."""
        if not value:
            return None
        return [v.strip() for v in value.split(',')]

    def parse_sort(self) -> List[tuple[str, str]]:
        """Parse sort string into list of (field, direction) tuples."""
        if not self.sort:
            return []

        result = []
        for sort_item in self.sort.split(','):
            field, direction = sort_item.strip().split(':')
            result.append((field, direction))
        return result


class TaskListResponse(BaseModel):
    """Response for paginated task list."""
    tasks: List[TaskResponse]
    total_count: int
    limit: int
    offset: int
    has_more: bool

"""Pydantic schemas for request/response validation."""
from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum


class TaskStatus(str, Enum):
    """Task status enum — only real persisted states."""
    ACTIVE = "active"
    COMPLETED = "completed"


class WriteTaskStatus(str, Enum):
    """Writable task statuses."""
    ACTIVE = "active"
    COMPLETED = "completed"


class BrainDumpRequest(BaseModel):
    """Request schema for brain dump voice processing."""
    transcription: str = Field(..., min_length=1, max_length=5000)
    user_id: str = Field(..., min_length=1)
    category: Optional[str] = None  # Pre-fill category for all tasks
    parent_id: Optional[str] = None  # Pre-fill parent for subtask mode


class BrainDumpTaskProposal(BaseModel):
    """A single proposed task from brain dump."""
    id: str  # Client-generated temp ID
    action: str = "add"  # "add", "complete", "edit", "delete", or "move"
    content: str
    description: Optional[str] = None
    category: str
    due_date: Optional[datetime] = None
    priority: Optional[str] = None
    parent_id: Optional[str] = None
    labels: List[str] = []
    changes: Optional[Dict[str, Any]] = None  # For edit actions (e.g. {"priority": "low"})
    matched_task_id: Optional[str] = None  # Resolved existing task ID for complete/edit/delete/move
    target_parent_id: Optional[str] = None  # MOVE: resolved destination parent UUID
    target_content: Optional[str] = None  # MOVE: display name of target parent
    confidence: Optional[float] = None  # Gemini's confidence in this proposal
    tags: Optional[List[str]] = None
    estimated_hours: Optional[float] = None
    alternate_matches: Optional[List[Dict[str, str]]] = None  # [{id, title, category}, ...]


class BrainDumpResponse(BaseModel):
    """Response schema for brain dump processing."""
    success: bool
    tasks: List[BrainDumpTaskProposal] = []
    transcription: str  # Echo back for display
    message: Optional[str] = None


class BrainDumpSubmitRequest(BaseModel):
    """Request schema for committing reviewed brain dump tasks."""
    user_id: str = Field(..., min_length=1)
    tasks: List[BrainDumpTaskProposal]


class BrainDumpSubmitResponse(BaseModel):
    """Response schema for brain dump submission."""
    success: bool
    created_count: int
    created_task_ids: List[str] = []
    message: str


class CreateTaskRequest(BaseModel):
    """Request schema for creating a task."""
    user_id: str
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = None
    category: str  # Any category: work, personal, fitness, etc.
    category_id: Optional[str] = None
    parent_id: Optional[str] = None
    due_date: Optional[datetime] = None
    transcription: str

    # New optional fields
    priority: Optional[str] = None  # high/medium/low
    tags: Optional[List[str]] = None
    estimated_hours: Optional[float] = None


class UpdateTaskRequest(BaseModel):
    """Request schema for updating a task."""
    title: Optional[str] = Field(None, min_length=1, max_length=500)
    description: Optional[str] = None
    category: Optional[str] = None  # Move to different domain
    parent_id: Optional[str] = None  # Move to different parent
    due_date: Optional[datetime] = None
    status: Optional[WriteTaskStatus] = None
    priority: Optional[str] = None
    tags: Optional[List[str]] = None
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
    category_id: Optional[str] = None
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
    estimated_hours: Optional[float] = None

    model_config = ConfigDict(from_attributes=True)


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
    sort: Optional[str] = "status:asc,due_date:asc,priority:desc,created_at:desc"

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
        """Parse sort string into list of (field, direction) tuples.
        Default: active tasks first, then newest."""
        if not self.sort:
            return [("status", "asc"), ("due_date", "asc"), ("priority", "desc"), ("created_at", "desc")]

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


class CategoryResponse(BaseModel):
    """Response schema for category."""
    id: str
    user_id: str
    name: str
    position: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class CreateCategoryRequest(BaseModel):
    """Request schema for creating a category."""
    user_id: str = Field(..., min_length=1)
    name: str = Field(..., min_length=1, max_length=50)


class CategoryStats(BaseModel):
    """Stats for a single category."""
    category_id: Optional[str]
    category_name: str
    total: int
    active: int
    completed: int
    overdue: int


class TaskStatsResponse(BaseModel):
    """Response schema for task statistics."""
    total_tasks: int
    by_status: Dict[str, int]
    by_priority: Dict[str, int]
    by_category: List[CategoryStats]
    due_soon_count: int

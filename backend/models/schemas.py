"""Pydantic schemas for request/response validation."""
import re
from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Optional, Dict, Any, List
from datetime import datetime
from enum import Enum


class TaskStatus(str, Enum):
    """Task status enum — only real persisted states."""
    ACTIVE = "active"
    COMPLETED = "completed"
    ARCHIVED = "archived"


class WriteTaskStatus(str, Enum):
    """Writable task statuses."""
    ACTIVE = "active"
    COMPLETED = "completed"


class PriorityLevel(str, Enum):
    """Valid priority levels."""
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


def _strip_html_tags(v: str | None) -> str | None:
    """Strip HTML tags from text to prevent stored XSS."""
    if v is None:
        return v
    return re.sub(r'<[^>]+>', '', v)


class BrainDumpRequest(BaseModel):
    """Request schema for brain dump voice processing."""
    transcription: str = Field(..., min_length=1, max_length=5000)
    category: Optional[str] = Field(None, max_length=50)
    parent_id: Optional[str] = Field(None, max_length=36)


class BrainDumpTaskProposal(BaseModel):
    """A single proposed task from brain dump."""
    id: str  # Client-generated temp ID
    action: str = "add"  # "add", "complete", "edit", "delete", or "breakdown"
    content: str = Field(..., max_length=500)
    description: Optional[str] = Field(None, max_length=5000)
    category: str = Field(..., max_length=50)
    due_date: Optional[datetime] = None
    priority: Optional[str] = None  # Gemini output — validated downstream
    parent_id: Optional[str] = None
    labels: List[str] = []
    changes: Optional[Dict[str, Any]] = None
    matched_task_id: Optional[str] = None
    confidence: Optional[float] = Field(None, ge=0.0, le=1.0)
    tags: Optional[List[str]] = Field(None, max_length=20)
    estimated_hours: Optional[float] = Field(None, ge=0.0, le=999.9)
    alternate_matches: Optional[List[Dict[str, str]]] = None
    match_explanation: Optional[str] = Field(None, max_length=500)

    @field_validator('tags')
    @classmethod
    def validate_tags(cls, v):
        if v is None:
            return v
        return [tag.strip()[:50] for tag in v[:20] if tag.strip()]


class BrainDumpResponse(BaseModel):
    """Response schema for brain dump processing."""
    success: bool
    tasks: List[BrainDumpTaskProposal] = []
    transcription: str  # Echo back for display
    message: Optional[str] = None


class BrainDumpSubmitRequest(BaseModel):
    """Request schema for committing reviewed brain dump tasks."""
    tasks: List[BrainDumpTaskProposal] = Field(..., max_length=50)


class BrainDumpSubmitResponse(BaseModel):
    """Response schema for brain dump submission."""
    success: bool
    created_count: int
    created_task_ids: List[str] = []
    message: str
    failed_reason: Optional[str] = None


class CreateTaskRequest(BaseModel):
    """Request schema for creating a task."""
    task_id: Optional[str] = Field(None, description="Client-generated UUID; server uses it as PK if provided")
    title: str = Field(..., min_length=1, max_length=500)
    description: Optional[str] = Field(None, max_length=5000)
    category: str = Field(..., max_length=50)
    category_id: Optional[str] = None
    parent_id: Optional[str] = None
    due_date: Optional[datetime] = None
    transcription: str = Field(..., max_length=5000)
    priority: Optional[PriorityLevel] = None
    tags: Optional[List[str]] = Field(None, max_length=20)
    estimated_hours: Optional[float] = Field(None, ge=0.0, le=999.9)

    _sanitize_title = field_validator('title')(lambda cls, v: _strip_html_tags(v))
    _sanitize_desc = field_validator('description')(lambda cls, v: _strip_html_tags(v))

    @field_validator('tags')
    @classmethod
    def validate_tags(cls, v):
        if v is None:
            return v
        return [tag.strip()[:50] for tag in v[:20] if tag.strip()]


class UpdateTaskRequest(BaseModel):
    """Request schema for updating a task."""
    title: Optional[str] = Field(None, min_length=1, max_length=500)
    description: Optional[str] = Field(None, max_length=5000)
    category: Optional[str] = Field(None, max_length=50)
    parent_id: Optional[str] = None
    due_date: Optional[datetime] = None
    status: Optional[WriteTaskStatus] = None
    priority: Optional[PriorityLevel] = None
    tags: Optional[List[str]] = Field(None, max_length=20)
    estimated_hours: Optional[float] = Field(None, ge=0.0, le=999.9)

    _sanitize_title = field_validator('title')(lambda cls, v: _strip_html_tags(v))
    _sanitize_desc = field_validator('description')(lambda cls, v: _strip_html_tags(v))

    @field_validator('tags')
    @classmethod
    def validate_tags(cls, v):
        if v is None:
            return v
        return [tag.strip()[:50] for tag in v[:20] if tag.strip()]


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
    category: str
    category_id: Optional[str] = None
    status: TaskStatus
    created_at: datetime
    updated_at: datetime
    due_date: Optional[datetime]
    completed_at: Optional[datetime]
    archived_at: Optional[datetime] = None
    transcription: str
    ai_placement: AIPlacement
    priority: Optional[str] = None
    tags: Optional[List[str]] = None
    estimated_hours: Optional[float] = None

    model_config = ConfigDict(from_attributes=True)


class TaskSearchResult(BaseModel):
    """A single search result with score."""
    task: TaskResponse
    score: float


class TaskSearchResponse(BaseModel):
    """Response for task search."""
    results: List[TaskSearchResult]
    query: str
    total_count: int


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
    category: Optional[str] = Field(None, max_length=200)
    priority: Optional[str] = Field(None, max_length=50)
    status: Optional[str] = Field(None, max_length=50)
    parent_id: Optional[str] = Field(None, max_length=36)
    tags: Optional[str] = Field(None, max_length=500)

    # Range filters
    created_at_gte: Optional[datetime] = None
    created_at_lte: Optional[datetime] = None
    updated_at_gte: Optional[datetime] = None
    updated_at_lte: Optional[datetime] = None
    due_date_gte: Optional[datetime] = None
    due_date_lte: Optional[datetime] = None
    completed_at_gte: Optional[datetime] = None
    completed_at_lte: Optional[datetime] = None

    # Archive filter
    include_archived: bool = False

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


class CategoryStatsEntry(BaseModel):
    """Per-category task statistics."""
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
    by_category: List[CategoryStatsEntry]
    due_soon_count: int


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
    name: str = Field(..., min_length=1, max_length=50)


class BulkAction(str, Enum):
    """Supported bulk actions."""
    COMPLETE = "complete"
    ARCHIVE = "archive"


class BulkActionRequest(BaseModel):
    """Request for bulk task operations."""
    task_ids: List[str] = Field(..., min_length=1, max_length=50)
    action: BulkAction


class BulkActionResponse(BaseModel):
    """Response for bulk task operations."""
    success: bool
    affected_count: int
    errors: List[str] = []

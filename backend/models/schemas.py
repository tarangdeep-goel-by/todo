"""Pydantic schemas for request/response validation."""
from pydantic import BaseModel, Field
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
    suggested_parent: Optional[str]
    confidence: float = Field(..., ge=0.0, le=1.0)
    reasoning: str


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

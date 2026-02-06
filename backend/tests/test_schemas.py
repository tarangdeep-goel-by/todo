"""Tests for Pydantic schemas — 8 tests."""
import pytest
from pydantic import ValidationError
from models.schemas import AgentResolveRequest, TaskFilterParams


# ──────────── AgentResolveRequest ────────────

class TestAgentResolveRequest:
    def test_valid_request(self):
        req = AgentResolveRequest(
            user_id="u1", action="complete", selected_task_id="t1",
            data={"key": "val"},
        )
        assert req.user_id == "u1"
        assert req.action == "complete"
        assert req.selected_task_id == "t1"

    def test_action_required(self):
        with pytest.raises(ValidationError):
            AgentResolveRequest(user_id="u1")

    def test_optional_fields_default_none(self):
        req = AgentResolveRequest(user_id="u1", action="delete")
        assert req.selected_task_id is None
        assert req.data is None


# ──────────── TaskFilterParams ────────────

class TestTaskFilterParams:
    def test_valid_sort(self):
        p = TaskFilterParams(user_id="u1", sort="category:asc,priority:desc")
        assert p.sort == "category:asc,priority:desc"

    def test_invalid_sort_format(self):
        with pytest.raises(ValidationError):
            TaskFilterParams(user_id="u1", sort="bad_format")

    def test_invalid_sort_field(self):
        with pytest.raises(ValidationError):
            TaskFilterParams(user_id="u1", sort="nonexistent:asc")

    def test_invalid_sort_direction(self):
        with pytest.raises(ValidationError):
            TaskFilterParams(user_id="u1", sort="title:sideways")

    def test_parse_multi_value(self):
        p = TaskFilterParams(user_id="u1", category="work,personal")
        result = p.parse_multi_value(p.category)
        assert result == ["work", "personal"]

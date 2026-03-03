"""Tests for Pydantic schemas — 5 tests."""
import pytest
from pydantic import ValidationError
from models.schemas import TaskFilterParams


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

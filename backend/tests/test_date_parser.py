"""Tests for parse_flexible_date — 10 tests."""
import pytest
from datetime import datetime, timezone, timedelta
from utils.date_parser import parse_flexible_date


class TestParseFlexibleDate:
    def test_today(self):
        result = parse_flexible_date("today")
        assert result is not None
        assert result.date() == datetime.now(timezone.utc).date()
        assert result.hour == 9

    def test_tomorrow(self):
        result = parse_flexible_date("tomorrow")
        expected_date = (datetime.now(timezone.utc) + timedelta(days=1)).date()
        assert result is not None
        assert result.date() == expected_date
        assert result.hour == 9

    def test_next_monday(self):
        result = parse_flexible_date("next monday")
        assert result is not None
        assert result.weekday() == 0  # Monday
        assert result.date() > datetime.now(timezone.utc).date()

    def test_next_friday(self):
        result = parse_flexible_date("next friday")
        assert result is not None
        assert result.weekday() == 4  # Friday

    def test_next_sunday(self):
        result = parse_flexible_date("next sunday")
        assert result is not None
        assert result.weekday() == 6  # Sunday

    def test_iso_date(self):
        result = parse_flexible_date("2025-06-15")
        assert result is not None
        assert result.year == 2025
        assert result.month == 6
        assert result.day == 15

    def test_iso_datetime_with_tz(self):
        result = parse_flexible_date("2025-06-15T14:30:00+00:00")
        assert result is not None
        assert result.tzinfo is not None
        assert result.hour == 14

    def test_none_input(self):
        assert parse_flexible_date(None) is None

    def test_empty_string(self):
        assert parse_flexible_date("") is None

    def test_garbage_input(self):
        assert parse_flexible_date("not a date at all zzz") is None

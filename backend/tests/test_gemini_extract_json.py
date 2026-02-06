"""Tests for GeminiService._extract_json — 6 tests."""
import pytest
import os

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://todo:todo123@postgres:5432/todo_test")
os.environ.setdefault("GEMINI_API_KEY", "test-key")

from services.gemini_service import GeminiService


@pytest.fixture
def gemini():
    """GeminiService instance (we only test _extract_json, no API calls)."""
    # Patch out the genai.configure call
    import unittest.mock as mock
    with mock.patch("google.generativeai.configure"), \
         mock.patch("google.generativeai.GenerativeModel"):
        return GeminiService("fake-key")


class TestExtractJson:
    def test_plain_json(self, gemini):
        text = '{"intent": "ADD", "confidence": 0.9}'
        assert gemini._extract_json(text) == '{"intent": "ADD", "confidence": 0.9}'

    def test_markdown_json_block(self, gemini):
        text = '```json\n{"intent": "ADD"}\n```'
        assert gemini._extract_json(text) == '{"intent": "ADD"}'

    def test_plain_code_block(self, gemini):
        text = '```\n{"intent": "DELETE"}\n```'
        assert gemini._extract_json(text) == '{"intent": "DELETE"}'

    def test_whitespace_around(self, gemini):
        text = '  \n  {"ok": true}  \n  '
        assert gemini._extract_json(text) == '{"ok": true}'

    def test_no_code_block_with_surrounding_text(self, gemini):
        """When there's no code block, return stripped text as-is."""
        text = 'Here is the result: {"intent": "QUERY"}'
        result = gemini._extract_json(text)
        assert '{"intent": "QUERY"}' in result

    def test_nested_json(self, gemini):
        text = '```json\n{"params": {"title": "test", "nested": {"a": 1}}}\n```'
        result = gemini._extract_json(text)
        assert '"nested"' in result
        assert '"a": 1' in result

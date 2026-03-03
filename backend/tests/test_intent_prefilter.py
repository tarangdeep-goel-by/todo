"""Tests for intent pre-filter (gibberish detection)."""
import pytest
from services.intent_prefilter import prefilter, _is_gibberish


class TestGibberishDetection:
    def test_gibberish_low_vowels(self):
        # Two gibberish words triggers detection (single gibberish word no longer does,
        # to avoid false positives on technical terms like "GraphQL")
        result = prefilter("asdfghjkl qwrtzp garble")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"
        assert result[0]["confidence"] <= 0.2

    def test_gibberish_consonant_clusters(self):
        result = prefilter("brrrghhh tsskfff xyzplm")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"

    def test_normal_text_not_gibberish(self):
        assert not _is_gibberish("add a new task called groceries")

    def test_short_text_not_gibberish(self):
        assert not _is_gibberish("hi")

    def test_empty_returns_unknown(self):
        result = prefilter("")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"

    def test_single_word_not_gibberish(self):
        """Single valid word like 'groceries' should NOT be flagged."""
        result = prefilter("groceries")
        assert result is None  # Defers to LLM


class TestPassthrough:
    def test_add_command(self):
        result = prefilter("add a task called groceries")
        assert result is None

    def test_complete_command(self):
        result = prefilter("complete the backend API task")
        assert result is None

    def test_delete_command(self):
        result = prefilter("delete the social media campaign")
        assert result is None

    def test_move_command(self):
        result = prefilter("move groceries under shopping list")
        assert result is None

    def test_query_passes_to_llm(self):
        """Query-like text should pass through to LLM (no pre-filter catch)."""
        result = prefilter("show me all career tasks")
        assert result is None

    def test_list_passes_to_llm(self):
        result = prefilter("what tasks are completed")
        assert result is None

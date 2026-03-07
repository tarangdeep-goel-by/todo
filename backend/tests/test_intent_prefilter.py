"""Tests for intent pre-filter (gibberish detection)."""
import pytest
from services.intent_prefilter import prefilter, _is_gibberish, _is_common_cluster


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


class TestPrefilterEdgeCases:
    """Edge cases for gibberish detection."""

    def test_all_consonants_is_gibberish(self):
        """Pure consonant string has vowel ratio 0 -> gibberish."""
        result = prefilter("bcdfgh jklmnp")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"

    def test_two_gibberish_words(self):
        """Two words with 5+ alpha and <0.15 vowel ratio -> gibberish."""
        result = prefilter("bcdfghj klmnpqr hello")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"

    def test_one_gibberish_word_not_enough(self):
        """Single gibberish word with no suspicious clusters -> not gibberish."""
        result = prefilter("bcdfghj hello world")
        assert result is None

    def test_common_cluster_whitelist(self):
        """_is_common_cluster recognises known English patterns and rejects unknown ones."""
        assert _is_common_cluster("ngth") is True
        assert _is_common_cluster("ghts") is True
        assert _is_common_cluster("str") is True
        assert _is_common_cluster("zzxx") is False

    def test_thoughtful_not_gibberish(self):
        """'thoughtful' has common cluster 'ght' and enough vowels -> not gibberish."""
        assert not _is_gibberish("thoughtful")

    def test_unicode_emoji_passes(self):
        """Emoji prefix should not trigger gibberish."""
        result = prefilter("\U0001f3af buy groceries")
        assert result is None

    def test_very_short_not_gibberish(self):
        """Text with < 3 alpha chars is too short to judge."""
        result = prefilter("ab")
        assert result is None

    def test_empty_string_returns_unknown(self):
        """Empty string returns UNKNOWN list (not None)."""
        result = prefilter("")
        assert result is not None
        assert isinstance(result, list)
        assert result[0]["intent"] == "UNKNOWN"

    def test_numbers_only(self):
        """Digits-only text has < 3 alpha chars -> passes."""
        result = prefilter("12345 67890")
        assert result is None

    def test_suspicious_clusters_threshold(self):
        """Two words each with 4+ non-common consonant clusters -> gibberish."""
        result = prefilter("xzpqwl bvnkfl hello")
        assert result is not None
        assert result[0]["intent"] == "UNKNOWN"

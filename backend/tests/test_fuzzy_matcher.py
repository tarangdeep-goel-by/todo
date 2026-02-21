"""Tests for FuzzyMatcher — 12 tests."""
import pytest
from utils.fuzzy_matcher import FuzzyMatcher
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class FakeTask:
    """Minimal task-like object for matcher tests."""
    id: str = "t1"
    title: str = "Test Task"
    description: Optional[str] = None
    category: str = "work"


# ──────────── score_task_match ────────────

class TestScoreTaskMatch:
    def test_exact_match(self):
        score = FuzzyMatcher.score_task_match("Backend API", "Backend API")
        assert score == 100

    def test_partial_match(self):
        score = FuzzyMatcher.score_task_match("backend", "Backend API")
        assert score > 60

    def test_unrelated(self):
        score = FuzzyMatcher.score_task_match("xylophone", "Backend API")
        assert score < 50

    def test_weighted_title_desc(self):
        """With description, score is weighted 70/30."""
        score = FuzzyMatcher.score_task_match(
            "api", "Backend API", "Build the REST API"
        )
        assert score > 70

    def test_title_only_no_weight(self):
        """Without description, raw title score is used."""
        score_no_extras = FuzzyMatcher.score_task_match("Backend API", "Backend API")
        score_with_desc = FuzzyMatcher.score_task_match(
            "Backend API", "Backend API", "some desc"
        )
        # Title-only should be 100, weighted should be <= 100
        assert score_no_extras == 100
        assert score_with_desc <= 100

    def test_empty_query(self):
        score = FuzzyMatcher.score_task_match("", "Backend API")
        assert isinstance(score, int)

    def test_threshold_parameter_does_not_affect_score(self):
        """threshold param is passed but doesn't change the score calculation."""
        s1 = FuzzyMatcher.score_task_match("api", "Backend API", threshold=50)
        s2 = FuzzyMatcher.score_task_match("api", "Backend API", threshold=90)
        assert s1 == s2


# ──────────── rank_matches ────────────

class TestRankMatches:
    def _make_tasks(self):
        return [
            FakeTask(id="1", title="Backend API", description="REST endpoints"),
            FakeTask(id="2", title="Frontend UI", description="React dashboard"),
            FakeTask(id="3", title="API Documentation", description="Swagger docs"),
        ]

    def test_sorted_descending(self):
        tasks = self._make_tasks()
        results = FuzzyMatcher.rank_matches("api", tasks, threshold=50)
        scores = [s for _, s in results]
        assert scores == sorted(scores, reverse=True)

    def test_respects_threshold(self):
        tasks = self._make_tasks()
        results = FuzzyMatcher.rank_matches("api", tasks, threshold=90)
        for _, score in results:
            assert score >= 90

    def test_respects_limit(self):
        tasks = self._make_tasks()
        results = FuzzyMatcher.rank_matches("api", tasks, threshold=30, limit=1)
        assert len(results) <= 1

    def test_empty_list(self):
        results = FuzzyMatcher.rank_matches("api", [], threshold=50)
        assert results == []

    def test_returns_task_and_score_tuples(self):
        tasks = self._make_tasks()
        results = FuzzyMatcher.rank_matches("backend", tasks, threshold=50)
        for task, score in results:
            assert hasattr(task, "title")
            assert isinstance(score, int)

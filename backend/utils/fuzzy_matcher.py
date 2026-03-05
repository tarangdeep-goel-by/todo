from typing import List, Tuple
from rapidfuzz import fuzz
from structured_logging import get_logger

logger = get_logger(__name__)


class FuzzyMatcher:
    """Fuzzy matching utility for task search."""

    @staticmethod
    def score_task_match(query: str, task_title: str, task_description: str = "",
                         threshold: int = 60) -> int:
        """Calculate weighted fuzzy match score.

        Uses max of token_set_ratio (word-order independent) and partial_ratio
        (substring matching) to handle cases like "SafeDrop" vs "Safe drop".
        """
        query_lower = query.lower()
        title_lower = task_title.lower()

        # Primary: token_set_ratio (word order independent)
        token_score = fuzz.token_set_ratio(query_lower, title_lower)
        # Secondary: partial_ratio (substring/character matching)
        partial_score = fuzz.partial_ratio(query_lower, title_lower)
        # Tertiary: normalized query without spaces vs title without spaces
        # Catches "SafeDrop" vs "Safe drop"
        stripped_score = fuzz.ratio(
            query_lower.replace(" ", ""),
            title_lower.replace(" ", ""),
        )
        title_score = max(token_score, partial_score, stripped_score)

        # If no description, title score stands on its own
        if not task_description:
            return int(title_score)

        # Weighted: title 70%, description 30%
        desc_score = fuzz.token_set_ratio(query_lower, task_description.lower())
        weighted = title_score * 0.7 + desc_score * 0.3

        return int(weighted)

    @staticmethod
    def rank_matches(query: str, tasks: List, threshold: int = 60,
                     limit: int = 5) -> List[Tuple[object, int]]:
        """Rank tasks by fuzzy score."""
        scored = []
        logger.debug("task.search.fuzzy", query=query, task_count=len(tasks), threshold=threshold)
        for task in tasks:
            score = FuzzyMatcher.score_task_match(
                query, task.title, task.description or "", threshold)
            if score >= threshold:
                scored.append((task, score))
        scored.sort(key=lambda x: x[1], reverse=True)

        # If best match is near-exact (>=90), drop weaker matches to avoid
        # flooding the user with false positives from common words like "task"
        if scored and scored[0][1] >= 90:
            cutoff = scored[0][1] - 10
            scored = [(t, s) for t, s in scored if s >= cutoff]

        logger.debug("task.search.fuzzy.done", matched=len(scored))
        return scored[:limit]

from typing import List, Tuple
from rapidfuzz import fuzz


class FuzzyMatcher:
    """Fuzzy matching utility for task search."""

    @staticmethod
    def score_task_match(query: str, task_title: str, task_description: str = "",
                         task_tags: List[str] = None, task_notes: str = "",
                         threshold: int = 70) -> int:
        """Calculate weighted fuzzy match score."""
        query_lower = query.lower()

        # Title (60% weight) - token_set_ratio for word order independence
        title_score = fuzz.token_set_ratio(query_lower, task_title.lower())
        weighted = title_score * 0.6

        # Description (20%)
        if task_description:
            desc_score = fuzz.token_set_ratio(query_lower, task_description.lower())
            weighted += desc_score * 0.2

        # Tags (10%)
        if task_tags:
            tags_str = " ".join(task_tags).lower()
            tags_score = fuzz.token_set_ratio(query_lower, tags_str)
            weighted += tags_score * 0.1

        # Notes (10%)
        if task_notes:
            notes_score = fuzz.token_set_ratio(query_lower, task_notes.lower())
            weighted += notes_score * 0.1

        return int(weighted)

    @staticmethod
    def rank_matches(query: str, tasks: List, threshold: int = 70,
                     limit: int = 5) -> List[Tuple[object, int]]:
        """Rank tasks by fuzzy score."""
        scored = []
        for task in tasks:
            score = FuzzyMatcher.score_task_match(
                query, task.title, task.description or "",
                task.tags or [], task.notes or "", threshold)
            if score >= threshold:
                scored.append((task, score))
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:limit]

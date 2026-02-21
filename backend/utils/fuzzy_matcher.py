from typing import List, Tuple
from rapidfuzz import fuzz


class FuzzyMatcher:
    """Fuzzy matching utility for task search."""

    @staticmethod
    def score_task_match(query: str, task_title: str, task_description: str = "",
                         threshold: int = 70) -> int:
        """Calculate weighted fuzzy match score."""
        query_lower = query.lower()

        # Title - token_set_ratio for word order independence
        title_score = fuzz.token_set_ratio(query_lower, task_title.lower())

        # If no description, title score stands on its own
        if not task_description:
            return int(title_score)

        # Weighted: title 70%, description 30%
        desc_score = fuzz.token_set_ratio(query_lower, task_description.lower())
        weighted = title_score * 0.7 + desc_score * 0.3

        return int(weighted)

    @staticmethod
    def rank_matches(query: str, tasks: List, threshold: int = 70,
                     limit: int = 5) -> List[Tuple[object, int]]:
        """Rank tasks by fuzzy score."""
        scored = []
        print(f"[FuzzyMatcher] query='{query}', searching {len(tasks)} tasks, threshold={threshold}")
        for task in tasks:
            score = FuzzyMatcher.score_task_match(
                query, task.title, task.description or "", threshold)
            if score >= threshold - 20:  # Log near-misses too
                print(f"  -> '{task.title}' score={score} {'✓' if score >= threshold else '✗'}")
            if score >= threshold:
                scored.append((task, score))
        scored.sort(key=lambda x: x[1], reverse=True)
        print(f"[FuzzyMatcher] matched {len(scored)} tasks")
        return scored[:limit]

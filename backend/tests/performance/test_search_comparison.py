#!/usr/bin/env python3
"""
Benchmark: FuzzyMatcher vs TaskSearchService (pg_trgm).

Runs the same queries against both search methods using the seed task tree
and compares match quality + latency.

Usage (inside Docker):
    python tests/performance/test_search_comparison.py
"""

import asyncio
import os
import sys
import time

# Add backend to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://todo:todo123@postgres:5432/todo_db")
os.environ.setdefault("GEMINI_API_KEY", "test-key")
os.environ.setdefault("SEARCH_ENGINE", "pg_native")

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import text
from services.task_service import TaskService
from services.task_search_service import TaskSearchService

USER_ID = "default-user"

# ── Real-world queries for a PM / tech lead ──
# Covers: exact match, partial, typos, ambiguous (same name under multiple parents),
# natural speech ("finish X", "done with Y"), and no-match cases.

QUERIES = [
    # --- Exact / near-exact ---
    "payments rewrite",           # top-level project
    "marathon training",          # health subtask
    "grocery shopping",           # personal errand
    "morning meditation",         # health/mental
    "fast.ai course",             # learning

    # --- Partial / natural speech ---
    "design review",              # AMBIGUOUS: exists under 4 parents!
    "product spec",               # AMBIGUOUS: exists under 4 parents!
    "testing plan",               # AMBIGUOUS: exists under 3 parents
    "unit tests",                 # AMBIGUOUS: under 2 parents
    "sprint retro",               # AMBIGUOUS: 3 parents (2 completed)
    "standup notes",              # AMBIGUOUS: 2 parents
    "meal prep",                  # partial match → "meal prep sunday" or "meal prep ingredients"

    # --- Queries Gemini would produce (natural language) ---
    "auth endpoints",             # specific child under payments → api design
    "notification service",       # child under mobile → push notifications
    "schema migration",           # data pipeline child
    "monitoring dashboard",       # data pipeline child
    "tempo runs",                 # deep child: health → fitness → marathon
    "grafana setup",              # deep: work → pipeline → monitoring
    "cpa appointment",            # deep: personal → finances → tax
    "mom birthday gift",          # personal → family
    "rebalance portfolio",        # personal → finances

    # --- Fuzzy / typos ---
    "grocerries",                 # typo
    "meditaiton",                 # typo
    "intergration tests",         # typo
    "performnce reviews",         # typo
    "budjet tracker",             # typo

    # --- Partial word ---
    "onboarding",                 # should match "onboarding flow"
    "podcast",                    # top-level project
    "supplements",                # health → nutrition
    "rust",                       # should match "learn rust"
    "retro",                      # partial → sprint retro (ambiguous)

    # --- No match ---
    "xyznonexistent",
    "quantum computing",
    "dentist appointment",
]


def _get_parent_title(task, all_tasks_by_id):
    """Get parent title for context."""
    if task.parent_id and task.parent_id in all_tasks_by_id:
        return all_tasks_by_id[task.parent_id].title
    return "(root)"


async def run_benchmark():
    engine = create_async_engine(
        os.environ["DATABASE_URL"],
        echo=False,
    )
    session_factory = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with session_factory() as db:
        task_service = TaskService(db)
        search_service = TaskSearchService(db)

        # Check task count
        result = await db.execute(
            text("SELECT COUNT(*) FROM tasks WHERE user_id = :uid AND status = 'active'"),
            {"uid": USER_ID},
        )
        task_count = result.scalar_one()
        print(f"\nTasks in DB for '{USER_ID}': {task_count}")
        if task_count == 0:
            print("ERROR: No tasks found. Run seed_realistic.py first.")
            return

        # Build lookup for parent context
        all_tasks = await task_service.get_tasks(USER_ID)
        by_id = {t.id: t for t in all_tasks}

        col_q = 25
        col_r = 40
        header = f"{'Query':<{col_q}} {'FuzzyMatcher':<{col_r}} {'pg_trgm':<{col_r}} {'Match?'}"
        sep = "-" * len(header)

        print(f"\n{header}")
        print(sep)

        fuzzy_times = []
        trgm_times = []
        agreements = 0
        total = 0

        for query in QUERIES:
            # FuzzyMatcher
            t0 = time.perf_counter()
            fuzzy_results = await task_service.search_tasks(USER_ID, query)
            fuzzy_ms = (time.perf_counter() - t0) * 1000
            fuzzy_times.append(fuzzy_ms)
            if fuzzy_results:
                ft = fuzzy_results[0]
                fuzzy_top = f"{ft.title} [{_get_parent_title(ft, by_id)}]"
            else:
                fuzzy_top = "(none)"

            # pg_trgm
            t0 = time.perf_counter()
            trgm_results = await search_service.search(USER_ID, query, status_filter="active")
            trgm_ms = (time.perf_counter() - t0) * 1000
            trgm_times.append(trgm_ms)
            if trgm_results:
                tt = trgm_results[0][0]
                trgm_score = trgm_results[0][1]
                trgm_top = f"{tt.title} [{_get_parent_title(tt, by_id)}]"
            else:
                trgm_top = "(none)"
                trgm_score = 0.0

            # Agreement check (same task title)
            fuzzy_title = fuzzy_results[0].title if fuzzy_results else None
            trgm_title = trgm_results[0][0].title if trgm_results else None
            match = fuzzy_title == trgm_title
            if match:
                agreements += 1
            total += 1

            match_str = "==" if match else "!="
            print(
                f"{query:<{col_q}} "
                f"{fuzzy_top:<{col_r}} {fuzzy_ms:>5.1f}ms  "
                f"{trgm_top:<{col_r}} {trgm_ms:>5.1f}ms  "
                f"{match_str}"
            )

        print(sep)
        print(f"\nAgreement: {agreements}/{total} ({agreements/total*100:.0f}%)")
        print(f"\nFuzzyMatcher  — avg: {sum(fuzzy_times)/len(fuzzy_times):.1f}ms  "
              f"p95: {sorted(fuzzy_times)[int(len(fuzzy_times)*0.95)]:.1f}ms")
        print(f"pg_trgm       — avg: {sum(trgm_times)/len(trgm_times):.1f}ms  "
              f"p95: {sorted(trgm_times)[int(len(trgm_times)*0.95)]:.1f}ms")

        # Show multi-result context for ambiguous queries
        print("\n\n═══ AMBIGUOUS QUERY DETAIL (top-3 per method) ═══\n")
        ambiguous = ["design review", "product spec", "testing plan", "unit tests", "standup notes", "meal prep", "retro"]
        for query in ambiguous:
            print(f"  Query: '{query}'")

            fuzzy_results = await task_service.search_tasks(USER_ID, query)
            trgm_results = await search_service.search(USER_ID, query, status_filter="active", limit=5)

            print(f"    FuzzyMatcher:")
            for i, t in enumerate(fuzzy_results[:3]):
                print(f"      {i+1}. {t.title} [{_get_parent_title(t, by_id)}]")
            if not fuzzy_results:
                print(f"      (none)")

            print(f"    pg_trgm:")
            for i, (t, score) in enumerate(trgm_results[:3]):
                print(f"      {i+1}. {t.title} [{_get_parent_title(t, by_id)}] (score={score:.3f})")
            if not trgm_results:
                print(f"      (none)")
            print()

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run_benchmark())

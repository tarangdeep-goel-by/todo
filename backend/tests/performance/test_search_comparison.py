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

# Test queries covering various matching scenarios
QUERIES = [
    "safe drop",
    "backend API",
    "groceries",
    "tech spec",
    "meal prep",
    "project alpha",
    "safedrop",       # no space (fuzzy)
    "grocery",        # partial
    "backend",        # partial
    "meditation",
    "budget review",
    "code review",
    "auth service",
    "xyznonexistent",  # no match
]


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
            print("ERROR: No tasks found. Run seed_tasks.sh or seed_deep_tasks.sh first.")
            return

        print(f"\n{'Query':<25} {'FuzzyMatcher':<35} {'pg_trgm':<35} {'Match?'}")
        print("-" * 110)

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
            fuzzy_top = fuzzy_results[0].title if fuzzy_results else "(none)"

            # pg_trgm
            t0 = time.perf_counter()
            trgm_results = await search_service.search(USER_ID, query, status_filter="active")
            trgm_ms = (time.perf_counter() - t0) * 1000
            trgm_times.append(trgm_ms)
            trgm_top = trgm_results[0][0].title if trgm_results else "(none)"

            match = fuzzy_top == trgm_top
            if match:
                agreements += 1
            total += 1

            match_str = "==" if match else "!="
            print(
                f"{query:<25} "
                f"{fuzzy_top:<25} {fuzzy_ms:>6.1f}ms   "
                f"{trgm_top:<25} {trgm_ms:>6.1f}ms   "
                f"{match_str}"
            )

        print("-" * 110)
        print(f"\nAgreement: {agreements}/{total} ({agreements/total*100:.0f}%)")
        print(f"\nFuzzyMatcher  — avg: {sum(fuzzy_times)/len(fuzzy_times):.1f}ms  "
              f"p95: {sorted(fuzzy_times)[int(len(fuzzy_times)*0.95)]:.1f}ms")
        print(f"pg_trgm       — avg: {sum(trgm_times)/len(trgm_times):.1f}ms  "
              f"p95: {sorted(trgm_times)[int(len(trgm_times)*0.95)]:.1f}ms")

    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(run_benchmark())

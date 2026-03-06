"""E2E tests for search, filter, sort, and pagination."""

import pytest


class TestSearchFilter:
    """Journey: search, filter, sort, and pagination."""

    @pytest.mark.asyncio
    async def test_filter_and_sort(self, e2e):
        # Setup: create diverse tasks
        await e2e.post("/tasks", "Create career/high task", expected_status=201,
            json_body={"title": "Finish report", "category": "career",
                       "transcription": "report", "priority": "high",
                       "due_date": "2026-12-01T00:00:00Z"})
        await e2e.post("/tasks", "Create career/low task", expected_status=201,
            json_body={"title": "Update resume", "category": "career",
                       "transcription": "resume", "priority": "low",
                       "due_date": "2026-12-15T00:00:00Z"})
        await e2e.post("/tasks", "Create home/medium task", expected_status=201,
            json_body={"title": "Buy groceries", "category": "home",
                       "transcription": "groceries", "priority": "medium",
                       "due_date": "2026-12-10T00:00:00Z"})
        t4 = await e2e.post("/tasks", "Create health/high task", expected_status=201,
            json_body={"title": "Doctor appointment", "category": "health",
                       "transcription": "doctor", "priority": "high"})
        t5 = await e2e.post("/tasks", "Create home/low task", expected_status=201,
            json_body={"title": "Clean garage", "category": "home",
                       "transcription": "garage", "priority": "low"})

        # Complete one task for status filter testing
        await e2e.put(f"/tasks/{t4['id']}/complete", "Complete health task")

        # Filter by category
        career = await e2e.get("/tasks", "Filter by career category",
            params={"category": "career"})
        assert career["total_count"] == 2
        assert all(t["category"] == "career" for t in career["tasks"])

        # Filter by status
        active = await e2e.get("/tasks", "Filter active only",
            params={"status": "active"})
        assert active["total_count"] == 4  # 5 created minus 1 completed

        completed = await e2e.get("/tasks", "Filter completed only",
            params={"status": "completed"})
        assert completed["total_count"] == 1

        # Filter by priority
        high = await e2e.get("/tasks", "Filter high priority",
            params={"priority": "high"})
        assert high["total_count"] == 2  # career+health (even completed)

        # Multi-filter: home + active
        home_active = await e2e.get("/tasks", "Filter home + active",
            params={"category": "home", "status": "active"})
        assert home_active["total_count"] == 2

        # Sort by due_date ascending (nulls last)
        sorted_tasks = await e2e.get("/tasks", "Sort by due_date asc",
            params={"sort": "due_date:asc", "status": "active"})
        dates = [t["due_date"] for t in sorted_tasks["tasks"] if t["due_date"]]
        assert dates == sorted(dates)  # ascending

        # Sort by priority descending
        by_priority = await e2e.get("/tasks", "Sort by priority desc",
            params={"sort": "priority:desc"})
        # high tasks should come first
        priorities = [t["priority"] for t in by_priority["tasks"]]
        # Just verify high comes before low
        high_idx = next(i for i, p in enumerate(priorities) if p == "high")
        low_idx = next(i for i, p in enumerate(priorities) if p == "low")
        assert high_idx < low_idx

    @pytest.mark.asyncio
    async def test_pagination(self, e2e):
        # Create 5 tasks
        for i in range(5):
            await e2e.post("/tasks", f"Create task {i+1}", expected_status=201,
                json_body={"title": f"Page task {i+1}", "category": "career",
                           "transcription": f"pt{i+1}"})

        # Page 1: limit=3, offset=0
        page1 = await e2e.get("/tasks", "Get page 1",
            params={"limit": "3", "offset": "0"})
        assert len(page1["tasks"]) == 3
        assert page1["total_count"] == 5
        assert page1["has_more"] is True

        # Page 2: limit=3, offset=3
        page2 = await e2e.get("/tasks", "Get page 2",
            params={"limit": "3", "offset": "3"})
        assert len(page2["tasks"]) == 2
        assert page2["has_more"] is False

        # No overlap
        page1_ids = {t["id"] for t in page1["tasks"]}
        page2_ids = {t["id"] for t in page2["tasks"]}
        assert page1_ids.isdisjoint(page2_ids)

    @pytest.mark.asyncio
    async def test_search(self, e2e):
        # Create tasks with distinct titles
        await e2e.post("/tasks", "Create searchable task 1", expected_status=201,
            json_body={"title": "Buy chocolate cake", "category": "home",
                       "transcription": "chocolate cake"})
        await e2e.post("/tasks", "Create searchable task 2", expected_status=201,
            json_body={"title": "Fix bicycle wheel", "category": "home",
                       "transcription": "bicycle wheel"})
        await e2e.post("/tasks", "Create searchable task 3", expected_status=201,
            json_body={"title": "Learn Python programming", "category": "career",
                       "transcription": "python"})

        # Search for "chocolate"
        results = await e2e.get("/tasks/search", "Search for chocolate",
            params={"q": "chocolate"})
        assert results["total_count"] >= 1
        assert any("chocolate" in r["task"]["title"] for r in results["results"])

        # Search with no results
        empty = await e2e.get("/tasks/search", "Search for nonexistent",
            params={"q": "xyznonexistent"})
        assert empty["total_count"] == 0

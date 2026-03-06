"""E2E tests for new user onboarding journey."""

import pytest


class TestNewUserOnboarding:
    """Journey: fresh user creates categories, tasks, checks stats."""

    @pytest.mark.asyncio
    async def test_new_user_journey(self, e2e):
        # Step 1: Create first category
        cat1 = await e2e.post(
            "/categories",
            "Create career category",
            expected_status=201,
            json_body={"name": "career"},
        )
        assert cat1["name"] == "career"

        # Step 2: Create second category
        cat2 = await e2e.post(
            "/categories",
            "Create home category",
            expected_status=201,
            json_body={"name": "home"},
        )
        assert cat2["name"] == "home"

        # Step 3: List categories and verify 2 exist
        categories = await e2e.get("/categories", "List categories")
        assert len(categories) == 2
        category_names = {c["name"] for c in categories}
        assert category_names == {"career", "home"}

        # Step 4: Create first task in career — title gets lowercased by backend
        task1 = await e2e.post(
            "/tasks",
            "Create first task in career",
            expected_status=201,
            json_body={
                "title": "Update Resume",
                "category": "career",
                "transcription": "I need to update my resume",
            },
        )
        assert task1["title"] == "update resume"
        assert task1["category"] == "career"

        # Step 5: Create second task in home
        task2 = await e2e.post(
            "/tasks",
            "Create second task in home",
            expected_status=201,
            json_body={
                "title": "Fix Kitchen Sink",
                "category": "home",
                "transcription": "I need to fix the kitchen sink",
            },
        )
        assert task2["title"] == "fix kitchen sink"
        assert task2["category"] == "home"

        # Step 6: List all tasks and verify 2 exist
        task_list = await e2e.get("/tasks", "List all tasks")
        assert task_list["total_count"] == 2
        assert len(task_list["tasks"]) == 2

        # Step 7: Get stats and verify counts
        stats = await e2e.get("/tasks/stats", "Get task stats")
        assert stats["total_tasks"] == 2
        assert stats["by_status"]["active"] == 2
        assert stats["due_soon_count"] == 0

        # Step 8: Create remaining 6 categories to reach the limit of 8
        remaining_categories = [
            "finance",
            "health",
            "relationships",
            "growth",
            "recreation",
            "community",
        ]
        for name in remaining_categories:
            await e2e.post(
                "/categories",
                f"Create {name} category",
                expected_status=201,
                json_body={"name": name},
            )

        # Verify all 8 categories exist
        all_categories = await e2e.get(
            "/categories", "List all categories after filling limit"
        )
        assert len(all_categories) == 8

        # Step 9: Try creating a 9th category — should fail with 400
        await e2e.post(
            "/categories",
            "Attempt 9th category (should fail)",
            expected_status=400,
            json_body={"name": "extras"},
        )

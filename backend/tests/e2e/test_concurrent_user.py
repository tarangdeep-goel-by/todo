"""E2E tests for user isolation — two users, data stays separate."""

import pytest


class TestConcurrentUsers:
    """Journey: two users, data isolation."""

    @pytest.mark.asyncio
    async def test_task_isolation(self, e2e, e2e_user2):
        # User A creates tasks
        a_task = await e2e.post(
            "/tasks",
            "User A creates task",
            expected_status=201,
            json_body={"title": "A's task", "category": "career", "transcription": "a task"},
        )

        # User B creates tasks
        b_task = await e2e_user2.post(
            "/tasks",
            "User B creates task",
            expected_status=201,
            json_body={"title": "B's task", "category": "home", "transcription": "b task"},
        )

        # User A lists → only sees own tasks
        a_list = await e2e.get("/tasks", "User A lists tasks")
        a_ids = [t["id"] for t in a_list["tasks"]]
        assert a_task["id"] in a_ids
        assert b_task["id"] not in a_ids

        # User B lists → only sees own tasks
        b_list = await e2e_user2.get("/tasks", "User B lists tasks")
        b_ids = [t["id"] for t in b_list["tasks"]]
        assert b_task["id"] in b_ids
        assert a_task["id"] not in b_ids

    @pytest.mark.asyncio
    async def test_cross_user_access_rejected(self, e2e, e2e_user2):
        # User A creates a task
        a_task = await e2e.post(
            "/tasks",
            "User A creates task",
            expected_status=201,
            json_body={"title": "Private task", "category": "career", "transcription": "private"},
        )

        # User B tries to GET User A's task → 403
        await e2e_user2.get(
            f"/tasks/{a_task['id']}",
            "User B tries to read A's task",
            expected_status=403,
        )

        # User B tries to complete User A's task → 403
        await e2e_user2.put(
            f"/tasks/{a_task['id']}/complete",
            "User B tries to complete A's task",
            expected_status=403,
        )

    @pytest.mark.asyncio
    async def test_category_isolation(self, e2e, e2e_user2):
        # Both users create same category name → both succeed (separate)
        a_cat = await e2e.post(
            "/categories",
            "User A creates career",
            expected_status=201,
            json_body={"name": "career"},
        )
        b_cat = await e2e_user2.post(
            "/categories",
            "User B creates career",
            expected_status=201,
            json_body={"name": "career"},
        )

        # Both exist independently
        assert a_cat["name"] == "career"
        assert b_cat["name"] == "career"
        assert a_cat["id"] != b_cat["id"]

        # User A only sees their categories
        a_cats = await e2e.get("/categories", "User A lists categories")
        a_cat_ids = [c["id"] for c in a_cats]
        assert a_cat["id"] in a_cat_ids
        assert b_cat["id"] not in a_cat_ids

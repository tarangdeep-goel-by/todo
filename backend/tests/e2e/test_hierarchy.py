"""E2E tests for tree/hierarchy operations."""

import pytest


class TestHierarchy:
    """Journey: parent/child tree operations."""

    @pytest.mark.asyncio
    async def test_tree_operations(self, e2e):
        # Step 1: Create parent task
        parent = await e2e.post(
            "/tasks",
            "Create parent",
            expected_status=201,
            json_body={
                "title": "Project Alpha",
                "category": "career",
                "transcription": "project alpha",
            },
        )
        parent_id = parent["id"]

        # Step 2: Create 3 children under parent
        children = []
        for i in range(3):
            child = await e2e.post(
                "/tasks",
                f"Create child {i + 1}",
                expected_status=201,
                json_body={
                    "title": f"Task {i + 1}",
                    "category": "career",
                    "transcription": f"task {i + 1}",
                    "parent_id": parent_id,
                },
            )
            assert child["parent_id"] == parent_id
            children.append(child)

        # Step 3: Create grandchild
        grandchild = await e2e.post(
            "/tasks",
            "Create grandchild",
            expected_status=201,
            json_body={
                "title": "Sub-sub task",
                "category": "career",
                "transcription": "sub sub",
                "parent_id": children[0]["id"],
            },
        )
        assert grandchild["parent_id"] == children[0]["id"]

        # Step 4: Verify tree via filtered query
        child_list = await e2e.get(
            "/tasks", "List children of parent", params={"parent_id": parent_id}
        )
        assert child_list["total_count"] == 3

        # Step 5: Complete parent -> cascades to children
        await e2e.put(f"/tasks/{parent_id}/complete", "Complete parent (cascade)")
        # Verify children are completed too
        for child in children:
            c = await e2e.get(
                f"/tasks/{child['id']}", f"Verify child {child['id']} completed"
            )
            assert c["status"] == "completed"

        # Step 6: Create new child under completed parent -> ancestor activation
        new_child = await e2e.post(
            "/tasks",
            "Create child under completed parent",
            expected_status=201,
            json_body={
                "title": "New task",
                "category": "career",
                "transcription": "new task",
                "parent_id": parent_id,
            },
        )
        # Verify parent reactivated
        reactivated = await e2e.get(
            f"/tasks/{parent_id}", "Verify parent reactivated"
        )
        assert reactivated["status"] == "active"

    @pytest.mark.asyncio
    async def test_move_task(self, e2e):
        # Create two parents
        p1 = await e2e.post(
            "/tasks",
            "Create parent 1",
            expected_status=201,
            json_body={
                "title": "Parent 1",
                "category": "career",
                "transcription": "p1",
            },
        )
        p2 = await e2e.post(
            "/tasks",
            "Create parent 2",
            expected_status=201,
            json_body={
                "title": "Parent 2",
                "category": "career",
                "transcription": "p2",
            },
        )

        # Create child under p1
        child = await e2e.post(
            "/tasks",
            "Create child under P1",
            expected_status=201,
            json_body={
                "title": "Movable",
                "category": "career",
                "transcription": "movable",
                "parent_id": p1["id"],
            },
        )

        # Move child to p2
        moved = await e2e.patch(
            f"/tasks/{child['id']}",
            "Move child to P2",
            json_body={"parent_id": p2["id"]},
        )
        assert moved["parent_id"] == p2["id"]

    @pytest.mark.asyncio
    async def test_circular_move_rejected(self, e2e):
        # Create parent -> child
        parent = await e2e.post(
            "/tasks",
            "Create parent",
            expected_status=201,
            json_body={
                "title": "Parent",
                "category": "career",
                "transcription": "parent",
            },
        )
        child = await e2e.post(
            "/tasks",
            "Create child",
            expected_status=201,
            json_body={
                "title": "Child",
                "category": "career",
                "transcription": "child",
                "parent_id": parent["id"],
            },
        )

        # Try moving parent under its own child -> ValueError
        # NOTE: The tasks router doesn't catch ValueError from update_task,
        # so this propagates as an unhandled exception through ASGITransport
        # rather than a clean 400 response. This is a known gap — the
        # categories router does catch ValueError → 400, but tasks doesn't.
        with pytest.raises(ValueError, match="Cannot move task under its own descendant"):
            await e2e.patch(
                f"/tasks/{parent['id']}",
                "Try circular move (should fail)",
                expected_status=400,
                json_body={"parent_id": child["id"]},
            )

    @pytest.mark.asyncio
    async def test_delete_parent_archives_descendants(self, e2e):
        parent = await e2e.post(
            "/tasks",
            "Create parent",
            expected_status=201,
            json_body={
                "title": "To Delete",
                "category": "career",
                "transcription": "del",
            },
        )
        child = await e2e.post(
            "/tasks",
            "Create child",
            expected_status=201,
            json_body={
                "title": "Child of deleted",
                "category": "career",
                "transcription": "child",
                "parent_id": parent["id"],
            },
        )

        # Archive parent (and children)
        result = await e2e.put(
            f"/tasks/{parent['id']}/archive", "Archive parent + children"
        )
        assert result["archived_count"] == 2

        # Both should be archived
        p = await e2e.get(f"/tasks/{parent['id']}", "Verify parent archived")
        assert p["status"] == "archived"
        c = await e2e.get(f"/tasks/{child['id']}", "Verify child archived")
        assert c["status"] == "archived"

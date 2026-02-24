"""Tests for ancestor chain activation — 7 tests."""
import pytest
from tests.helpers import make_task


class TestActivateAncestorOnUndo:
    """When a task is set back to active, completed ancestors must also activate."""

    async def test_undo_child_activates_parent(self, task_service):
        """Complete parent+child, undo child → parent becomes active."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        child = await task_service.create_task(
            **make_task(title="Child", parent_id=parent.id)
        )
        await task_service.complete_task_with_children(parent.id)

        # Undo child
        await task_service.update_task(child.id, status="active")

        refreshed = await task_service.get_task(parent.id)
        assert refreshed.status == "active"
        assert refreshed.completed_at is None

    async def test_undo_grandchild_activates_entire_chain(self, task_service):
        """Complete GP→P→C chain, undo C → GP and P both become active."""
        gp = await task_service.create_task(**make_task(title="Grandparent"))
        p = await task_service.create_task(
            **make_task(title="Parent", parent_id=gp.id)
        )
        c = await task_service.create_task(
            **make_task(title="Child", parent_id=p.id)
        )
        await task_service.complete_task_with_children(gp.id)

        await task_service.update_task(c.id, status="active")

        assert (await task_service.get_task(gp.id)).status == "active"
        assert (await task_service.get_task(p.id)).status == "active"

    async def test_undo_parent_does_not_activate_children(self, task_service):
        """Complete parent+child, undo parent → child stays completed."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        child = await task_service.create_task(
            **make_task(title="Child", parent_id=parent.id)
        )
        await task_service.complete_task_with_children(parent.id)

        await task_service.update_task(parent.id, status="active")

        refreshed_child = await task_service.get_task(child.id)
        assert refreshed_child.status == "completed"

    async def test_undo_root_task_no_error(self, task_service):
        """Undo a root task (no parent) → no crash, just activates itself."""
        root = await task_service.create_task(**make_task(title="Root"))
        await task_service.complete_task(root.id)

        updated = await task_service.update_task(root.id, status="active")
        assert updated.status == "active"


class TestActivateAncestorOnAddChild:
    """When a child is added to a completed parent, ancestors must activate."""

    async def test_add_subtask_activates_completed_parent(self, task_service):
        """Add child to completed parent → parent becomes active."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        await task_service.complete_task(parent.id)

        await task_service.create_task(
            **make_task(title="New Child", parent_id=parent.id)
        )

        refreshed = await task_service.get_task(parent.id)
        assert refreshed.status == "active"
        assert refreshed.completed_at is None

    async def test_add_subtask_activates_entire_ancestor_chain(self, task_service):
        """Add child to completed parent whose GP is also completed → both active."""
        gp = await task_service.create_task(**make_task(title="Grandparent"))
        p = await task_service.create_task(
            **make_task(title="Parent", parent_id=gp.id)
        )
        await task_service.complete_task_with_children(gp.id)

        await task_service.create_task(
            **make_task(title="New Child", parent_id=p.id)
        )

        assert (await task_service.get_task(gp.id)).status == "active"
        assert (await task_service.get_task(p.id)).status == "active"

    async def test_add_subtask_to_active_parent_no_side_effect(self, task_service):
        """Add child to active parent → no status changes."""
        parent = await task_service.create_task(**make_task(title="Parent"))
        await task_service.create_task(
            **make_task(title="Child", parent_id=parent.id)
        )

        refreshed = await task_service.get_task(parent.id)
        assert refreshed.status == "active"

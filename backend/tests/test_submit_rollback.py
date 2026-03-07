"""Tests for brain dump submit atomic rollback (M4)."""
import pytest
from models.schemas import BrainDumpTaskProposal
from tests.helpers import make_task_tree
from sqlalchemy import text


class TestSubmitRollback:
    """submit_brain_dump() should be atomic — all-or-nothing."""

    async def test_partial_failure_rolls_back_all(
        self, agent_service, task_service, db_session
    ):
        """If proposal #2 fails (invalid parent_id), proposals #1 and #3 are rolled back."""
        await make_task_tree(task_service)

        proposals = [
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000b01", content="Task one", category="home",
            ),
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000b02", content="Task two", category="home",
                parent_id="00000000-0000-0000-0000-000000000099",  # non-existent
            ),
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000b03", content="Task three", category="home",
            ),
        ]

        result = await agent_service.submit_brain_dump(
            "test-user", proposals, db_session
        )

        assert result.success is False
        assert result.created_count == 0
        assert result.created_task_ids == []
        assert "rolled back" in result.message.lower()
        assert result.failed_reason is not None

        # Verify NO tasks from this batch exist in the DB
        # (need a fresh query since session was rolled back)
        rows = await db_session.execute(
            text("SELECT id FROM tasks WHERE title IN ('task one', 'task two', 'task three')")
        )
        assert rows.fetchall() == []

    async def test_all_valid_proposals_committed(
        self, agent_service, task_service, db_session
    ):
        """When all proposals are valid, all are committed successfully."""
        await make_task_tree(task_service)

        proposals = [
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000c01", content="Valid task A", category="home",
            ),
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000c02", content="Valid task B", category="career",
                priority="high",
            ),
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000c03", content="Valid task C", category="home",
            ),
        ]

        result = await agent_service.submit_brain_dump(
            "test-user", proposals, db_session
        )

        assert result.success is True
        assert result.created_count == 3
        assert len(result.created_task_ids) == 3
        assert result.failed_reason is None

        # Verify all tasks exist in DB
        for task_id in result.created_task_ids:
            task = await task_service.get_task(task_id)
            assert task is not None

    async def test_rollback_on_edit_failure_undoes_prior_adds(
        self, agent_service, task_service, db_session
    ):
        """ADD + failing EDIT → ADD is rolled back too."""
        tree = await make_task_tree(task_service)

        proposals = [
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000d01", content="New task before edit", category="home",
            ),
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000d02", action="edit", content="Groceries",
                category="home", matched_task_id=tree["groceries"].id,
                changes={"parent_id": "00000000-0000-0000-0000-000000000099"},
            ),
        ]

        result = await agent_service.submit_brain_dump(
            "test-user", proposals, db_session
        )

        assert result.success is False
        assert result.created_count == 0

        # The ADD from proposal #1 should NOT exist
        rows = await db_session.execute(
            text("SELECT id FROM tasks WHERE title = 'new task before edit'")
        )
        assert rows.fetchall() == []

    async def test_failed_reason_populated_on_error(
        self, agent_service, task_service, db_session
    ):
        """failed_reason should contain the error message on rollback."""
        await make_task_tree(task_service)

        proposals = [
            BrainDumpTaskProposal(
                id="00000000-0000-0000-0000-000000000e01", action="edit", content="Groceries",
                category="home", matched_task_id="00000000-0000-0000-0000-000000000001",
                changes={"parent_id": "00000000-0000-0000-0000-000000000099"},
            ),
        ]

        result = await agent_service.submit_brain_dump(
            "test-user", proposals, db_session
        )

        assert result.success is False
        assert result.failed_reason is not None
        assert len(result.failed_reason) > 0

"""Tests for AgentService.resolve_question() — 18 tests."""
import pytest
from tests.helpers import make_task, make_task_tree

MISSING_UUID = "ffffffff-ffff-ffff-ffff-ffffffffffff"


# ──────────── action=complete ────────────

class TestResolveComplete:
    async def test_complete_single_task(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="complete", data=None, db=db_session,
        )
        assert result.success is True
        assert result.type == "confirmation"
        assert "Completed" in result.message

    async def test_complete_task_with_children(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["project_alpha"]  # has child backend_api
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="complete", data=None, db=db_session,
        )
        assert result.success is True
        assert "sub-tasks" in result.message

    async def test_complete_task_not_found(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=MISSING_UUID,
            action="complete", data=None, db=db_session,
        )
        assert result.success is False
        assert "not found" in result.message.lower()


# ──────────── action=delete ────────────

class TestResolveDelete:
    async def test_delete_single_task(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="delete", data=None, db=db_session,
        )
        assert result.success is True
        assert "Deleted" in result.message
        assert await task_service.get_task(task.id) is None

    async def test_delete_with_descendants(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["project_alpha"]
        child_id = tree["backend_api"].id
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="delete", data=None, db=db_session,
        )
        assert result.success is True
        assert await task_service.get_task(child_id) is None

    async def test_delete_not_found(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=MISSING_UUID,
            action="delete", data=None, db=db_session,
        )
        assert result.success is False


# ──────────── action=edit ────────────

class TestResolveEdit:
    async def test_edit_title(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="edit", data={"changes": {"title": "Buy groceries"}},
            db=db_session,
        )
        assert result.success is True
        updated = await task_service.get_task(task.id)
        assert updated.title == "buy groceries"

    async def test_edit_due_date(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="edit", data={"changes": {"dueDate": "tomorrow"}},
            db=db_session,
        )
        assert result.success is True

    async def test_edit_not_found(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=MISSING_UUID,
            action="edit", data={"changes": {"title": "x"}},
            db=db_session,
        )
        assert result.success is False


# ──────────── action=move ────────────

class TestResolveMove:
    async def test_move_to_parent(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="move",
            data={"targetParentQuery": "Project Alpha"},
            db=db_session,
        )
        assert result.success is True
        assert "Moved" in result.message

    async def test_move_no_target_query(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="move", data={}, db=db_session,
        )
        assert result.success is False

    async def test_move_parent_not_found(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="move",
            data={"targetParentQuery": "zzz_nonexistent_zzz"},
            db=db_session,
        )
        assert result.success is False

    async def test_move_ambiguous_parent_returns_question(self, agent_service, task_service, db_session):
        """Two parents match → chained question."""
        tree = await make_task_tree(task_service)
        await task_service.create_task(
            user_id="test-user", title="Meeting Prep A", category="work",
            parent_id=None, transcription="meeting prep a",
        )
        await task_service.create_task(
            user_id="test-user", title="Meeting Prep B", category="work",
            parent_id=None, transcription="meeting prep b",
        )
        task = tree["groceries"]
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=task.id,
            action="move",
            data={"targetParentQuery": "Meeting Prep"},
            db=db_session,
        )
        assert result.type == "question"
        assert result.data["action"] == "select_parent"


# ──────────── action=select_parent ────────────

class TestResolveSelectParent:
    async def test_select_parent_success(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        result = await agent_service.resolve_question(
            user_id="test-user",
            selected_task_id=tree["project_alpha"].id,
            action="select_parent",
            data={"taskToMove": tree["groceries"].id},
            db=db_session,
        )
        assert result.success is True
        moved = await task_service.get_task(tree["groceries"].id)
        assert moved.parent_id == tree["project_alpha"].id

    async def test_select_parent_task_not_found(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=tree["project_alpha"].id,
            action="select_parent",
            data={"taskToMove": MISSING_UUID},
            db=db_session,
        )
        assert result.success is False

    async def test_select_parent_parent_not_found(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=MISSING_UUID,
            action="select_parent",
            data={"taskToMove": tree["groceries"].id},
            db=db_session,
        )
        assert result.success is False


# ──────────── action=create_category ────────────

class TestResolveCreateCategory:
    async def test_create_new_category_and_task(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=None,
            action="create_category",
            data={"suggested_title": "Practice violin", "suggested_category": "hobbies"},
            db=db_session,
        )
        assert result.success is True
        assert "hobbies" in result.message.lower() or "Hobbies" in result.message
        # Category should exist in categories table
        categories = await task_service.get_categories("test-user")
        assert "hobbies" in categories

    async def test_create_under_existing_category(self, agent_service, task_service, db_session):
        tree = await make_task_tree(task_service)
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=None,
            action="create_category",
            data={"suggested_title": "Code review", "suggested_category": "work"},
            db=db_session,
        )
        assert result.success is True

    async def test_create_category_missing_data(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=None,
            action="create_category",
            data={},
            db=db_session,
        )
        assert result.success is False


# ──────────── unknown action ────────────

class TestResolveUnknown:
    async def test_unknown_action(self, agent_service, task_service, db_session):
        result = await agent_service.resolve_question(
            user_id="test-user", selected_task_id=None,
            action="foobar", data=None, db=db_session,
        )
        assert result.success is False
        assert "Unknown action" in result.message

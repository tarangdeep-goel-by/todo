"""Tests for per-user WebSocket connection limit."""
import asyncio
import json
import pytest
from unittest.mock import patch, MagicMock

from routers.ramble import ramble_websocket, _active_connections, _connections_lock


class FakeWebSocket:
    """Lightweight WebSocket mock for testing the ramble endpoint."""

    def __init__(self, messages: list[str]):
        self._messages = list(messages)
        self._sent: list = []
        self._closed = False
        self._close_code = None

    async def accept(self):
        pass

    async def receive_text(self):
        if not self._messages:
            raise Exception("No more messages")
        return self._messages.pop(0)

    async def send_json(self, data: dict):
        self._sent.append(data)

    async def close(self, code: int = 1000, reason: str = ""):
        self._closed = True
        self._close_code = code

    @property
    def sent_messages(self) -> list:
        return self._sent


@pytest.fixture(autouse=True)
def reset_connections():
    """Clear connection tracking before and after each test."""
    _active_connections.clear()
    yield
    _active_connections.clear()


@pytest.fixture
def mock_firebase_ok():
    """Mock firebase to accept any token."""
    with patch("routers.ramble._init_firebase"), \
         patch("firebase_admin.auth.verify_id_token") as mock_verify:
        mock_verify.return_value = {"uid": "test-user-123"}
        yield mock_verify


def _make_settings(max_ws=2):
    """Create mock settings with given max_ws_connections_per_user."""
    s = MagicMock()
    s.max_ws_connections_per_user = max_ws
    s.sarvam_api_key = "fake-key"
    return s


class TestWebSocketConnectionLimit:
    """Per-user WebSocket connection limit tests."""

    @pytest.mark.asyncio
    async def test_first_connection_succeeds(self, mock_firebase_ok):
        """First connection within limit is accepted."""
        with patch("routers.ramble.get_settings", return_value=_make_settings(max_ws=2)):
            ws = FakeWebSocket([
                json.dumps({"type": "auth", "token": "valid-token"}),
                json.dumps({"type": "stop"}),
            ])
            await ramble_websocket(ws)

        assert ws.sent_messages[0] == {"type": "auth_ok"}
        assert not any(m.get("message") == "Too many active connections" for m in ws.sent_messages)

    @pytest.mark.asyncio
    async def test_connection_at_limit_rejected(self, mock_firebase_ok):
        """Connection at the limit gets rejected with code 4009."""
        # Pre-fill connections to the limit
        _active_connections["test-user-123"] = 2

        with patch("routers.ramble.get_settings", return_value=_make_settings(max_ws=2)):
            ws = FakeWebSocket([
                json.dumps({"type": "auth", "token": "valid-token"}),
            ])
            await ramble_websocket(ws)

        assert ws._closed
        assert ws._close_code == 4009
        error_msgs = [m for m in ws.sent_messages if m.get("type") == "error"]
        assert any("Too many active connections" in m["message"] for m in error_msgs)

    @pytest.mark.asyncio
    async def test_connection_count_decrements_after_disconnect(self, mock_firebase_ok):
        """Connection count decrements when the session ends (finally block)."""
        with patch("routers.ramble.get_settings", return_value=_make_settings(max_ws=3)):
            ws = FakeWebSocket([
                json.dumps({"type": "auth", "token": "valid-token"}),
                json.dumps({"type": "stop"}),
            ])
            await ramble_websocket(ws)

        # After disconnect, user should be removed (count was 1, now 0)
        assert "test-user-123" not in _active_connections

    @pytest.mark.asyncio
    async def test_different_users_independent_limits(self, mock_firebase_ok):
        """Different users have independent connection limits."""
        # User A is at the limit
        _active_connections["user-A"] = 2

        # User B (test-user-123 from mock) should still connect fine
        with patch("routers.ramble.get_settings", return_value=_make_settings(max_ws=2)):
            ws = FakeWebSocket([
                json.dumps({"type": "auth", "token": "valid-token"}),
                json.dumps({"type": "stop"}),
            ])
            await ramble_websocket(ws)

        assert ws.sent_messages[0] == {"type": "auth_ok"}
        assert not ws._closed or ws._close_code != 4009
        # User A still at limit
        assert _active_connections["user-A"] == 2

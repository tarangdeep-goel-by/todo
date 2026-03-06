"""Tests for WebSocket auth-in-first-message protocol."""
import asyncio
import json
import pytest
from unittest.mock import patch, AsyncMock, MagicMock


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


@pytest.fixture
def mock_firebase_ok():
    """Mock firebase to accept any token."""
    with patch("routers.ramble._init_firebase"), \
         patch("firebase_admin.auth.verify_id_token") as mock_verify:
        mock_verify.return_value = {"uid": "test-user-123"}
        yield mock_verify


@pytest.fixture
def mock_firebase_reject():
    """Mock firebase to reject tokens."""
    with patch("routers.ramble._init_firebase"), \
         patch("firebase_admin.auth.verify_id_token") as mock_verify:
        mock_verify.side_effect = Exception("Invalid token")
        yield mock_verify


class TestWebSocketAuth:
    """WebSocket auth-in-first-message protocol tests."""

    @pytest.mark.asyncio
    async def test_auth_ok_with_valid_token(self, mock_firebase_ok):
        """Valid auth message gets auth_ok response."""
        from routers.ramble import ramble_websocket

        ws = FakeWebSocket([
            json.dumps({"type": "auth", "token": "valid-token"}),
            json.dumps({"type": "stop"}),
        ])
        await ramble_websocket(ws)

        assert ws.sent_messages[0] == {"type": "auth_ok"}

    @pytest.mark.asyncio
    async def test_auth_rejected_with_invalid_token(self, mock_firebase_reject):
        """Invalid token gets auth_error and connection closed."""
        from routers.ramble import ramble_websocket

        ws = FakeWebSocket([
            json.dumps({"type": "auth", "token": "bad-token"}),
        ])
        await ramble_websocket(ws)

        assert ws.sent_messages[0]["type"] == "auth_error"
        assert "Authentication failed" in ws.sent_messages[0]["message"]
        assert ws._closed
        assert ws._close_code == 4001

    @pytest.mark.asyncio
    async def test_non_auth_first_message_rejected(self, mock_firebase_ok):
        """Sending a non-auth message first closes connection."""
        from routers.ramble import ramble_websocket

        ws = FakeWebSocket([
            json.dumps({"type": "start"}),
        ])
        await ramble_websocket(ws)

        assert ws.sent_messages[0]["type"] == "auth_error"
        assert ws._closed
        assert ws._close_code == 4001

    @pytest.mark.asyncio
    async def test_auth_timeout_closes_connection(self, mock_firebase_ok):
        """No message within timeout closes connection."""
        from routers.ramble import ramble_websocket, WS_AUTH_TIMEOUT_SECONDS

        class SlowWebSocket(FakeWebSocket):
            async def receive_text(self):
                await asyncio.sleep(WS_AUTH_TIMEOUT_SECONDS + 1)

        ws = SlowWebSocket([])

        # Patch timeout to be very short for test speed
        with patch("routers.ramble.WS_AUTH_TIMEOUT_SECONDS", 0.1):
            await ramble_websocket(ws)

        assert ws._closed
        assert ws._close_code == 4008

    @pytest.mark.asyncio
    async def test_invalid_json_rejected(self, mock_firebase_ok):
        """Sending invalid JSON as first message closes connection."""
        from routers.ramble import ramble_websocket

        ws = FakeWebSocket(["not json at all"])
        await ramble_websocket(ws)

        assert ws._closed
        assert ws._close_code == 4001

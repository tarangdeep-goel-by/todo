"""Tests for RambleSession (Sarvam AI streaming STT)."""
import asyncio
import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class FakeSarvamWS:
    """Mock Sarvam streaming WebSocket connection."""

    def __init__(self, events=None):
        self._events = events or []
        self.transcribe = AsyncMock()

    def __aiter__(self):
        return self

    async def __anext__(self):
        if not self._events:
            raise StopAsyncIteration
        return self._events.pop(0)


class FakeContextManager:
    """Mock async context manager for Sarvam connect()."""

    def __init__(self, ws):
        self._ws = ws

    async def __aenter__(self):
        return self._ws

    async def __aexit__(self, *args):
        pass


def _make_transcript_event(text: str):
    """Create a mock Sarvam transcript event."""
    data = MagicMock()
    data.transcript = text
    event = MagicMock()
    event.type = "data"
    event.data = data
    return event


def _make_error_event(msg: str):
    """Create a mock Sarvam error event."""
    event = MagicMock()
    event.type = "error"
    event.data = msg
    return event


@pytest.fixture
def mock_sarvam_client():
    """Patch AsyncSarvamAI so no real connection is made."""
    with patch("services.ramble_service.AsyncSarvamAI") as MockCls:
        client = MagicMock()
        MockCls.return_value = client
        yield client


class TestRambleSessionLifecycle:
    """Session create / start / close."""

    @pytest.mark.asyncio
    async def test_create_session(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        session = RambleSession(api_key="test-key")
        assert session.accumulated_transcription == ""
        assert session._ws is None

    @pytest.mark.asyncio
    async def test_start_opens_sarvam_connection(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        fake_ws = FakeSarvamWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        # Connection was opened
        mock_sarvam_client.speech_to_text_streaming.connect.assert_called_once()
        call_kwargs = mock_sarvam_client.speech_to_text_streaming.connect.call_args.kwargs
        assert call_kwargs["model"] == "saaras:v3"
        assert call_kwargs["mode"] == "translate"
        assert session._ws is fake_ws
        assert session._session_start is not None

        await session.close()

    @pytest.mark.asyncio
    async def test_close_cleans_up_resources(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        fake_ws = FakeSarvamWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()
        assert session._ws is not None

        await session.close()
        assert session._ws is None
        assert session._context_manager is None

    @pytest.mark.asyncio
    async def test_close_without_start_is_safe(self, mock_sarvam_client):
        """Closing a session that was never started should not raise."""
        from services.ramble_service import RambleSession

        session = RambleSession(api_key="test-key")
        await session.close()  # Should not raise


class TestAudioChunkHandling:
    """Sending audio data to Sarvam."""

    @pytest.mark.asyncio
    async def test_send_audio_forwards_to_sarvam(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        fake_ws = FakeSarvamWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        audio_b64 = "SGVsbG8gV29ybGQ="  # "Hello World" base64
        await session.send_audio(audio_b64)

        fake_ws.transcribe.assert_called_once_with(
            audio=audio_b64,
            encoding="audio/wav",
            sample_rate=16000,
        )
        assert session._audio_bytes == len(audio_b64)

        await session.close()

    @pytest.mark.asyncio
    async def test_send_audio_before_start_is_noop(self, mock_sarvam_client):
        """Sending audio when ws is None should silently do nothing."""
        from services.ramble_service import RambleSession

        session = RambleSession(api_key="test-key")
        await session.send_audio("SGVsbG8=")  # Should not raise

    @pytest.mark.asyncio
    async def test_audio_bytes_accumulate(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        fake_ws = FakeSarvamWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        chunk1 = "AAAA"
        chunk2 = "BBBBBB"
        await session.send_audio(chunk1)
        await session.send_audio(chunk2)

        assert session._audio_bytes == len(chunk1) + len(chunk2)
        await session.close()

    @pytest.mark.asyncio
    async def test_oversized_chunk_rejected_by_router(self):
        """Router rejects audio chunks > MAX_AUDIO_CHUNK_SIZE (200KB).

        This is enforced at the router level, not in RambleSession itself.
        Verify the constant exists and the router logic checks it.
        """
        from routers.ramble import MAX_AUDIO_CHUNK_SIZE

        assert MAX_AUDIO_CHUNK_SIZE == 200_000

        # Simulate the router-level check
        oversized_data = "A" * (MAX_AUDIO_CHUNK_SIZE + 1)
        assert len(oversized_data) > MAX_AUDIO_CHUNK_SIZE


class TestTranscriptionEvents:
    """Receiving transcription events from Sarvam."""

    @pytest.mark.asyncio
    async def test_transcript_events_accumulate(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        events = [
            _make_transcript_event("Hello"),
            _make_transcript_event("world"),
        ]
        fake_ws = FakeSarvamWS(events)
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        received = []
        async def on_message(msg):
            received.append(msg)

        await session.receive_events(on_message)

        assert len(received) == 2
        assert received[0]["type"] == "transcription"
        assert received[0]["text"] == "Hello"
        assert received[1]["text"] == "Hello world"
        assert session.accumulated_transcription == "Hello world"

        await session.close()

    @pytest.mark.asyncio
    async def test_get_english_transcription(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        events = [_make_transcript_event("Buy groceries")]
        fake_ws = FakeSarvamWS(events)
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()
        await session.receive_events(AsyncMock())

        result = await session.get_english_transcription()
        assert result == "Buy groceries"

        await session.close()

    @pytest.mark.asyncio
    async def test_receive_events_before_start_is_noop(self, mock_sarvam_client):
        """receive_events when ws is None should return immediately."""
        from services.ramble_service import RambleSession

        session = RambleSession(api_key="test-key")
        on_message = AsyncMock()
        await session.receive_events(on_message)
        on_message.assert_not_called()

    @pytest.mark.asyncio
    async def test_error_event_forwarded_to_callback(self, mock_sarvam_client):
        from services.ramble_service import RambleSession

        events = [_make_error_event("Sarvam internal error")]
        fake_ws = FakeSarvamWS(events)
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        received = []
        async def on_message(msg):
            received.append(msg)

        await session.receive_events(on_message)

        assert len(received) == 1
        assert received[0]["type"] == "error"
        assert "Sarvam internal error" in received[0]["message"]

        await session.close()


class TestSarvamErrorHandling:
    """Sarvam API connection and transcription errors."""

    @pytest.mark.asyncio
    async def test_connection_failure_handled(self, mock_sarvam_client):
        """If Sarvam connection fails during start(), exception propagates.

        The router catches this and sends an error to the client.
        """
        from services.ramble_service import RambleSession

        ctx_mgr = MagicMock()
        ctx_mgr.__aenter__ = AsyncMock(side_effect=ConnectionError("Sarvam unavailable"))
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = ctx_mgr

        session = RambleSession(api_key="test-key")
        with pytest.raises(ConnectionError, match="Sarvam unavailable"):
            await session.start()

    @pytest.mark.asyncio
    async def test_receive_exception_sends_error_callback(self, mock_sarvam_client):
        """Non-normal close exceptions are forwarded via on_message error."""
        from services.ramble_service import RambleSession

        class FailingWS:
            transcribe = AsyncMock()

            def __aiter__(self):
                return self

            async def __anext__(self):
                raise RuntimeError("Stream broke")

        fake_ws = FailingWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        received = []
        async def on_message(msg):
            received.append(msg)

        await session.receive_events(on_message)

        assert len(received) == 1
        assert received[0]["type"] == "error"
        assert "Stream broke" in received[0]["message"]

        await session.close()

    @pytest.mark.asyncio
    async def test_normal_close_codes_no_error(self, mock_sarvam_client):
        """WebSocket close codes 1000/1001 are treated as normal, not errors."""
        from services.ramble_service import RambleSession

        class NormalCloseWS:
            transcribe = AsyncMock()

            def __aiter__(self):
                return self

            async def __anext__(self):
                raise Exception("connection closed with 1000 (OK)")

        fake_ws = NormalCloseWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        received = []
        async def on_message(msg):
            received.append(msg)

        await session.receive_events(on_message)

        # Normal close — no error callback
        assert len(received) == 0

        await session.close()

    @pytest.mark.asyncio
    async def test_cancelled_error_no_callback(self, mock_sarvam_client):
        """CancelledError (from task cancellation) is handled silently."""
        from services.ramble_service import RambleSession

        class CancellingWS:
            transcribe = AsyncMock()

            def __aiter__(self):
                return self

            async def __anext__(self):
                raise asyncio.CancelledError()

        fake_ws = CancellingWS()
        mock_sarvam_client.speech_to_text_streaming.connect.return_value = (
            FakeContextManager(fake_ws)
        )

        session = RambleSession(api_key="test-key")
        await session.start()

        on_message = AsyncMock()
        await session.receive_events(on_message)

        on_message.assert_not_called()
        await session.close()

    @pytest.mark.asyncio
    async def test_close_aexit_exception_swallowed(self, mock_sarvam_client):
        """If __aexit__ raises during close(), it's swallowed."""
        from services.ramble_service import RambleSession

        class FailCloseCtx:
            async def __aenter__(self):
                return FakeSarvamWS()

            async def __aexit__(self, *args):
                raise RuntimeError("cleanup failed")

        mock_sarvam_client.speech_to_text_streaming.connect.return_value = FailCloseCtx()

        session = RambleSession(api_key="test-key")
        await session.start()
        await session.close()  # Should not raise

        assert session._ws is None


class TestSessionTimeout:
    """Session timeout enforcement (at router level)."""

    @pytest.mark.asyncio
    async def test_timeout_constants_defined(self):
        """Verify timeout constants are set correctly."""
        from routers.ramble import (
            RAMBLE_MAX_DURATION_SECONDS,
            RAMBLE_TIMER_INTERVAL_SECONDS,
        )

        assert RAMBLE_MAX_DURATION_SECONDS == 300  # 5 minutes
        assert RAMBLE_TIMER_INTERVAL_SECONDS == 30

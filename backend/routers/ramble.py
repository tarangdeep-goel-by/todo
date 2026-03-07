"""WebSocket router for ramble streaming mode (transcription-only)."""
import asyncio
import json
import time
import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.ramble_service import RambleSession
from config import get_settings
from auth import _init_firebase
from structured_logging import get_logger, trace_id_var, user_id_var, session_id_var

logger = get_logger(__name__)
router = APIRouter(tags=["ramble"])

# Maximum session duration in seconds
RAMBLE_MAX_DURATION_SECONDS = 300  # 5 minutes
RAMBLE_TIMER_INTERVAL_SECONDS = 30

# WebSocket security limits
MAX_MESSAGE_SIZE = 262_144  # 256 KB per message
MAX_AUDIO_CHUNK_SIZE = 200_000  # ~5 seconds at 16kHz base64
VALID_MSG_TYPES = {"start", "audio", "stop"}

# Auth timeout for first message
WS_AUTH_TIMEOUT_SECONDS = 5

# Per-user active WebSocket connection tracking
_active_connections: dict[str, int] = {}
_connections_lock = asyncio.Lock()


class _BandwidthTracker:
    """Per-connection bandwidth limiter (sliding window)."""

    def __init__(self, max_bytes_per_second: int = 512_000):
        self.max_bps = max_bytes_per_second
        self.bytes_this_window = 0
        self.window_start = time.monotonic()

    def check(self, msg_size: int) -> bool:
        """Return True if message is within rate limit, False if exceeded."""
        now = time.monotonic()
        if now - self.window_start >= 1.0:
            self.bytes_this_window = 0
            self.window_start = now
        if self.bytes_this_window + msg_size > self.max_bps:
            return False
        self.bytes_this_window += msg_size
        return True


@router.websocket("/ws/ramble")
async def ramble_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for streaming ramble mode (transcription-only).

    Auth: Send {"type": "auth", "token": "<firebase_id_token>"} as first message.
    Server responds with {"type": "auth_ok"} or closes with 4001.

    Client->Server messages (JSON):
      {"type": "auth", "token": "<firebase_id_token>"}  (MUST be first message)
      {"type": "start"}
      {"type": "audio", "data": "<base64 PCM 16kHz mono>"}
      {"type": "stop"}

    Server->Client messages (JSON):
      {"type": "auth_ok"}
      {"type": "transcription", "text": "..."}
      {"type": "final_transcript", "text": "..."}
      {"type": "status", "status": "connected"|"closed"}
      {"type": "error", "message": "..."}
    """
    await websocket.accept()

    user_uid = None

    # Wait for auth message as first message
    try:
        raw = await asyncio.wait_for(
            websocket.receive_text(), timeout=WS_AUTH_TIMEOUT_SECONDS
        )
        msg = json.loads(raw)
        if msg.get("type") != "auth" or "token" not in msg:
            await websocket.send_json({"type": "auth_error", "message": "Expected auth message"})
            await websocket.close(code=4001, reason="Invalid auth message")
            return
    except asyncio.TimeoutError:
        await websocket.close(code=4008, reason="Auth timeout")
        return
    except (json.JSONDecodeError, Exception):
        await websocket.close(code=4001, reason="Invalid auth message")
        return

    # Verify token
    settings = get_settings()
    token = msg["token"]
    if token == "test-token-e2e":
        if settings.app_env != "test":
            logger.error("ws.test_token_rejected", app_env=settings.app_env)
            await websocket.close(code=4001, reason="Invalid token")
            return
        user_uid = "test-user-e2e"
        logger.warning("ws.test_token_used", uid=user_uid)
    else:
        _init_firebase()
        try:
            from firebase_admin import auth as firebase_auth
            loop = asyncio.get_running_loop()
            decoded = await loop.run_in_executor(
                None, firebase_auth.verify_id_token, token
            )
            user_uid = decoded.get("uid", "unknown")
        except Exception as e:
            logger.warning("ws.auth_failed", reason=str(e))
            await websocket.send_json({"type": "auth_error", "message": "Authentication failed"})
            await websocket.close(code=4001, reason="Authentication failed")
            return

    await websocket.send_json({"type": "auth_ok"})

    # Check per-user connection limit
    settings = get_settings()
    async with _connections_lock:
        current = _active_connections.get(user_uid, 0)
        if current >= settings.max_ws_connections_per_user:
            await websocket.send_json({
                "type": "error",
                "message": "Too many active connections"
            })
            await websocket.close(code=4009, reason="Connection limit exceeded")
            return
        _active_connections[user_uid] = current + 1

    bandwidth = _BandwidthTracker()

    trace_id_var.set(str(uuid.uuid4()))
    user_id_var.set(user_uid)
    logger.info("ws.connect")
    session: RambleSession | None = None
    receive_task: asyncio.Task | None = None
    timer_task: asyncio.Task | None = None
    session_expired = asyncio.Event()

    async def send_to_client(msg: dict):
        try:
            await websocket.send_json(msg)
        except Exception as e:
            logger.error("ws.error", reason=str(e))

    async def session_timer(start_time: float):
        """Send time_remaining every 30s, set expired event at 0."""
        try:
            while True:
                await asyncio.sleep(RAMBLE_TIMER_INTERVAL_SECONDS)
                elapsed = time.monotonic() - start_time
                remaining = max(0, RAMBLE_MAX_DURATION_SECONDS - int(elapsed))
                await send_to_client({
                    "type": "status",
                    "status": "time_remaining",
                    "seconds": remaining,
                })
                logger.info("ramble.timer", seconds_remaining=remaining)
                if remaining <= 0:
                    session_expired.set()
                    return
        except asyncio.CancelledError:
            pass

    try:
        while True:
            # Check if session expired (timer ran out)
            if session_expired.is_set():
                logger.info("ramble.stop", reason="timeout")
                break

            raw = await websocket.receive_text()

            # Bandwidth throttling
            if not bandwidth.check(len(raw)):
                logger.warning("ws.bandwidth_exceeded", user_id=user_uid)
                await send_to_client({"type": "error", "message": "Rate limit exceeded"})
                await websocket.close(code=4029, reason="Bandwidth limit exceeded")
                break

            # Validate message size
            if len(raw) > MAX_MESSAGE_SIZE:
                await send_to_client({"type": "error", "message": "Message too large"})
                continue

            # Parse JSON safely
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await send_to_client({"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type")

            # Validate message type
            if msg_type not in VALID_MSG_TYPES:
                await send_to_client({"type": "error", "message": "Invalid message type"})
                continue

            logger.debug("ws.message", msg_type=msg_type)

            if msg_type == "start":
                session = RambleSession(
                    api_key=settings.sarvam_api_key,
                )
                try:
                    await session.start()
                    logger.info("ramble.start")
                except Exception as e:
                    logger.error("ramble.stt.error", reason=str(e), exc_info=True)
                    await send_to_client({"type": "error", "message": "Transcription service unavailable"})
                    break

                receive_task = asyncio.create_task(
                    session.receive_events(send_to_client)
                )
                timer_task = asyncio.create_task(
                    session_timer(time.monotonic())
                )

                await send_to_client({"type": "status", "status": "connected"})

            elif msg_type == "audio":
                if session:
                    data = msg.get("data", "")
                    if not isinstance(data, str) or len(data) > MAX_AUDIO_CHUNK_SIZE:
                        await send_to_client({"type": "error", "message": "Audio chunk too large"})
                        continue
                    try:
                        await session.send_audio(data)
                    except Exception as e:
                        logger.error("ramble.stt.chunk.error", reason=str(e))
                        await send_to_client({"type": "error", "message": "Audio processing failed"})

            elif msg_type == "stop":
                logger.info("ramble.stop", reason="user")
                if receive_task:
                    receive_task.cancel()
                    try:
                        await receive_task
                    except asyncio.CancelledError:
                        pass
                    receive_task = None
                if session:
                    # Transliterate to English if needed, then send
                    transcript = await session.get_english_transcription()
                    logger.info("ramble.transcript", length=len(transcript))
                    if transcript:
                        await send_to_client({
                            "type": "final_transcript",
                            "text": transcript,
                        })
                    await session.close()
                    session = None
                await send_to_client({"type": "status", "status": "closed"})
                break

    except WebSocketDisconnect:
        logger.info("ws.disconnect", reason="client")
    except Exception as e:
        logger.error("ws.error", reason=str(e), exc_info=True)
        await send_to_client({"type": "error", "message": "An unexpected error occurred"})
    finally:
        # On timeout: send final transcript before closing
        if session_expired.is_set() and session:
            if receive_task:
                receive_task.cancel()
                try:
                    await receive_task
                except asyncio.CancelledError:
                    pass
                receive_task = None
            transcript = await session.get_english_transcription()
            if transcript:
                await send_to_client({
                    "type": "final_transcript",
                    "text": transcript,
                })
            await send_to_client({"type": "status", "status": "timeout"})

        if timer_task:
            timer_task.cancel()
        if session:
            await session.close()
        if receive_task:
            receive_task.cancel()
        # Decrement active connection count
        if user_uid is not None:
            async with _connections_lock:
                count = _active_connections.get(user_uid, 1) - 1
                if count <= 0:
                    _active_connections.pop(user_uid, None)
                else:
                    _active_connections[user_uid] = count
        logger.info("ws.disconnect", reason="cleanup")

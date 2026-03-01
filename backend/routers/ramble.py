"""WebSocket router for ramble streaming mode (transcription-only)."""
import asyncio
import json
import logging
import time

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.ramble_service import RambleSession
from config import get_settings

logger = logging.getLogger(__name__)
router = APIRouter(tags=["ramble"])

# Maximum session duration in seconds
RAMBLE_MAX_DURATION_SECONDS = 300  # 5 minutes
RAMBLE_TIMER_INTERVAL_SECONDS = 30


@router.websocket("/ws/ramble")
async def ramble_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for streaming ramble mode (transcription-only).

    Client→Server messages (JSON):
      {"type": "start", "user_id": "..."}
      {"type": "audio", "data": "<base64 PCM 16kHz mono>"}
      {"type": "stop"}

    Server→Client messages (JSON):
      {"type": "transcription", "text": "..."}
      {"type": "final_transcript", "text": "..."}
      {"type": "status", "status": "connected"|"closed"}
      {"type": "error", "message": "..."}
    """
    await websocket.accept()
    logger.info("[Ramble WS] Connection accepted")
    settings = get_settings()
    session: RambleSession | None = None
    receive_task: asyncio.Task | None = None
    timer_task: asyncio.Task | None = None
    session_expired = asyncio.Event()

    async def send_to_client(msg: dict):
        try:
            await websocket.send_json(msg)
        except Exception as e:
            logger.error("[Ramble WS] Failed to send to client: %s", e)

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
                logger.info("[Ramble WS] Time remaining: %ds", remaining)
                if remaining <= 0:
                    session_expired.set()
                    return
        except asyncio.CancelledError:
            pass

    try:
        while True:
            # Check if session expired (timer ran out)
            if session_expired.is_set():
                logger.info("[Ramble WS] Session expired, auto-stopping")
                break

            raw = await websocket.receive_text()
            msg = json.loads(raw)
            msg_type = msg.get("type")
            logger.info("[Ramble WS] ← %s", msg_type)

            if msg_type == "start":
                session = RambleSession(
                    api_key=settings.gemini_api_key,
                )
                try:
                    await session.start()
                    logger.info("[Ramble WS] Gemini session started")
                except Exception as e:
                    logger.error("[Ramble WS] Failed to start Gemini session: %s", e, exc_info=True)
                    await send_to_client({"type": "error", "message": f"Gemini session failed: {e}"})
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
                    try:
                        await session.send_audio(msg["data"])
                    except Exception as e:
                        logger.error("[Ramble WS] Failed to send audio: %s", e)
                        await send_to_client({"type": "error", "message": f"Audio send failed: {e}"})

            elif msg_type == "stop":
                logger.info("[Ramble WS] Stop requested")
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
                    print(f"[Ramble WS] Final transcript: '{transcript}'")
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
        logger.info("[Ramble WS] Client disconnected")
    except Exception as e:
        logger.error("[Ramble WS] Unexpected error: %s", e, exc_info=True)
        await send_to_client({"type": "error", "message": str(e)})
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
        logger.info("[Ramble WS] Cleanup done")

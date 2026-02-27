"""WebSocket router for ramble streaming mode (transcription-only)."""
import asyncio
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.ramble_service import RambleSession
from config import get_settings

logger = logging.getLogger(__name__)
router = APIRouter(tags=["ramble"])


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

    async def send_to_client(msg: dict):
        try:
            await websocket.send_json(msg)
        except Exception as e:
            logger.error("[Ramble WS] Failed to send to client: %s", e)

    try:
        while True:
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
        if session:
            await session.close()
        if receive_task:
            receive_task.cancel()
        logger.info("[Ramble WS] Cleanup done")

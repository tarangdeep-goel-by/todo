"""Ramble mode service — streams audio to Sarvam AI for transcription."""
import asyncio
import logging
from typing import Callable

from sarvamai import AsyncSarvamAI

logger = logging.getLogger(__name__)


class RambleSession:
    """Manages one Sarvam AI streaming STT session for ramble mode."""

    def __init__(self, api_key: str):
        self._client = AsyncSarvamAI(api_subscription_key=api_key)
        self._ws = None
        self._context_manager = None
        self._accumulated_transcription: str = ""

    async def start(self) -> None:
        """Open Sarvam streaming STT connection in translate mode (→ English)."""
        logger.info("Opening Sarvam streaming STT session...")
        self._context_manager = self._client.speech_to_text_streaming.connect(
            model="saaras:v3",
            mode="translate",
            language_code="en-IN",
            sample_rate="16000",
            input_audio_codec="pcm_s16le",
        )
        self._ws = await self._context_manager.__aenter__()
        logger.info("Sarvam streaming STT session opened successfully")

    async def send_audio(self, pcm_base64: str) -> None:
        """Send a chunk of base64-encoded 16kHz PCM audio."""
        if not self._ws:
            return
        await self._ws.transcribe(
            audio=pcm_base64,
            encoding="audio/wav",
            sample_rate=16000,
        )

    async def receive_events(self, on_message: Callable) -> None:
        """Listen for Sarvam streaming events. Calls on_message(dict) for each."""
        if not self._ws:
            return
        logger.info("Starting receive loop")
        try:
            async for message in self._ws:
                # SpeechToTextStreamingResponse: .type = "data"|"error"|"events"
                # For "data": .data is SpeechToTextTranscriptionData with .transcript
                logger.debug("Sarvam event: type=%s", getattr(message, "type", "?"))
                if getattr(message, "type", None) == "data" and hasattr(message, "data"):
                    transcript = getattr(message.data, "transcript", None)
                    if transcript:
                        self._accumulated_transcription += " " + transcript
                        logger.debug("Transcription chunk: %s", transcript[:200])
                        await on_message({
                            "type": "transcription",
                            "text": self._accumulated_transcription.strip(),
                        })
                elif getattr(message, "type", None) == "error":
                    err_msg = str(getattr(message, "data", message))
                    logger.error("Sarvam error event: %s", err_msg)
                    await on_message({"type": "error", "message": err_msg})

            logger.info("Receive loop ended normally")
        except asyncio.CancelledError:
            logger.info("Receive loop cancelled")
        except Exception as e:
            err_str = str(e)
            if "1000 (OK)" in err_str or "1001" in err_str:
                logger.info("Receive loop closed normally")
            else:
                logger.error("Receive loop error: %s", e)
                await on_message({"type": "error", "message": err_str})

    async def close(self) -> None:
        """Close the Sarvam streaming connection."""
        if self._context_manager and self._ws:
            try:
                await self._context_manager.__aexit__(None, None, None)
            except Exception:
                pass
        self._ws = None
        self._context_manager = None

    @property
    def accumulated_transcription(self) -> str:
        return self._accumulated_transcription.strip()

    async def get_english_transcription(self) -> str:
        """Return accumulated transcription (already English via translate mode)."""
        return self._accumulated_transcription.strip()

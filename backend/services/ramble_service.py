"""Ramble mode service — streams audio to Sarvam AI for transcription."""
import asyncio
import time
from typing import Callable

from sarvamai import AsyncSarvamAI
from structured_logging import get_logger

logger = get_logger(__name__)


class RambleSession:
    """Manages one Sarvam AI streaming STT session for ramble mode."""

    def __init__(self, api_key: str):
        self._client = AsyncSarvamAI(api_subscription_key=api_key)
        self._ws = None
        self._context_manager = None
        self._accumulated_transcription: str = ""
        self._session_start: float | None = None
        self._audio_bytes: int = 0
        self._first_transcript_at: float | None = None

    async def start(self) -> None:
        """Open Sarvam streaming STT connection in translate mode (→ English)."""
        logger.info("ramble.stt.open")
        self._context_manager = self._client.speech_to_text_streaming.connect(
            model="saaras:v3",
            mode="translate",
            language_code="en-IN",
            sample_rate="16000",
            input_audio_codec="pcm_s16le",
        )
        self._ws = await self._context_manager.__aenter__()
        self._session_start = time.monotonic()
        logger.info("ramble.stt.open.done")

    async def send_audio(self, pcm_base64: str) -> None:
        """Send a chunk of base64-encoded 16kHz PCM audio."""
        if not self._ws:
            return
        self._audio_bytes += len(pcm_base64)
        await self._ws.transcribe(
            audio=pcm_base64,
            encoding="audio/wav",
            sample_rate=16000,
        )

    async def receive_events(self, on_message: Callable) -> None:
        """Listen for Sarvam streaming events. Calls on_message(dict) for each."""
        if not self._ws:
            return
        logger.debug("ramble.stt.receive_start")
        try:
            async for message in self._ws:
                # SpeechToTextStreamingResponse: .type = "data"|"error"|"events"
                # For "data": .data is SpeechToTextTranscriptionData with .transcript
                logger.debug("ramble.stt.event", event_type=getattr(message, "type", "?"))
                if getattr(message, "type", None) == "data" and hasattr(message, "data"):
                    transcript = getattr(message.data, "transcript", None)
                    if transcript:
                        if self._first_transcript_at is None and self._session_start:
                            self._first_transcript_at = time.monotonic()
                            ttft_ms = round((self._first_transcript_at - self._session_start) * 1000, 1)
                            logger.info("sarvam.api.ttft", time_to_first_transcript_ms=ttft_ms)
                        self._accumulated_transcription += " " + transcript
                        logger.debug("ramble.stt.chunk", length=len(transcript))
                        await on_message({
                            "type": "transcription",
                            "text": self._accumulated_transcription.strip(),
                        })
                elif getattr(message, "type", None) == "error":
                    err_msg = str(getattr(message, "data", message))
                    logger.error("ramble.stt.error", message=err_msg)
                    await on_message({"type": "error", "message": err_msg})

            logger.info("ramble.stt.close")
        except asyncio.CancelledError:
            logger.info("ramble.stt.close", reason="cancelled")
        except Exception as e:
            err_str = str(e)
            if "1000 (OK)" in err_str or "1001" in err_str:
                logger.info("ramble.stt.close", reason="normal")
            else:
                logger.error("ramble.stt.error", error=str(e))
                await on_message({"type": "error", "message": err_str})

    async def close(self) -> None:
        """Close the Sarvam streaming connection and log session metrics."""
        if self._session_start:
            duration_s = round(time.monotonic() - self._session_start, 1)
            logger.info("sarvam.api.session", duration_s=duration_s,
                        audio_bytes=self._audio_bytes,
                        transcript_length=len(self._accumulated_transcription.strip()))
        if self._context_manager and self._ws:
            try:
                await self._context_manager.__aexit__(None, None, None)
            except Exception as e:
                logger.debug("ramble.cleanup_error", error=str(e))
        self._ws = None
        self._context_manager = None

    @property
    def accumulated_transcription(self) -> str:
        return self._accumulated_transcription.strip()

    async def get_english_transcription(self) -> str:
        """Return accumulated transcription (already English via translate mode)."""
        return self._accumulated_transcription.strip()

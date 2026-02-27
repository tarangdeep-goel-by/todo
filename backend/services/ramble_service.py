"""Ramble mode service — streams audio to Gemini Live API for transcription."""
import asyncio
import base64
import logging
from typing import Callable

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)


class RambleSession:
    """Manages one Gemini Live API session for transcription-only ramble mode."""

    def __init__(self, api_key: str):
        self.client = genai.Client(api_key=api_key)
        self._api_key = api_key
        self._session = None
        self._context_manager = None
        self._accumulated_transcription: str = ""

    async def start(self) -> None:
        """Open Gemini Live API session with input audio transcription."""
        config = types.LiveConnectConfig(
            responseModalities=[types.Modality.AUDIO],
            input_audio_transcription=types.AudioTranscriptionConfig(),
            realtime_input_config=types.RealtimeInputConfig(
                automatic_activity_detection=types.AutomaticActivityDetection(
                    start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
                    end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_LOW,
                    silence_duration_ms=10000,
                ),
            ),
            systemInstruction=types.Content(
                parts=[types.Part(text="You are a silent listener. Do not respond.")]
            ),
        )

        print("[Ramble] Opening Gemini Live session...")
        self._context_manager = self.client.aio.live.connect(
            model="gemini-2.5-flash-native-audio-latest",
            config=config,
        )
        self._session = await self._context_manager.__aenter__()
        print("[Ramble] Gemini Live session opened successfully")

    async def send_audio(self, pcm_base64: str) -> None:
        """Send a chunk of base64-encoded 16kHz PCM audio."""
        if not self._session:
            return
        audio_bytes = base64.b64decode(pcm_base64)
        await self._session.send(
            input=types.LiveClientRealtimeInput(
                mediaChunks=[types.Blob(data=audio_bytes, mimeType="audio/pcm;rate=16000")]
            )
        )

    async def receive_events(self, on_message: Callable) -> None:
        """Listen for Gemini Live API events. Calls on_message(dict) for each."""
        if not self._session:
            return
        print("[Ramble] Starting receive loop")
        try:
            async for event in self._session.receive():
                if not event.server_content:
                    continue

                # Input transcription (auto-detected language/script)
                if event.server_content.input_transcription:
                    text = event.server_content.input_transcription.text
                    if text:
                        self._accumulated_transcription += text
                        print(f"[Ramble] Input transcription chunk: {text[:200]}")
                        await on_message({
                            "type": "transcription",
                            "text": self._accumulated_transcription,
                        })

            print("[Ramble] Receive loop ended normally")
        except asyncio.CancelledError:
            print("[Ramble] Receive loop cancelled")
        except Exception as e:
            err_str = str(e)
            if "1000 (OK)" in err_str or "1001" in err_str:
                print("[Ramble] Receive loop closed normally")
            else:
                print(f"[Ramble] Receive loop error: {e}")
                await on_message({"type": "error", "message": err_str})

    async def close(self) -> None:
        """Close the Gemini Live session."""
        if self._context_manager and self._session:
            try:
                await self._context_manager.__aexit__(None, None, None)
            except Exception:
                pass
        self._session = None
        self._context_manager = None

    @property
    def accumulated_transcription(self) -> str:
        return self._accumulated_transcription.strip()

    async def get_english_transcription(self) -> str:
        """Transliterate accumulated transcription to English via Gemini text API."""
        raw = self._accumulated_transcription.strip()
        if not raw:
            return ""

        # If already Latin script, return as-is
        if all(ord(c) < 256 or c in ' \n\t' for c in raw):
            print(f"[Ramble] Transcript already Latin: {raw[:100]}")
            return raw

        print(f"[Ramble] Transliterating to English: {raw[:100]}...")
        try:
            response = self.client.models.generate_content(
                model="gemini-2.5-flash-lite",
                contents=f"Transliterate the following text to English using Latin alphabet ONLY. "
                         f"Output ONLY the transliterated text, nothing else. No quotes, no explanation.\n\n{raw}",
            )
            result = response.text.strip()
            print(f"[Ramble] Transliterated: {result[:200]}")
            return result
        except Exception as e:
            print(f"[Ramble] Transliteration failed: {e}, returning raw")
            return raw

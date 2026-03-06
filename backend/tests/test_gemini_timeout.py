"""Tests for Gemini API timeout handling."""
import asyncio
import pytest
from unittest.mock import AsyncMock, patch, MagicMock

from services.gemini_service import GeminiService


@pytest.fixture
def gemini_service():
    """GeminiService with a mocked client."""
    service = GeminiService.__new__(GeminiService)
    service.client = MagicMock()
    return service


class TestDetectBrainDumpTimeout:
    """Timeout handling for detect_brain_dump."""

    @pytest.mark.asyncio
    async def test_timeout_returns_empty_list(self, gemini_service):
        """When Gemini exceeds timeout, return [] gracefully."""
        async def slow_response(*args, **kwargs):
            await asyncio.sleep(100)

        gemini_service.client.aio.models.generate_content = slow_response

        with patch("services.gemini_service.get_settings") as mock_settings:
            mock_settings.return_value.gemini_timeout_seconds = 0.1
            result = await gemini_service.detect_brain_dump("buy groceries", "")

        assert result == []

    @pytest.mark.asyncio
    async def test_timeout_does_not_raise(self, gemini_service):
        """Timeout is handled gracefully — no exception propagates."""
        async def slow_response(*args, **kwargs):
            await asyncio.sleep(100)

        gemini_service.client.aio.models.generate_content = slow_response

        with patch("services.gemini_service.get_settings") as mock_settings:
            mock_settings.return_value.gemini_timeout_seconds = 0.1
            # Should not raise — returns [] instead
            result = await gemini_service.detect_brain_dump("test input", "tree context")

        assert result == []

    @pytest.mark.asyncio
    async def test_completes_within_timeout(self, gemini_service):
        """Normal response within timeout returns parsed result."""
        mock_response = MagicMock()
        mock_response.text = '[{"action":"add","content":"Buy groceries","category":"home","confidence":0.9}]'

        async def fast_response(*args, **kwargs):
            return mock_response

        gemini_service.client.aio.models.generate_content = fast_response

        with patch("services.gemini_service.get_settings") as mock_settings:
            mock_settings.return_value.gemini_timeout_seconds = 10
            result = await gemini_service.detect_brain_dump("buy groceries", "")

        assert len(result) == 1
        assert result[0]["content"] == "Buy groceries"


class TestGenerateSubtasksTimeout:
    """Timeout handling for generate_subtasks."""

    @pytest.mark.asyncio
    async def test_timeout_returns_empty_list(self, gemini_service):
        """When Gemini exceeds timeout, return [] gracefully."""
        async def slow_response(*args, **kwargs):
            await asyncio.sleep(100)

        gemini_service.client.aio.models.generate_content = slow_response

        with patch("services.gemini_service.get_settings") as mock_settings:
            mock_settings.return_value.gemini_subtask_timeout_seconds = 0.1
            result = await gemini_service.generate_subtasks("Build feature X")

        assert result == []

    @pytest.mark.asyncio
    async def test_completes_within_timeout(self, gemini_service):
        """Normal response within timeout returns subtask list."""
        mock_response = MagicMock()
        mock_response.text = '["Research", "Design", "Implement", "Test"]'

        async def fast_response(*args, **kwargs):
            return mock_response

        gemini_service.client.aio.models.generate_content = fast_response

        with patch("services.gemini_service.get_settings") as mock_settings:
            mock_settings.return_value.gemini_subtask_timeout_seconds = 10
            result = await gemini_service.generate_subtasks("Build feature X")

        assert result == ["Research", "Design", "Implement", "Test"]

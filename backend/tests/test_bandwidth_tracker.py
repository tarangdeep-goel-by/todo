"""Tests for WebSocket bandwidth throttling."""
import time
from unittest.mock import patch
from routers.ramble import _BandwidthTracker


class TestBandwidthTracker:
    """Unit tests for the per-connection bandwidth limiter."""

    def test_allows_message_within_limit(self):
        """A single message under the limit should be allowed."""
        tracker = _BandwidthTracker(max_bytes_per_second=1000)
        assert tracker.check(500) is True

    def test_allows_multiple_messages_within_limit(self):
        """Multiple messages totaling under the limit should be allowed."""
        tracker = _BandwidthTracker(max_bytes_per_second=1000)
        assert tracker.check(300) is True
        assert tracker.check(300) is True
        assert tracker.check(300) is True

    def test_rejects_message_exceeding_limit(self):
        """Message that would push total over limit should be rejected."""
        tracker = _BandwidthTracker(max_bytes_per_second=1000)
        assert tracker.check(600) is True
        assert tracker.check(600) is False  # 1200 > 1000

    def test_rejects_single_message_over_limit(self):
        """A single message larger than the limit should be rejected."""
        tracker = _BandwidthTracker(max_bytes_per_second=1000)
        assert tracker.check(1500) is False

    def test_window_resets_after_one_second(self):
        """After 1 second, the byte counter should reset."""
        tracker = _BandwidthTracker(max_bytes_per_second=1000)
        assert tracker.check(900) is True
        assert tracker.check(200) is False  # Over limit

        # Simulate 1 second passing
        tracker.window_start = time.monotonic() - 1.1
        assert tracker.check(900) is True  # Window reset

    def test_default_limit_is_512kb(self):
        """Default max_bytes_per_second should be 512000."""
        tracker = _BandwidthTracker()
        assert tracker.max_bps == 512_000

    def test_zero_size_message_allowed(self):
        """Zero-byte messages should always be allowed."""
        tracker = _BandwidthTracker(max_bytes_per_second=100)
        assert tracker.check(0) is True

    def test_cumulative_tracking(self):
        """Bytes should accumulate within the same window."""
        tracker = _BandwidthTracker(max_bytes_per_second=100)
        for _ in range(10):
            assert tracker.check(10) is True  # 10 * 10 = 100, at limit
        assert tracker.check(1) is False  # 101 > 100

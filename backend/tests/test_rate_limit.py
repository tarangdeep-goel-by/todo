"""Tests for rate limit key extraction logic."""
import pytest
from unittest.mock import MagicMock, patch


class _HeadersDict(dict):
    """Dict subclass that allows attribute assignment for mocking."""
    pass


def _make_request(auth_header=None, xff=None, client_host="1.2.3.4"):
    """Create a mock Request with optional headers and client."""
    req = MagicMock()
    headers = _HeadersDict()
    if auth_header:
        headers["Authorization"] = auth_header
    if xff:
        headers["X-Forwarded-For"] = xff
    req.headers = headers
    if client_host:
        req.client.host = client_host
    else:
        req.client = None
    return req


def _make_settings(trusted_proxy_count=0):
    """Create a mock Settings with given trusted_proxy_count."""
    s = MagicMock()
    s.trusted_proxy_count = trusted_proxy_count
    return s


class TestRateLimitKey:
    """Rate limit key extraction tests."""

    @patch("rate_limit.get_settings")
    def test_bearer_token_takes_priority(self, mock_settings):
        """Bearer token is used as key even when XFF is present."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=1)
        req = _make_request(
            auth_header="Bearer my-token-123",
            xff="10.0.0.1, 172.16.0.1",
            client_host="192.168.1.1",
        )
        assert _rate_limit_key(req) == "my-token-123"

    @patch("rate_limit.get_settings")
    def test_no_auth_falls_back_to_client_host(self, mock_settings):
        """Without auth header, client.host is used."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=0)
        req = _make_request(client_host="9.8.7.6")
        assert _rate_limit_key(req) == "9.8.7.6"

    @patch("rate_limit.get_settings")
    def test_trusted_proxy_count_zero_ignores_xff(self, mock_settings):
        """With trusted_proxy_count=0, XFF header is ignored."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=0)
        req = _make_request(xff="10.0.0.1, 172.16.0.1", client_host="192.168.1.1")
        assert _rate_limit_key(req) == "192.168.1.1"

    @patch("rate_limit.get_settings")
    def test_trusted_proxy_count_1_takes_last_xff(self, mock_settings):
        """With trusted_proxy_count=1, last XFF entry is used."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=1)
        req = _make_request(xff="10.0.0.1, 172.16.0.1", client_host="192.168.1.1")
        assert _rate_limit_key(req) == "172.16.0.1"

    @patch("rate_limit.get_settings")
    def test_trusted_proxy_count_2_takes_second_to_last_xff(self, mock_settings):
        """With trusted_proxy_count=2, second-to-last XFF entry is used."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=2)
        req = _make_request(
            xff="203.0.113.1, 10.0.0.1, 172.16.0.1",
            client_host="192.168.1.1",
        )
        assert _rate_limit_key(req) == "10.0.0.1"

    @patch("rate_limit.get_settings")
    def test_missing_client_returns_unknown(self, mock_settings):
        """When client is None and no auth, returns 'unknown'."""
        from rate_limit import _rate_limit_key

        mock_settings.return_value = _make_settings(trusted_proxy_count=0)
        req = _make_request(client_host=None)
        assert _rate_limit_key(req) == "unknown"

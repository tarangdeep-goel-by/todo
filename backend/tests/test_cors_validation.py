"""Tests for CORS origin format validation in config.py."""
import pytest
from pydantic import ValidationError
from config import Settings


# Minimal required env vars for Settings construction
_REQUIRED = {
    "DATABASE_URL": "postgresql+asyncpg://u:p@localhost/db",
    "GEMINI_API_KEY": "test-key",
    "SARVAM_API_KEY": "test-key",
}


class TestCorsOriginValidation:
    """Validate CORS origin format checking (field_validator)."""

    def test_valid_http_origin(self, monkeypatch):
        """Valid http:// origin should pass."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "http://localhost:8000")
        s = Settings()
        assert "localhost:8000" in s.cors_origins

    def test_valid_https_origin(self, monkeypatch):
        """Valid https:// origin should pass."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "https://app.example.com")
        s = Settings()
        assert "app.example.com" in s.cors_origins

    def test_valid_multiple_origins(self, monkeypatch):
        """Multiple valid origins separated by commas should pass."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "http://localhost:8000,https://prod.example.com")
        s = Settings()
        assert "localhost:8000" in s.cors_origins
        assert "prod.example.com" in s.cors_origins

    def test_valid_with_trailing_comma(self, monkeypatch):
        """Trailing comma (empty string) should be tolerated."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "http://localhost:8000,")
        s = Settings()
        assert "localhost:8000" in s.cors_origins

    def test_invalid_origin_no_scheme(self, monkeypatch):
        """Origin without http/https scheme should raise ValidationError."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "localhost:8000")
        with pytest.raises(ValidationError, match="must start with http:// or https://"):
            Settings()

    def test_invalid_origin_ftp_scheme(self, monkeypatch):
        """Origin with ftp:// scheme should raise ValidationError."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "ftp://files.example.com")
        with pytest.raises(ValidationError, match="must start with http:// or https://"):
            Settings()

    def test_invalid_origin_empty_host(self, monkeypatch):
        """Origin with scheme but no host should raise ValidationError."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "http://")
        with pytest.raises(ValidationError, match="Malformed CORS origin"):
            Settings()

    def test_invalid_origin_wildcard(self, monkeypatch):
        """Wildcard '*' has no scheme and should fail format validation."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "*")
        with pytest.raises(ValidationError, match="must start with http:// or https://"):
            Settings()

    def test_invalid_mixed_origins(self, monkeypatch):
        """One bad origin among valid ones should raise."""
        for k, v in _REQUIRED.items():
            monkeypatch.setenv(k, v)
        monkeypatch.setenv("CORS_ORIGINS", "http://localhost:8000,badorigin")
        with pytest.raises(ValidationError, match="must start with http:// or https://"):
            Settings()

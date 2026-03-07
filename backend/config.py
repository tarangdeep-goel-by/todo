"""Configuration management using Pydantic settings."""
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, field_validator, model_validator
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = ConfigDict(case_sensitive=False)

    # Database
    database_url: str

    # Gemini API
    gemini_api_key: str

    # Sarvam AI (streaming STT)
    sarvam_api_key: str

    # Application
    app_env: str = "development"
    debug: bool = False

    # Search engine: "fuzzy" (RapidFuzz) or "pg_native" (pg_trgm)
    search_engine: str = "fuzzy"

    # CORS
    cors_origins: str = "http://localhost:8000,http://localhost:8001"

    # Firebase Auth
    firebase_project_id: str = ""
    google_application_credentials: str = ""

    # Logging
    log_level: str = "INFO"

    # Sentry (optional — no-op if not set)
    sentry_dsn: str = ""

    # Redis (optional — memory storage if not set)
    redis_url: str = ""

    # API timeouts (seconds)
    gemini_timeout_seconds: int = 15
    gemini_subtask_timeout_seconds: int = 10
    gemini_max_retries: int = 2

    # Category limits
    max_categories: int = 8

    # Notifications
    notification_check_interval_minutes: int = 15

    # Rate limiting — proxy awareness
    trusted_proxy_count: int = 0

    # WebSocket connection limits
    max_ws_connections_per_user: int = 3

    # Test auth — must be explicitly enabled (never in production)
    allow_test_auth: bool = False

    @field_validator("search_engine")
    @classmethod
    def validate_search_engine(cls, v):
        if v not in ("fuzzy", "pg_native"):
            raise ValueError(f"SEARCH_ENGINE must be 'fuzzy' or 'pg_native', got '{v}'")
        return v

    @model_validator(mode='after')
    def validate_cors_origins(self):
        if self.app_env == "production":
            origins = [o.strip() for o in self.cors_origins.split(",")]
            for origin in origins:
                if origin == "*":
                    raise ValueError("Wildcard CORS origin not allowed in production")
                if "localhost" in origin:
                    raise ValueError(f"localhost CORS origin not allowed in production: {origin}")
        return self


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()

"""Configuration management using Pydantic settings."""
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, field_validator, model_validator
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = ConfigDict(case_sensitive=False)

    # Database
    database_url: str

    @field_validator("database_url")
    @classmethod
    def ensure_asyncpg_scheme(cls, v):
        """Render/Heroku provide postgresql:// but asyncpg needs postgresql+asyncpg://."""
        if v.startswith("postgresql://"):
            v = v.replace("postgresql://", "postgresql+asyncpg://", 1)
        return v

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
    firebase_credentials_json: str = ""  # base64-encoded service account JSON (for Render/Heroku)

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

    # Database pool
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_timeout: int = 30

    # WebSocket connection limits
    max_ws_connections_per_user: int = 3

    # E2E test auth — explicit opt-in, never in production
    allow_test_token: bool = False

    @field_validator("search_engine")
    @classmethod
    def validate_search_engine(cls, v):
        if v not in ("fuzzy", "pg_native"):
            raise ValueError(f"SEARCH_ENGINE must be 'fuzzy' or 'pg_native', got '{v}'")
        return v

    @field_validator("cors_origins")
    @classmethod
    def validate_cors_origin_format(cls, v):
        """Validate each CORS origin is scheme + host [+ port], nothing else."""
        from urllib.parse import urlparse
        origins = [o.strip() for o in v.split(",")]
        for origin in origins:
            if not origin:
                continue  # skip empty strings from trailing commas
            parsed = urlparse(origin)
            if parsed.scheme not in ("http", "https"):
                raise ValueError(f"CORS origin must use http or https scheme, got '{origin}'")
            if not parsed.hostname:
                raise ValueError(f"CORS origin missing hostname: '{origin}'")
            if "*" in parsed.hostname:
                raise ValueError(f"Wildcard hostnames not allowed in CORS origin: '{origin}'")
            if parsed.path and parsed.path != "/":
                raise ValueError(f"CORS origin must not contain a path: '{origin}'")
            if parsed.query or parsed.fragment:
                raise ValueError(f"CORS origin must not contain query or fragment: '{origin}'")
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

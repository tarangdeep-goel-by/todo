"""Configuration management using Pydantic settings."""
from pydantic_settings import BaseSettings
from pydantic import ConfigDict, field_validator
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

    # Category limits
    max_categories: int = 8

    @field_validator("search_engine")
    @classmethod
    def validate_search_engine(cls, v):
        if v not in ("fuzzy", "pg_native"):
            raise ValueError(f"SEARCH_ENGINE must be 'fuzzy' or 'pg_native', got '{v}'")
        return v


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()

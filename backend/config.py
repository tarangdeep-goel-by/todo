"""Configuration management using Pydantic settings."""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database
    database_url: str

    # Gemini API
    gemini_api_key: str

    # Application
    app_env: str = "development"
    debug: bool = True

    class Config:
        # No .env file - all config from Docker environment
        case_sensitive = False


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()

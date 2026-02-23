"""Configuration management using Pydantic settings."""
from pydantic_settings import BaseSettings
from pydantic import ConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = ConfigDict(case_sensitive=False)

    # Database
    database_url: str

    # Gemini API
    gemini_api_key: str

    # Application
    app_env: str = "development"
    debug: bool = True


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance."""
    return Settings()

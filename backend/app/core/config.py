"""Configuración tipada desde variables de entorno y backend/.env (pydantic-settings)."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BACKEND_DIR / ".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "development"

    db_server: str = "localhost"
    db_port: int = 1433
    db_name: str = "RedSolidaria"
    db_driver: str = "ODBC Driver 18 for SQL Server"
    db_trust_server_certificate: str = "yes"
    db_app_user: str = "redsolidaria_app"
    db_app_password: SecretStr = SecretStr("")

    jwt_secret_key: SecretStr = SecretStr("")
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    cors_origins: str = "http://localhost:4200"
    login_max_attempts: int = 5
    login_lock_minutes: int = 15

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @model_validator(mode="after")
    def _validar(self) -> "Settings":
        secreto = self.jwt_secret_key.get_secret_value()
        if len(secreto) < 32:
            raise ValueError(
                "JWT_SECRET_KEY debe tener al menos 32 caracteres. Ejecute setup.ps1 para generarla."
            )
        if self.jwt_algorithm not in {"HS256", "HS384", "HS512"}:
            raise ValueError("JWT_ALGORITHM debe ser HS256, HS384 o HS512.")
        if self.is_production and self.db_trust_server_certificate.lower() == "yes":
            raise ValueError(
                "En producción no se debe usar TrustServerCertificate=yes: instale un certificado confiable."
            )
        if "*" in self.cors_origins_list:
            raise ValueError("CORS_ORIGINS no puede ser '*': liste los orígenes permitidos.")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()

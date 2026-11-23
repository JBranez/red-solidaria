"""Conexión síncrona a SQL Server mediante pyodbc.

- Cuenta de aplicación con mínimo privilegio (solo EXECUTE); jamás sa.
- autocommit=True: cada procedimiento almacenado es la unidad transaccional.
- Una conexión por petición, cerrada al terminar (ver apis/deps.py).
"""
from __future__ import annotations

import logging
from typing import Any

from app.core.config import Settings
from app.core.errors import DatabaseUnavailableError

log = logging.getLogger("redsolidaria.db")


def build_connection_string(settings: Settings) -> str:
    # En ODBC los valores con caracteres especiales van entre llaves; '}' se duplica.
    def llaves(valor: str) -> str:
        return "{" + valor.replace("}", "}}") + "}"

    partes = [
        f"DRIVER={llaves(settings.db_driver)}",
        f"SERVER={settings.db_server},{settings.db_port}",
        f"DATABASE={llaves(settings.db_name)}",
        f"UID={llaves(settings.db_app_user)}",
        f"PWD={llaves(settings.db_app_password.get_secret_value())}",
        "Encrypt=yes",
        f"TrustServerCertificate={settings.db_trust_server_certificate}",
        "Connection Timeout=10",
        "APP=RedSolidaria-API",
    ]
    return ";".join(partes)


def open_connection(settings: Settings) -> Any:
    try:
        import pyodbc  # importación diferida: las pruebas no necesitan el driver
    except ImportError as exc:  # pragma: no cover
        raise DatabaseUnavailableError("El módulo pyodbc no está instalado.") from exc
    try:
        return pyodbc.connect(build_connection_string(settings), autocommit=True, timeout=10)
    except pyodbc.Error as exc:
        log.error("No se pudo abrir la conexión a SQL Server: %s", exc.args[:1])
        raise DatabaseUnavailableError(
            "No se pudo conectar con la base de datos. Verifique que SQL Server esté en ejecución."
        ) from exc

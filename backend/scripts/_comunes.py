"""Utilidades compartidas por los scripts de inicialización (sin dependencias de la aplicación web)."""
from __future__ import annotations

import os
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
DB_DIR = RAIZ / "database"
_IDENTIFICADOR = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,63}$")


def cargar_env() -> dict[str, str]:
    """Lee <raíz>/.env y lo combina con las variables de entorno (estas últimas ganan)."""
    valores: dict[str, str] = {}
    archivo = RAIZ / ".env"
    if archivo.exists():
        for linea in archivo.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            clave, _, valor = linea.partition("=")
            valor = valor.strip()
            if valor[:1] not in ('"', "'"):
                valor = re.split(r"\s+#", valor, maxsplit=1)[0].strip()  # comentario en línea
            valores[clave.strip()] = valor.strip('"').strip("'")
    valores.update({k: v for k, v in os.environ.items() if v != ""})
    return valores


def validar_identificador(valor: str, nombre: str) -> str:
    if not _IDENTIFICADOR.match(valor or ""):
        raise ValueError(f"{nombre} solo puede contener letras, números y guion bajo (máx. 64): {valor!r}")
    return valor


def escapar_literal(valor: str) -> str:
    """Para valores que van dentro de N'...' en DDL (CREATE LOGIN no admite parámetros)."""
    if any(c in valor for c in "\r\n\x00") or "$(" in valor:
        raise ValueError("El valor contiene caracteres no permitidos.")
    return valor.replace("'", "''")


def sustituir_variables(sql: str, variables: dict[str, str]) -> str:
    """Sustituye $(NOMBRE) como lo hace sqlcmd. Falla si queda alguna sin resolver."""
    for nombre, valor in variables.items():
        sql = sql.replace(f"$({nombre})", valor)
    pendiente = re.search(r"\$\((\w+)\)", sql)
    if pendiente:
        raise ValueError(f"Variable SQL sin definir: $({pendiente.group(1)})")
    return sql


def dividir_lotes(sql: str) -> list[str]:
    """Divide un script en lotes por líneas GO (SSMS y sqlcmd lo hacen igual; pyodbc no entiende GO)."""
    return [b.strip() for b in re.split(r"^\s*GO\s*$", sql, flags=re.M | re.I) if b.strip()]


def cadena_admin(cfg: dict[str, str], base: str = "master") -> str:
    """Conexión administrativa: usuario/contraseña SQL si hay MSSQL_SA_PASSWORD; si no, autenticación de Windows."""
    def llaves(v: str) -> str:
        return "{" + v.replace("}", "}}") + "}"

    auth = (f"UID={llaves(cfg.get('MSSQL_SA_USER', 'sa'))};PWD={llaves(cfg['MSSQL_SA_PASSWORD'])}"
            if cfg.get("MSSQL_SA_PASSWORD") else "Trusted_Connection=yes")
    return ";".join([
        f"DRIVER={llaves(cfg.get('DB_DRIVER', 'ODBC Driver 18 for SQL Server'))}",
        f"SERVER={cfg.get('DB_SERVER', 'localhost')},{cfg.get('DB_PORT', '1433')}",
        f"DATABASE={base}", auth, "Encrypt=yes",
        f"TrustServerCertificate={cfg.get('DB_TRUST_SERVER_CERTIFICATE', 'yes')}", "Connection Timeout=15",
    ])


def conectar_admin(cfg: dict[str, str], base: str = "master", autocommit: bool = True):
    import pyodbc  # importación diferida

    try:
        return pyodbc.connect(cadena_admin(cfg, base), autocommit=autocommit, timeout=15)
    except pyodbc.Error as exc:
        raise SystemExit(
            "No se pudo conectar a SQL Server con la cuenta administrativa.\n"
            "  · Verifique que el servicio esté en ejecución y que TCP/IP esté habilitado en el puerto indicado.\n"
            "  · Sin MSSQL_SA_PASSWORD se usa autenticación de Windows (su usuario debe ser sysadmin).\n"
            f"  Detalle del driver: {str(exc.args[-1])[:200]}"
        ) from exc

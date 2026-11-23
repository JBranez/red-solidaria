"""Único punto de la aplicación que ejecuta procedimientos almacenados.

- Solo procedimientos `dbo.usp_*`: nada de SQL embebido en repositorios o servicios.
- Parámetros SIEMPRE enlazados con `?` y nombrados (@nombre = ?): no hay concatenación → sin inyección SQL.
- Errores de SQL Server traducidos a excepciones de dominio (sin filtrar detalles internos).
"""
from __future__ import annotations

import logging
import re
from typing import Any, Callable

from app.core.errors import (
    AppError,
    BusinessRuleError,
    ConfirmationRequiredError,
    ConflictError,
    DatabaseUnavailableError,
    ForbiddenError,
    NotFoundError,
)

log = logging.getLogger("redsolidaria.db")

_PROC = re.compile(r"usp_[a-z0-9_]+")
_PARAM = re.compile(r"[a-z][a-z0-9_]*")
_MSG = re.compile(r"\[SQL Server\](?P<msg>.*?)\s*\((?P<num>\d+)\)\s*(?:\(SQL\w+\))?\s*$", re.S)
_SQLSTATE_CONEXION = {"08001", "08S01", "08004", "HYT00", "HYT01", "28000"}


def parse_sql_error(texto: str) -> tuple[int | None, str]:
    """Extrae (número de error, mensaje) del texto que devuelve el driver ODBC de SQL Server."""
    m = _MSG.search(texto)
    if not m:
        return None, texto
    return int(m.group("num")), m.group("msg").strip()


def translate_db_error(exc: BaseException) -> AppError:
    """Traduce una excepción de pyodbc a una excepción de dominio."""
    if isinstance(exc, AppError):
        return exc
    args = getattr(exc, "args", ())
    sqlstate = str(args[0]) if args else ""
    texto = " ".join(str(a) for a in args)
    numero, mensaje = parse_sql_error(texto)

    # Serie 50xxx = reglas lanzadas por nuestros procedimientos (THROW): el mensaje es apto para el usuario
    if numero == 50404:
        return NotFoundError(mensaje)
    if numero == 50409:
        return ConflictError(mensaje)
    if numero == 50410:
        return ConfirmationRequiredError(mensaje)
    if numero == 50422:
        return BusinessRuleError(mensaje)
    if numero == 50403:
        return ForbiddenError(mensaje)
    # Respaldo de las restricciones del motor (los procedimientos ya validan antes con mensajes amigables)
    if numero in (2601, 2627):
        return ConflictError("Ya existe un registro con esos datos.")
    if numero == 547:
        return BusinessRuleError("La operación no cumple una restricción de integridad de los datos.")
    if numero in (1205, 1222):
        return ConflictError("Otro usuario modificó los mismos datos a la vez. Intente de nuevo.", codigo="CONCURRENCIA")
    if numero in (18456, 4060) or sqlstate in _SQLSTATE_CONEXION or sqlstate.startswith("08"):
        log.error("Fallo de conexión a la base de datos: %s", texto[:300])
        return DatabaseUnavailableError("La base de datos no está disponible en este momento.")
    log.error("Error inesperado de base de datos (%s, %s): %s", sqlstate, numero, texto[:500])
    return AppError("Ocurrió un error al procesar la operación.")


class Executor:
    """Envuelve una conexión DB-API (pyodbc) y ejecuta procedimientos almacenados."""

    def __init__(self, connection: Any) -> None:
        self._cn = connection

    # -- construcción segura de la sentencia ----------------------------------
    @staticmethod
    def build_call(proc: str, params: dict[str, Any]) -> tuple[str, list[Any]]:
        if not _PROC.fullmatch(proc):
            raise ValueError(f"Nombre de procedimiento no permitido: {proc!r}")
        for nombre in params:
            if not _PARAM.fullmatch(nombre):
                raise ValueError(f"Nombre de parámetro no permitido: {nombre!r}")
        asignaciones = ", ".join(f"@{n} = ?" for n in params)
        sql = f"EXEC dbo.{proc} {asignaciones}".rstrip()
        return sql, list(params.values())

    def _run(self, proc: str, params: dict[str, Any], leer: Callable[[Any], Any]) -> Any:
        sql, args = self.build_call(proc, params)
        cursor = self._cn.cursor()
        try:
            cursor.execute(sql, args)
            return leer(cursor)
        except Exception as exc:  # noqa: BLE001 - se traduce siempre
            raise translate_db_error(exc) from exc
        finally:
            cursor.close()

    @staticmethod
    def _filas(cursor: Any) -> list[dict[str, Any]]:
        if cursor.description is None:
            return []
        columnas = [c[0] for c in cursor.description]
        return [dict(zip(columnas, fila)) for fila in cursor.fetchall()]

    # -- API pública -----------------------------------------------------------
    def fetch_all(self, proc: str, /, **params: Any) -> list[dict[str, Any]]:
        """Primer conjunto de resultados como lista de dicts."""
        return self._run(proc, params, self._filas)

    def fetch_one(self, proc: str, /, **params: Any) -> dict[str, Any] | None:
        filas = self.fetch_all(proc, **params)
        return filas[0] if filas else None

    def fetch_sets(self, proc: str, /, **params: Any) -> list[list[dict[str, Any]]]:
        """Todos los conjuntos de resultados (procedimientos con varios SELECT)."""

        def leer(cursor: Any) -> list[list[dict[str, Any]]]:
            conjuntos: list[list[dict[str, Any]]] = []
            while True:
                if cursor.description is not None:
                    conjuntos.append(self._filas(cursor))
                if not cursor.nextset():
                    return conjuntos

        return self._run(proc, params, leer)

    def execute(self, proc: str, /, **params: Any) -> None:
        """Procedimiento sin resultado. Se agotan los conjuntos para que afloren los errores diferidos."""

        def leer(cursor: Any) -> None:
            while cursor.nextset():
                pass

        self._run(proc, params, leer)

    def page(self, proc: str, /, *, pagina: int, tamano: int, **params: Any) -> tuple[list[dict[str, Any]], int]:
        """Listado paginado: el procedimiento devuelve `total_filas` en cada fila."""
        filas = self.fetch_all(proc, pagina=pagina, tamano=tamano, **params)
        if not filas:
            if pagina > 1:  # página fuera de rango: se averigua el total real con una consulta mínima
                sonda = self.fetch_all(proc, pagina=1, tamano=1, **params)
                return [], int(sonda[0]["total_filas"]) if sonda else 0
            return [], 0
        total = int(filas[0]["total_filas"])
        for f in filas:
            f.pop("total_filas", None)
        return filas, total

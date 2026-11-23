"""Excepciones de dominio y su traducción a respuestas HTTP uniformes.

Formato de error:  {"error": {"codigo": "...", "mensaje": "...", "detalles": [...]}}
Nunca se devuelven trazas, cadenas de conexión ni mensajes internos de SQL Server.
"""
from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("redsolidaria")


class AppError(Exception):
    status_code = 500
    codigo = "ERROR_INTERNO"

    def __init__(self, mensaje: str, *, codigo: str | None = None, detalles: list[Any] | None = None):
        super().__init__(mensaje)
        self.mensaje = mensaje
        self.detalles = detalles or []
        if codigo:
            self.codigo = codigo


class UnauthorizedError(AppError):
    status_code, codigo = 401, "NO_AUTENTICADO"


class ForbiddenError(AppError):
    status_code, codigo = 403, "PROHIBIDO"


class NotFoundError(AppError):
    status_code, codigo = 404, "NO_ENCONTRADO"


class ConflictError(AppError):
    status_code, codigo = 409, "CONFLICTO"


class ConfirmationRequiredError(AppError):
    """Advertencia que el usuario puede aceptar reenviando con la bandera de confirmación."""

    status_code, codigo = 409, "REQUIERE_CONFIRMACION"


class BusinessRuleError(AppError):
    status_code, codigo = 422, "REGLA_DE_NEGOCIO"


class AccountLockedError(AppError):
    status_code, codigo = 423, "CUENTA_BLOQUEADA"


class DatabaseUnavailableError(AppError):
    status_code, codigo = 503, "BASE_DE_DATOS_NO_DISPONIBLE"


def _respuesta(status: int, codigo: str, mensaje: str, detalles: list[Any] | None = None) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"codigo": codigo, "mensaje": mensaje, "detalles": detalles or []}})


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return _respuesta(exc.status_code, exc.codigo, exc.mensaje, exc.detalles)

    @app.exception_handler(RequestValidationError)
    async def _validacion(_: Request, exc: RequestValidationError) -> JSONResponse:
        detalles = [
            {"campo": ".".join(str(p) for p in e["loc"] if p not in ("body", "query", "path")), "mensaje": e["msg"]}
            for e in exc.errors()
        ]
        return _respuesta(422, "VALIDACION", "Hay datos que no son válidos. Revise los campos indicados.", detalles)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        mensajes = {404: "El recurso solicitado no existe.", 405: "Método no permitido.", 401: "No autenticado."}
        return _respuesta(exc.status_code, "HTTP_%d" % exc.status_code, mensajes.get(exc.status_code, "Solicitud no válida."))

    @app.exception_handler(Exception)
    async def _inesperado(request: Request, exc: Exception) -> JSONResponse:
        log.exception("Error no controlado en %s %s", request.method, request.url.path)
        return _respuesta(500, "ERROR_INTERNO", "Ocurrió un error inesperado. Intente de nuevo más tarde.")

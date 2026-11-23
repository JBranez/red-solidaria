"""Punto de entrada de la API de Red Solidaria."""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.apis.deps import CatalogoSvc
from app.apis.router import api_router
from app.core.config import Settings, get_settings
from app.core.errors import register_exception_handlers

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    produccion = settings.is_production
    app = FastAPI(
        title="Red Solidaria API",
        version="1.0.0",
        description="Gestión de donaciones, campañas, hogares beneficiarios y entregas de ayuda social.",
        docs_url=None if produccion else "/docs",
        redoc_url=None,
        openapi_url=None if produccion else "/openapi.json",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,  # lista explícita; jamás "*"
        allow_credentials=False,                   # se usa Bearer en cabecera, no cookies
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
        max_age=600,
    )

    @app.middleware("http")
    async def cabeceras_de_seguridad(request: Request, call_next):
        respuesta = await call_next(request)
        respuesta.headers.setdefault("X-Content-Type-Options", "nosniff")
        respuesta.headers.setdefault("X-Frame-Options", "DENY")
        respuesta.headers.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path.startswith("/api/"):
            respuesta.headers.setdefault("Cache-Control", "no-store")  # nada con datos personales en cachés
        return respuesta

    register_exception_handlers(app)
    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health", tags=["Salud"], summary="Liveness: el proceso responde")
    def health() -> dict[str, str]:
        return {"estado": "ok"}

    @app.get("/health/db", tags=["Salud"], summary="Readiness: la base de datos responde")
    def health_db(catalogos: CatalogoSvc) -> dict[str, str]:
        catalogos.metodos_pago()  # consulta mínima: si falla, el manejador responde 503
        return {"estado": "ok", "base_de_datos": "disponible"}

    return app


app = create_app()

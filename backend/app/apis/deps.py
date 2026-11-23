"""Dependencias de FastAPI: conexión por petición, usuario autenticado, autorización por permiso y servicios."""
from __future__ import annotations

from typing import Annotated, Callable, Iterator

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings
from app.core.errors import ForbiddenError, UnauthorizedError
from app.core.security import decode_access_token
from app.db.connection import open_connection
from app.db.executor import Executor
from app.repositories.catalogos import CatalogoRepository
from app.repositories.finanzas import CampanaRepository, DonacionRepository, DonanteRepository, GastoRepository
from app.repositories.operacion import (
    BeneficiarioRepository, EntregaRepository, FeedbackRepository, NecesidadRepository, VoluntarioRepository,
)
from app.repositories.reportes import ReporteRepository
from app.repositories.seguridad import AuditoriaRepository, AuthRepository, UsuarioRepository
from app.schemas.auth import UsuarioActualOut
from app.services.catalogos import CatalogoService
from app.services.finanzas import CampanaService, DonacionService, DonanteService, GastoService
from app.services.operacion import (
    BeneficiarioService, EntregaService, FeedbackService, NecesidadService, VoluntarioService,
)
from app.services.reportes import ReporteService
from app.services.seguridad import AuditoriaService, AuthService, UsuarioService

bearer = HTTPBearer(auto_error=False, description="Token JWT obtenido en POST /api/v1/auth/login")


def get_db(settings: Annotated[Settings, Depends(get_settings)]) -> Iterator[Executor]:
    """Una conexión por petición; se cierra siempre al terminar (FastAPI la comparte entre dependencias)."""
    conexion = open_connection(settings)
    try:
        yield Executor(conexion)
    finally:
        try:
            conexion.close()
        except Exception:  # noqa: BLE001 - el cierre nunca debe tapar la respuesta
            pass


Db = Annotated[Executor, Depends(get_db)]
Cfg = Annotated[Settings, Depends(get_settings)]


def client_ip(request: Request) -> str | None:
    """IP directa del cliente. Detrás de un proxy inverso, configure uvicorn con --proxy-headers y --forwarded-allow-ips."""
    return request.client.host if request.client else None


Ip = Annotated[str | None, Depends(client_ip)]


# ---------------------------------------------------------------- servicios
def _auth_service(db: Db, settings: Cfg) -> AuthService:
    return AuthService(AuthRepository(db), UsuarioRepository(db), AuditoriaRepository(db), settings)


AuthSvc = Annotated[AuthService, Depends(_auth_service)]


def _usuario_service(db: Db) -> UsuarioService:
    return UsuarioService(UsuarioRepository(db))


def _auditoria_service(db: Db) -> AuditoriaService:
    return AuditoriaService(AuditoriaRepository(db))


def _catalogo_service(db: Db) -> CatalogoService:
    return CatalogoService(CatalogoRepository(db))


def _campana_service(db: Db) -> CampanaService:
    return CampanaService(CampanaRepository(db))


def _donante_service(db: Db) -> DonanteService:
    return DonanteService(DonanteRepository(db))


def _donacion_service(db: Db) -> DonacionService:
    return DonacionService(DonacionRepository(db), AuditoriaRepository(db))


def _gasto_service(db: Db) -> GastoService:
    return GastoService(GastoRepository(db))


def _beneficiario_service(db: Db) -> BeneficiarioService:
    return BeneficiarioService(BeneficiarioRepository(db))


def _necesidad_service(db: Db) -> NecesidadService:
    return NecesidadService(NecesidadRepository(db))


def _voluntario_service(db: Db) -> VoluntarioService:
    return VoluntarioService(VoluntarioRepository(db))


def _entrega_service(db: Db) -> EntregaService:
    return EntregaService(EntregaRepository(db), AuditoriaRepository(db))


def _feedback_service(db: Db) -> FeedbackService:
    return FeedbackService(FeedbackRepository(db))


def _reporte_service(db: Db) -> ReporteService:
    return ReporteService(ReporteRepository(db))


UsuarioSvc = Annotated[UsuarioService, Depends(_usuario_service)]
AuditoriaSvc = Annotated[AuditoriaService, Depends(_auditoria_service)]
CatalogoSvc = Annotated[CatalogoService, Depends(_catalogo_service)]
CampanaSvc = Annotated[CampanaService, Depends(_campana_service)]
DonanteSvc = Annotated[DonanteService, Depends(_donante_service)]
DonacionSvc = Annotated[DonacionService, Depends(_donacion_service)]
GastoSvc = Annotated[GastoService, Depends(_gasto_service)]
BeneficiarioSvc = Annotated[BeneficiarioService, Depends(_beneficiario_service)]
NecesidadSvc = Annotated[NecesidadService, Depends(_necesidad_service)]
VoluntarioSvc = Annotated[VoluntarioService, Depends(_voluntario_service)]
EntregaSvc = Annotated[EntregaService, Depends(_entrega_service)]
FeedbackSvc = Annotated[FeedbackService, Depends(_feedback_service)]
ReporteSvc = Annotated[ReporteService, Depends(_reporte_service)]


# ---------------------------------------------------------------- autenticación y autorización
def usuario_sesion(
    credenciales: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    auth: AuthSvc,
    settings: Cfg,
) -> UsuarioActualOut:
    """Usuario de la sesión (aunque deba cambiar su contraseña). Se valida contra la BD en CADA petición."""
    if credenciales is None:
        raise UnauthorizedError("Falta el token de autenticación.")
    return auth.autenticar_token(decode_access_token(credenciales.credentials, settings))


def usuario_actual(usuario: Annotated[UsuarioActualOut, Depends(usuario_sesion)]) -> UsuarioActualOut:
    """Usuario listo para operar: bloquea todo mientras tenga una contraseña temporal pendiente de cambio."""
    if usuario.debe_cambiar_password:
        raise ForbiddenError("Debe cambiar su contraseña temporal antes de continuar.", codigo="CAMBIO_PASSWORD_REQUERIDO")
    return usuario


Actor = Annotated[UsuarioActualOut, Depends(usuario_actual)]


def requiere(*permisos: str) -> Callable[..., UsuarioActualOut]:
    """Exige AL MENOS UNO de los permisos indicados. El menú del frontend es solo comodidad: aquí se hace cumplir."""

    def dependencia(usuario: Actor) -> UsuarioActualOut:
        if not any(usuario.tiene(p) for p in permisos):
            raise ForbiddenError("No tiene permiso para realizar esta acción.", codigo="PERMISO_INSUFICIENTE")
        return usuario

    return dependencia

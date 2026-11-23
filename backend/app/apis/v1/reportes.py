"""Dashboard, reportes internos, portales personales y datos públicos."""
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.apis.deps import DonacionSvc, EntregaSvc, ReporteSvc, requiere
from app.core import permissions as P
from app.schemas.auth import UsuarioActualOut
from app.schemas.common import Pagina
from app.schemas.finanzas import DonacionOut, FiltroDonaciones
from app.schemas.operacion import EntregaOut, FiltroEntregas
from app.schemas.reportes import (
    KpisOut, PorCategoriaOut, PorSectorOut, PublicoCampanaOut, PublicoResumenOut, SerieMensualOut, TopDonanteOut,
)

dashboard = APIRouter(tags=["Dashboard y reportes"])
mi = APIRouter(prefix="/mi", tags=["Mi portal"])
publico = APIRouter(prefix="/public", tags=["Portal público de transparencia (sin autenticación)"])


def _perm(*codigos: str):
    return Annotated[UsuarioActualOut, Depends(requiere(*codigos))]


@dashboard.get("/dashboard/kpis", response_model=KpisOut, summary="Indicadores por nivel: financiero, cobertura, operación, resultados")
def kpis(svc: ReporteSvc, _: _perm(P.DASHBOARD_LEER)):
    return svc.kpis()


@dashboard.get("/dashboard/series", response_model=list[SerieMensualOut])
def series(svc: ReporteSvc, _: _perm(P.DASHBOARD_LEER), meses: Annotated[int, Query(ge=1, le=36)] = 12):
    return svc.series(meses)


@dashboard.get("/dashboard/categorias", response_model=list[PorCategoriaOut])
def por_categoria(svc: ReporteSvc, _: _perm(P.DASHBOARD_LEER)):
    return svc.por_categoria()


@dashboard.get("/dashboard/sectores", response_model=list[PorSectorOut])
def por_sector(svc: ReporteSvc, _: _perm(P.DASHBOARD_LEER)):
    return svc.por_sector()


@dashboard.get("/reportes/top-donantes", response_model=list[TopDonanteOut], summary="Reporte interno con nombres de donantes")
def top_donantes(svc: ReporteSvc, _: _perm(P.REPORTES_LEER), limite: Annotated[int, Query(ge=1, le=20)] = 5):
    return svc.top_donantes(limite)


# ---------------------------------------------------------------- portales personales
@mi.get("/donaciones", response_model=Pagina[DonacionOut], summary="Mis donaciones (portal del donante)")
def mis_donaciones(filtro: Annotated[FiltroDonaciones, Query()], svc: DonacionSvc, actor: _perm(P.PORTAL_DONANTE)):
    return svc.listar_propias(actor, filtro)


@mi.get("/entregas", response_model=Pagina[EntregaOut], summary="Mis entregas asignadas (portal del voluntario)")
def mis_entregas(filtro: Annotated[FiltroEntregas, Query()], svc: EntregaSvc, actor: _perm(P.PORTAL_VOLUNTARIO)):
    return svc.listar(filtro, actor)


# ---------------------------------------------------------------- público (solo agregados)
def _cache(respuesta: Response) -> None:
    respuesta.headers["Cache-Control"] = "public, max-age=60"


@publico.get("/resumen", response_model=PublicoResumenOut)
def publico_resumen(svc: ReporteSvc, respuesta: Response):
    _cache(respuesta)
    return svc.publico_resumen()


@publico.get("/campanas", response_model=list[PublicoCampanaOut])
def publico_campanas(svc: ReporteSvc, respuesta: Response):
    _cache(respuesta)
    return svc.publico_campanas()

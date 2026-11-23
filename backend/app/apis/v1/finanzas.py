"""Campañas, donantes, donaciones y gastos."""
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.apis.deps import CampanaSvc, DonacionSvc, DonanteSvc, GastoSvc, Ip, requiere
from app.core import permissions as P
from app.schemas.auth import UsuarioActualOut
from app.schemas.common import CambioActivo, Pagina
from app.schemas.finanzas import (
    CampanaEstadoIn, CampanaIn, CampanaOut, CierreCampanaOut, DonacionEstadoIn, DonacionIn, DonacionOut, DonanteIn,
    DonanteOut, FiltroCampanas, FiltroDonaciones, FiltroDonantes, FiltroGastos, GastoEstadoIn, GastoIn, GastoOut,
)

campanas = APIRouter(prefix="/campanas", tags=["Campañas"])
donantes = APIRouter(prefix="/donantes", tags=["Donantes"])
donaciones = APIRouter(prefix="/donaciones", tags=["Donaciones"])
gastos = APIRouter(prefix="/gastos", tags=["Gastos"])


def _perm(*codigos: str):
    return Annotated[UsuarioActualOut, Depends(requiere(*codigos))]


# ---------------------------------------------------------------- campañas
@campanas.get("", response_model=Pagina[CampanaOut])
def listar_campanas(filtro: Annotated[FiltroCampanas, Query()], svc: CampanaSvc, _: _perm(P.CAMPANAS_LEER)):
    return svc.listar(filtro)


@campanas.post("", response_model=CampanaOut, status_code=201)
def crear_campana(datos: CampanaIn, svc: CampanaSvc, actor: _perm(P.CAMPANAS_ESCRIBIR)):
    return svc.crear(datos, actor)


@campanas.get("/{id_campana}", response_model=CampanaOut)
def obtener_campana(id_campana: int, svc: CampanaSvc, _: _perm(P.CAMPANAS_LEER)):
    return svc.obtener(id_campana)


@campanas.put("/{id_campana}", response_model=CampanaOut)
def actualizar_campana(id_campana: int, datos: CampanaIn, svc: CampanaSvc, actor: _perm(P.CAMPANAS_ESCRIBIR)):
    return svc.actualizar(id_campana, datos, actor)


@campanas.post("/{id_campana}/estado", response_model=CampanaOut, summary="Activar, pausar, finalizar o cancelar")
def estado_campana(id_campana: int, datos: CampanaEstadoIn, svc: CampanaSvc, actor: _perm(P.CAMPANAS_ESTADO)):
    return svc.cambiar_estado(id_campana, datos, actor)


@campanas.get("/{id_campana}/cierre", response_model=CierreCampanaOut, summary="Informe de cierre / rendición de cuentas")
def cierre_campana(id_campana: int, svc: CampanaSvc, _: _perm(P.CAMPANAS_LEER)):
    return svc.cierre(id_campana)


# ---------------------------------------------------------------- donantes
@donantes.get("", response_model=Pagina[DonanteOut])
def listar_donantes(filtro: Annotated[FiltroDonantes, Query()], svc: DonanteSvc, _: _perm(P.DONANTES_LEER)):
    return svc.listar(filtro)


@donantes.post("", response_model=DonanteOut, status_code=201)
def crear_donante(datos: DonanteIn, svc: DonanteSvc, actor: _perm(P.DONANTES_ESCRIBIR)):
    return svc.crear(datos, actor)


@donantes.get("/{id_donante}", response_model=DonanteOut)
def obtener_donante(id_donante: int, svc: DonanteSvc, _: _perm(P.DONANTES_LEER)):
    return svc.obtener(id_donante)


@donantes.put("/{id_donante}", response_model=DonanteOut)
def actualizar_donante(id_donante: int, datos: DonanteIn, svc: DonanteSvc, actor: _perm(P.DONANTES_ESCRIBIR)):
    return svc.actualizar(id_donante, datos, actor)


@donantes.patch("/{id_donante}/estado", response_model=DonanteOut)
def estado_donante(id_donante: int, datos: CambioActivo, svc: DonanteSvc, actor: _perm(P.DONANTES_ESCRIBIR)):
    return svc.cambiar_estado(id_donante, datos.activo, actor)


# ---------------------------------------------------------------- donaciones
@donaciones.get("", response_model=Pagina[DonacionOut])
def listar_donaciones(filtro: Annotated[FiltroDonaciones, Query()], svc: DonacionSvc, _: _perm(P.DONACIONES_LEER)):
    return svc.listar(filtro)


@donaciones.get("/export", summary="Exportar donaciones a CSV (queda en la bitácora)")
def exportar_donaciones(filtro: Annotated[FiltroDonaciones, Query()], svc: DonacionSvc, ip: Ip,
                        actor: _perm(P.DONACIONES_EXPORTAR)) -> Response:
    contenido = svc.exportar_csv(filtro, actor, ip)
    return Response(contenido, media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="donaciones_{date.today().isoformat()}.csv"'})


@donaciones.post("", response_model=DonacionOut, status_code=201)
def crear_donacion(datos: DonacionIn, svc: DonacionSvc, actor: _perm(P.DONACIONES_REGISTRAR)):
    return svc.crear(datos, actor)


@donaciones.get("/{id_donacion}", response_model=DonacionOut)
def obtener_donacion(id_donacion: int, svc: DonacionSvc, _: _perm(P.DONACIONES_LEER)):
    return svc.obtener(id_donacion)


@donaciones.post("/{id_donacion}/estado", response_model=DonacionOut, summary="Confirmar, rechazar o anular")
def estado_donacion(id_donacion: int, datos: DonacionEstadoIn, svc: DonacionSvc, actor: _perm(P.DONACIONES_VERIFICAR)):
    return svc.cambiar_estado(id_donacion, datos, actor)


# ---------------------------------------------------------------- gastos
@gastos.get("", response_model=Pagina[GastoOut])
def listar_gastos(filtro: Annotated[FiltroGastos, Query()], svc: GastoSvc, _: _perm(P.GASTOS_LEER)):
    return svc.listar(filtro)


@gastos.post("", response_model=GastoOut, status_code=201)
def crear_gasto(datos: GastoIn, svc: GastoSvc, actor: _perm(P.GASTOS_REGISTRAR)):
    return svc.crear(datos, actor)


@gastos.post("/{id_gasto}/estado", response_model=GastoOut, summary="Aprobar o anular (aprueba alguien distinto de quien registró)")
def estado_gasto(id_gasto: int, datos: GastoEstadoIn, svc: GastoSvc, actor: _perm(P.GASTOS_APROBAR)):
    return svc.cambiar_estado(id_gasto, datos, actor)

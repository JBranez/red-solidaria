"""Hogares, necesidades, voluntarios, entregas y retroalimentación."""
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.apis.deps import BeneficiarioSvc, EntregaSvc, FeedbackSvc, Ip, NecesidadSvc, VoluntarioSvc, requiere
from app.core import permissions as P
from app.schemas.auth import UsuarioActualOut
from app.schemas.common import CambioActivo, Pagina
from app.schemas.operacion import (
    BeneficiarioIn, BeneficiarioOut, EntregaEstadoIn, EntregaIn, EntregaOut, FeedbackGestionIn, FeedbackIn,
    FeedbackOut, FiltroBeneficiarios, FiltroEntregas, FiltroFeedback, FiltroNecesidades, FiltroVoluntarios,
    NecesidadEdicionIn, NecesidadEstadoIn, NecesidadIn, NecesidadOut, VoluntarioIn, VoluntarioOut,
)

beneficiarios = APIRouter(prefix="/beneficiarios", tags=["Hogares beneficiarios"])
necesidades = APIRouter(prefix="/necesidades", tags=["Necesidades"])
voluntarios = APIRouter(prefix="/voluntarios", tags=["Voluntarios"])
entregas = APIRouter(prefix="/entregas", tags=["Entregas"])
feedback = APIRouter(prefix="/feedback", tags=["Retroalimentación y quejas"])


def _perm(*codigos: str):
    return Annotated[UsuarioActualOut, Depends(requiere(*codigos))]


# ---------------------------------------------------------------- hogares
@beneficiarios.get("", response_model=Pagina[BeneficiarioOut])
def listar_beneficiarios(filtro: Annotated[FiltroBeneficiarios, Query()], svc: BeneficiarioSvc,
                         _: _perm(P.BENEFICIARIOS_LEER)):
    return svc.listar(filtro)


@beneficiarios.post("", response_model=BeneficiarioOut, status_code=201)
def crear_beneficiario(datos: BeneficiarioIn, svc: BeneficiarioSvc, actor: _perm(P.BENEFICIARIOS_ESCRIBIR)):
    return svc.crear(datos, actor)


@beneficiarios.get("/{id_beneficiario}", response_model=BeneficiarioOut)
def obtener_beneficiario(id_beneficiario: int, svc: BeneficiarioSvc, _: _perm(P.BENEFICIARIOS_LEER)):
    return svc.obtener(id_beneficiario)


@beneficiarios.put("/{id_beneficiario}", response_model=BeneficiarioOut)
def actualizar_beneficiario(id_beneficiario: int, datos: BeneficiarioIn, svc: BeneficiarioSvc,
                            actor: _perm(P.BENEFICIARIOS_ESCRIBIR)):
    return svc.actualizar(id_beneficiario, datos, actor)


@beneficiarios.patch("/{id_beneficiario}/estado", response_model=BeneficiarioOut)
def estado_beneficiario(id_beneficiario: int, datos: CambioActivo, svc: BeneficiarioSvc,
                        actor: _perm(P.BENEFICIARIOS_ESCRIBIR)):
    return svc.cambiar_estado(id_beneficiario, datos.activo, actor)


# ---------------------------------------------------------------- necesidades
@necesidades.get("", response_model=Pagina[NecesidadOut], summary="Cola de atención (urgencia y antigüedad)")
def listar_necesidades(filtro: Annotated[FiltroNecesidades, Query()], svc: NecesidadSvc, _: _perm(P.NECESIDADES_LEER)):
    return svc.listar(filtro)


@necesidades.post("", response_model=NecesidadOut, status_code=201)
def crear_necesidad(datos: NecesidadIn, svc: NecesidadSvc, actor: _perm(P.NECESIDADES_ESCRIBIR)):
    return svc.crear(datos, actor)


@necesidades.put("/{id_necesidad}", response_model=NecesidadOut)
def actualizar_necesidad(id_necesidad: int, datos: NecesidadEdicionIn, svc: NecesidadSvc,
                         actor: _perm(P.NECESIDADES_ESCRIBIR)):
    return svc.actualizar(id_necesidad, datos, actor)


@necesidades.post("/{id_necesidad}/estado", response_model=NecesidadOut)
def estado_necesidad(id_necesidad: int, datos: NecesidadEstadoIn, svc: NecesidadSvc,
                     actor: _perm(P.NECESIDADES_ESCRIBIR)):
    return svc.cambiar_estado(id_necesidad, datos, actor)


# ---------------------------------------------------------------- voluntarios
@voluntarios.get("", response_model=Pagina[VoluntarioOut])
def listar_voluntarios(filtro: Annotated[FiltroVoluntarios, Query()], svc: VoluntarioSvc, _: _perm(P.VOLUNTARIOS_LEER)):
    return svc.listar(filtro)


@voluntarios.post("", response_model=VoluntarioOut, status_code=201)
def crear_voluntario(datos: VoluntarioIn, svc: VoluntarioSvc, actor: _perm(P.VOLUNTARIOS_ESCRIBIR)):
    return svc.crear(datos, actor)


@voluntarios.get("/{id_voluntario}", response_model=VoluntarioOut)
def obtener_voluntario(id_voluntario: int, svc: VoluntarioSvc, _: _perm(P.VOLUNTARIOS_LEER)):
    return svc.obtener(id_voluntario)


@voluntarios.put("/{id_voluntario}", response_model=VoluntarioOut)
def actualizar_voluntario(id_voluntario: int, datos: VoluntarioIn, svc: VoluntarioSvc,
                          actor: _perm(P.VOLUNTARIOS_ESCRIBIR)):
    return svc.actualizar(id_voluntario, datos, actor)


@voluntarios.patch("/{id_voluntario}/estado", response_model=VoluntarioOut)
def estado_voluntario(id_voluntario: int, datos: CambioActivo, svc: VoluntarioSvc, actor: _perm(P.VOLUNTARIOS_ESCRIBIR)):
    return svc.cambiar_estado(id_voluntario, datos.activo, actor)


# ---------------------------------------------------------------- entregas
@entregas.get("", response_model=Pagina[EntregaOut])
def listar_entregas(filtro: Annotated[FiltroEntregas, Query()], svc: EntregaSvc,
                    actor: _perm(P.ENTREGAS_LEER, P.ENTREGAS_PROPIAS)):
    return svc.listar(filtro, actor)


@entregas.get("/export", summary="Exportar entregas a CSV (queda en la bitácora)")
def exportar_entregas(filtro: Annotated[FiltroEntregas, Query()], svc: EntregaSvc, ip: Ip,
                      actor: _perm(P.REPORTES_EXPORTAR)) -> Response:
    contenido = svc.exportar_csv(filtro, actor, ip)
    return Response(contenido, media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="entregas_{date.today().isoformat()}.csv"'})


@entregas.post("", response_model=EntregaOut, status_code=201)
def crear_entrega(datos: EntregaIn, svc: EntregaSvc, actor: _perm(P.ENTREGAS_REGISTRAR)):
    return svc.crear(datos, actor)


@entregas.get("/{id_entrega}", response_model=EntregaOut)
def obtener_entrega(id_entrega: int, svc: EntregaSvc, actor: _perm(P.ENTREGAS_LEER, P.ENTREGAS_PROPIAS)):
    return svc.obtener(id_entrega, actor)


@entregas.post("/{id_entrega}/estado", response_model=EntregaOut, summary="Entregada, no realizada o anulada")
def estado_entrega(id_entrega: int, datos: EntregaEstadoIn, svc: EntregaSvc,
                   actor: _perm(P.ENTREGAS_GESTIONAR, P.ENTREGAS_PROPIAS)):
    return svc.cambiar_estado(id_entrega, datos, actor)


# ---------------------------------------------------------------- retroalimentación
@feedback.get("", response_model=Pagina[FeedbackOut])
def listar_feedback(filtro: Annotated[FiltroFeedback, Query()], svc: FeedbackSvc, actor: _perm(P.FEEDBACK_LEER)):
    return svc.listar(filtro, actor)


@feedback.post("", status_code=201, summary="Registrar retroalimentación, consulta o queja")
def crear_feedback(datos: FeedbackIn, svc: FeedbackSvc, actor: _perm(P.FEEDBACK_REGISTRAR)) -> Response:
    svc.crear(datos, actor)
    return Response(status_code=201)


@feedback.post("/{id_retroalimentacion}/gestionar", response_model=FeedbackOut)
def gestionar_feedback(id_retroalimentacion: int, datos: FeedbackGestionIn, svc: FeedbackSvc,
                       actor: _perm(P.FEEDBACK_GESTIONAR)):
    return svc.gestionar(id_retroalimentacion, datos, actor)

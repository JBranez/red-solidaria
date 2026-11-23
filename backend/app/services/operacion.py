"""Hogares, necesidades, voluntarios, entregas y retroalimentación."""
from __future__ import annotations

from app.core import permissions as P
from app.core.errors import BusinessRuleError, ForbiddenError, NotFoundError
from app.core.utils import to_csv
from app.repositories.operacion import (
    BeneficiarioRepository, EntregaRepository, FeedbackRepository, NecesidadRepository, VoluntarioRepository,
)
from app.repositories.seguridad import AuditoriaRepository
from app.schemas.auth import UsuarioActualOut
from app.schemas.common import Pagina
from app.schemas.operacion import (
    BeneficiarioIn, BeneficiarioOut, EntregaEstadoIn, EntregaIn, EntregaOut, FeedbackGestionIn, FeedbackIn,
    FeedbackOut, FiltroBeneficiarios, FiltroEntregas, FiltroFeedback, FiltroNecesidades, FiltroVoluntarios,
    NecesidadEdicionIn, NecesidadEstadoIn, NecesidadIn, NecesidadOut, VoluntarioIn, VoluntarioOut,
)
from app.services.base import a_pagina, existente, kwargs_filtro

EXPORT_MAX_FILAS = 50_000


class BeneficiarioService:
    def __init__(self, repo: BeneficiarioRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroBeneficiarios) -> Pagina[BeneficiarioOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, BeneficiarioOut)

    def obtener(self, id_beneficiario: int) -> BeneficiarioOut:
        return BeneficiarioOut.model_validate(existente(self.repo.obtener(id_beneficiario), "El hogar"))

    def crear(self, datos: BeneficiarioIn, actor: UsuarioActualOut) -> BeneficiarioOut:
        nuevo = self.repo.guardar(id_beneficiario=None, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_beneficiario: int, datos: BeneficiarioIn, actor: UsuarioActualOut) -> BeneficiarioOut:
        self.repo.guardar(id_beneficiario=id_beneficiario, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(id_beneficiario)

    def cambiar_estado(self, id_beneficiario: int, activo: bool, actor: UsuarioActualOut) -> BeneficiarioOut:
        self.repo.cambiar_estado(id_beneficiario=id_beneficiario, activo=activo, id_actor=actor.id_usuario)
        return self.obtener(id_beneficiario)


class NecesidadService:
    def __init__(self, repo: NecesidadRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroNecesidades) -> Pagina[NecesidadOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro, excluir=("q",)))
        return a_pagina(filas, total, filtro, NecesidadOut)

    def obtener(self, id_necesidad: int) -> NecesidadOut:
        return NecesidadOut.model_validate(existente(self.repo.obtener(id_necesidad), "La necesidad"))

    def crear(self, datos: NecesidadIn, actor: UsuarioActualOut) -> NecesidadOut:
        nuevo = self.repo.guardar(id_necesidad=None, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_necesidad: int, datos: NecesidadEdicionIn, actor: UsuarioActualOut) -> NecesidadOut:
        actual = self.obtener(id_necesidad)
        self.repo.guardar(id_necesidad=id_necesidad, id_beneficiario=actual.id_beneficiario, **datos.model_dump(),
                          id_actor=actor.id_usuario)
        return self.obtener(id_necesidad)

    def cambiar_estado(self, id_necesidad: int, datos: NecesidadEstadoIn, actor: UsuarioActualOut) -> NecesidadOut:
        if datos.estado == "Descartada" and not (datos.motivo or "").strip():
            raise BusinessRuleError("Indique el motivo por el que se descarta la necesidad.")
        self.repo.cambiar_estado(id_necesidad=id_necesidad, nuevo_estado=datos.estado, motivo=datos.motivo,
                                 id_actor=actor.id_usuario)
        return self.obtener(id_necesidad)


class VoluntarioService:
    def __init__(self, repo: VoluntarioRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroVoluntarios) -> Pagina[VoluntarioOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, VoluntarioOut)

    def obtener(self, id_voluntario: int) -> VoluntarioOut:
        return VoluntarioOut.model_validate(existente(self.repo.obtener(id_voluntario), "El voluntario"))

    def crear(self, datos: VoluntarioIn, actor: UsuarioActualOut) -> VoluntarioOut:
        nuevo = self.repo.guardar(id_voluntario=None, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_voluntario: int, datos: VoluntarioIn, actor: UsuarioActualOut) -> VoluntarioOut:
        self.repo.guardar(id_voluntario=id_voluntario, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(id_voluntario)

    def cambiar_estado(self, id_voluntario: int, activo: bool, actor: UsuarioActualOut) -> VoluntarioOut:
        self.repo.cambiar_estado(id_voluntario=id_voluntario, activo=activo, id_actor=actor.id_usuario)
        return self.obtener(id_voluntario)


COLUMNAS_ENTREGAS = [
    ("id_entrega", "N.º"), ("fecha", "Fecha"), ("campana", "Campaña"), ("hogar", "Hogar"), ("sector", "Sector"),
    ("voluntario", "Voluntario"), ("cantidad", "Cantidad"), ("detalle", "Detalle"), ("estado", "Estado"),
]


class EntregaService:
    """Autorización a nivel de dato: un voluntario solo ve y confirma las entregas ASIGNADAS a él."""

    def __init__(self, repo: EntregaRepository, auditoria: AuditoriaRepository) -> None:
        self.repo, self.auditoria = repo, auditoria

    def listar(self, filtro: FiltroEntregas, actor: UsuarioActualOut) -> Pagina[EntregaOut]:
        if actor.tiene(P.ENTREGAS_LEER):
            efectivo = filtro
        elif actor.tiene(P.ENTREGAS_PROPIAS) and actor.id_voluntario is not None:
            efectivo = filtro.model_copy(update={"id_voluntario": actor.id_voluntario})  # forzado desde la sesión
        else:
            raise ForbiddenError("No tiene acceso a las entregas.")
        filas, total = self.repo.listar(**kwargs_filtro(efectivo))
        return a_pagina(filas, total, efectivo, EntregaOut)

    def obtener(self, id_entrega: int, actor: UsuarioActualOut) -> EntregaOut:
        fila = existente(self.repo.obtener(id_entrega), "La entrega")
        if not actor.tiene(P.ENTREGAS_LEER) and fila["id_voluntario"] != actor.id_voluntario:
            raise NotFoundError("La entrega no existe.")  # 404 y no 403: no se revela que existe
        return EntregaOut.model_validate(fila)

    def crear(self, datos: EntregaIn, actor: UsuarioActualOut) -> EntregaOut:
        nuevo = self.repo.crear(**datos.model_dump(), id_actor=actor.id_usuario)
        return EntregaOut.model_validate(existente(self.repo.obtener(nuevo), "La entrega"))

    def cambiar_estado(self, id_entrega: int, datos: EntregaEstadoIn, actor: UsuarioActualOut) -> EntregaOut:
        if datos.estado in ("No realizada", "Anulada") and not (datos.motivo or "").strip():
            raise BusinessRuleError("Indique el motivo.")
        if not actor.tiene(P.ENTREGAS_GESTIONAR):
            actual = self.obtener(id_entrega, actor)  # 404 si no es suya
            if not actor.tiene(P.ENTREGAS_PROPIAS) or actual.id_voluntario != actor.id_voluntario:
                raise ForbiddenError("No puede modificar esta entrega.")
            if datos.estado == "Anulada":
                raise ForbiddenError("Solo coordinación puede anular entregas.")
        self.repo.cambiar_estado(id_entrega=id_entrega, nuevo_estado=datos.estado, motivo=datos.motivo,
                                 fecha=datos.fecha, id_actor=actor.id_usuario)
        return EntregaOut.model_validate(existente(self.repo.obtener(id_entrega), "La entrega"))

    def exportar_csv(self, filtro: FiltroEntregas, actor: UsuarioActualOut, ip: str | None) -> str:
        kw = kwargs_filtro(filtro)
        kw.update(pagina=1, tamano=EXPORT_MAX_FILAS)
        filas, _ = self.repo.listar(**kw)
        self.auditoria.registrar(id_usuario=actor.id_usuario, accion="EXPORTAR", entidad="entrega", id_entidad=None,
                                 detalle=f"{len(filas)} filas", ip=ip)
        return to_csv(filas, COLUMNAS_ENTREGAS)


class FeedbackService:
    def __init__(self, repo: FeedbackRepository) -> None:
        self.repo = repo

    @staticmethod
    def _ve_confidenciales(actor: UsuarioActualOut) -> bool:
        return actor.tiene(P.FEEDBACK_CONFIDENCIAL)

    def listar(self, filtro: FiltroFeedback, actor: UsuarioActualOut) -> Pagina[FeedbackOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro), incluir_confidenciales=self._ve_confidenciales(actor))
        return a_pagina(filas, total, filtro, FeedbackOut)

    def obtener(self, id_retroalimentacion: int, actor: UsuarioActualOut) -> FeedbackOut:
        fila = self.repo.obtener(id_retroalimentacion, incluir_confidenciales=self._ve_confidenciales(actor))
        return FeedbackOut.model_validate(existente(fila, "El registro"))

    def crear(self, datos: FeedbackIn, actor: UsuarioActualOut) -> None:
        """No se devuelve el registro: quien lo crea como confidencial podría no tener permiso de lectura."""
        self.repo.crear(**datos.model_dump(), id_actor=actor.id_usuario)

    def gestionar(self, id_retroalimentacion: int, datos: FeedbackGestionIn, actor: UsuarioActualOut) -> FeedbackOut:
        self.repo.gestionar(id_retroalimentacion=id_retroalimentacion, nuevo_estado=datos.estado,
                            respuesta=datos.respuesta, id_responsable=datos.id_responsable,
                            incluir_confidenciales=self._ve_confidenciales(actor), id_actor=actor.id_usuario)
        return self.obtener(id_retroalimentacion, actor)

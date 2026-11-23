"""Campañas, donantes, donaciones y gastos."""
from __future__ import annotations

from app.core import permissions as P
from app.core.errors import BusinessRuleError, ForbiddenError
from app.core.utils import to_csv
from app.repositories.finanzas import CampanaRepository, DonacionRepository, DonanteRepository, GastoRepository
from app.repositories.seguridad import AuditoriaRepository
from app.schemas.auth import UsuarioActualOut
from app.schemas.common import Pagina
from app.schemas.finanzas import (
    CampanaEstadoIn, CampanaIn, CampanaOut, CierreCampanaOut, DonacionEstadoIn, DonacionIn, DonacionOut,
    DonanteIn, DonanteOut, FeedbackCierreOut, FiltroCampanas, FiltroDonaciones, FiltroDonantes, FiltroGastos,
    GastoEstadoIn, GastoIn, GastoOut, PorMetodoOut, PorSectorCierreOut, PorTipoOut,
)
from app.services.base import a_pagina, existente, kwargs_filtro

EXPORT_MAX_FILAS = 50_000


class CampanaService:
    def __init__(self, repo: CampanaRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroCampanas) -> Pagina[CampanaOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, CampanaOut)

    def obtener(self, id_campana: int) -> CampanaOut:
        return CampanaOut.model_validate(existente(self.repo.obtener(id_campana), "La campaña"))

    def crear(self, datos: CampanaIn, actor: UsuarioActualOut) -> CampanaOut:
        nuevo = self.repo.guardar(id_campana=None, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_campana: int, datos: CampanaIn, actor: UsuarioActualOut) -> CampanaOut:
        self.repo.guardar(id_campana=id_campana, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(id_campana)

    def cambiar_estado(self, id_campana: int, datos: CampanaEstadoIn, actor: UsuarioActualOut) -> CampanaOut:
        if datos.estado == "Cancelada" and not (datos.motivo or "").strip():
            raise BusinessRuleError("Indique el motivo de la cancelación.")
        self.repo.cambiar_estado(id_campana=id_campana, nuevo_estado=datos.estado, motivo=datos.motivo,
                                 id_actor=actor.id_usuario)
        return self.obtener(id_campana)

    def cierre(self, id_campana: int) -> CierreCampanaOut:
        resumen, metodos, gastos, sectores, feedback = self.repo.cierre(id_campana)
        return CierreCampanaOut(
            resumen=CampanaOut.model_validate(existente(resumen[0] if resumen else None, "La campaña")),
            donaciones_por_metodo=[PorMetodoOut.model_validate(f) for f in metodos],
            gastos_por_tipo=[PorTipoOut.model_validate(f) for f in gastos],
            entregas_por_sector=[PorSectorCierreOut.model_validate(f) for f in sectores],
            retroalimentacion=FeedbackCierreOut.model_validate(feedback[0]),
        )


class DonanteService:
    def __init__(self, repo: DonanteRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroDonantes) -> Pagina[DonanteOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, DonanteOut)

    def obtener(self, id_donante: int) -> DonanteOut:
        return DonanteOut.model_validate(existente(self.repo.obtener(id_donante), "El donante"))

    def crear(self, datos: DonanteIn, actor: UsuarioActualOut) -> DonanteOut:
        nuevo = self.repo.guardar(id_donante=None, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_donante: int, datos: DonanteIn, actor: UsuarioActualOut) -> DonanteOut:
        self.repo.guardar(id_donante=id_donante, **datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(id_donante)

    def cambiar_estado(self, id_donante: int, activo: bool, actor: UsuarioActualOut) -> DonanteOut:
        self.repo.cambiar_estado(id_donante=id_donante, activo=activo, id_actor=actor.id_usuario)
        return self.obtener(id_donante)


COLUMNAS_DONACIONES = [
    ("id_donacion", "N.º"), ("fecha", "Fecha"), ("donante", "Donante"), ("campana", "Campaña"),
    ("monto", "Monto"), ("moneda", "Moneda"), ("metodo_pago", "Método de pago"), ("referencia", "Referencia"),
    ("estado", "Estado"),
]


class DonacionService:
    def __init__(self, repo: DonacionRepository, auditoria: AuditoriaRepository) -> None:
        self.repo, self.auditoria = repo, auditoria

    def listar(self, filtro: FiltroDonaciones) -> Pagina[DonacionOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, DonacionOut)

    def listar_propias(self, actor: UsuarioActualOut, filtro: FiltroDonaciones) -> Pagina[DonacionOut]:
        """Portal del donante: el filtro por donante se FUERZA desde la sesión; nunca desde la petición."""
        if actor.id_donante is None:
            raise ForbiddenError("Su cuenta no está vinculada a un donante.")
        return self.listar(filtro.model_copy(update={"id_donante": actor.id_donante}))

    def obtener(self, id_donacion: int) -> DonacionOut:
        return DonacionOut.model_validate(existente(self.repo.obtener(id_donacion), "La donación"))

    def crear(self, datos: DonacionIn, actor: UsuarioActualOut) -> DonacionOut:
        if datos.confirmar and not actor.tiene(P.DONACIONES_VERIFICAR):
            raise ForbiddenError("No tiene permiso para confirmar donaciones al registrarlas.")
        nuevo = self.repo.crear(**datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def cambiar_estado(self, id_donacion: int, datos: DonacionEstadoIn, actor: UsuarioActualOut) -> DonacionOut:
        if datos.estado in ("Rechazada", "Anulada") and not (datos.motivo or "").strip():
            raise BusinessRuleError("Indique el motivo.")
        self.repo.cambiar_estado(id_donacion=id_donacion, nuevo_estado=datos.estado, motivo=datos.motivo,
                                 id_actor=actor.id_usuario)
        return self.obtener(id_donacion)

    def exportar_csv(self, filtro: FiltroDonaciones, actor: UsuarioActualOut, ip: str | None) -> str:
        kw = kwargs_filtro(filtro)
        kw.update(pagina=1, tamano=EXPORT_MAX_FILAS)
        filas, total = self.repo.listar(**kw)
        self.auditoria.registrar(id_usuario=actor.id_usuario, accion="EXPORTAR", entidad="donacion", id_entidad=None,
                                 detalle=f"{len(filas)} filas", ip=ip)
        return to_csv(filas, COLUMNAS_DONACIONES)


class GastoService:
    def __init__(self, repo: GastoRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroGastos) -> Pagina[GastoOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, GastoOut)

    def obtener(self, id_gasto: int) -> GastoOut:
        return GastoOut.model_validate(existente(self.repo.obtener(id_gasto), "El gasto"))

    def crear(self, datos: GastoIn, actor: UsuarioActualOut) -> GastoOut:
        nuevo = self.repo.crear(**datos.model_dump(), id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def cambiar_estado(self, id_gasto: int, datos: GastoEstadoIn, actor: UsuarioActualOut) -> GastoOut:
        if datos.estado == "Anulado" and not (datos.motivo or "").strip():
            raise BusinessRuleError("Indique el motivo de la anulación.")
        if datos.estado == "Aprobado" and not actor.tiene(P.GASTOS_APROBAR):
            raise ForbiddenError("No tiene permiso para aprobar gastos.")
        self.repo.cambiar_estado(id_gasto=id_gasto, nuevo_estado=datos.estado, motivo=datos.motivo,
                                 id_actor=actor.id_usuario)
        return self.obtener(id_gasto)

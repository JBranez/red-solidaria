"""Campañas, donantes, donaciones y gastos."""
from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import Field, model_validator

from app.schemas.common import (
    ConCorreo, ConMotivo, Entrada, EstadoCampana, EstadoDonacion, EstadoGasto, FiltroBase,
    Salida, TipoDonante, TipoGasto,
)

Dinero = Field(gt=0, le=Decimal("99999999.99"), max_digits=10, decimal_places=2)


# =============================== CAMPAÑAS ===============================
class CampanaIn(Entrada):
    nombre: str = Field(min_length=3, max_length=100)
    descripcion: str | None = Field(None, max_length=500)
    objetivo_social: str | None = Field(None, max_length=300)
    id_categoria: int
    fecha_inicio: date
    fecha_fin: date
    meta_recaudacion: Decimal = Dinero
    meta_hogares: int | None = Field(None, gt=0, le=100_000)
    meta_unidades: int | None = Field(None, gt=0, le=1_000_000)
    moneda: str = Field("PEN", pattern=r"^[A-Z]{3}$")
    id_responsable: int | None = None

    @model_validator(mode="after")
    def _fechas(self) -> "CampanaIn":
        if self.fecha_fin < self.fecha_inicio:
            raise ValueError("La fecha de fin no puede ser anterior a la de inicio.")
        return self


class CampanaEstadoIn(ConMotivo):
    estado: EstadoCampana


class CampanaOut(Salida):
    id_campana: int
    nombre: str
    descripcion: str | None = None
    objetivo_social: str | None = None
    id_categoria: int
    categoria: str
    fecha_inicio: date
    fecha_fin: date
    estado: EstadoCampana
    moneda: str
    meta_recaudacion: float
    meta_hogares: int | None = None
    meta_unidades: int | None = None
    id_responsable: int | None = None
    responsable: str | None = None
    cerrada_en: datetime | None = None
    motivo_cierre: str | None = None
    creado_en: datetime
    recaudado_confirmado: float
    recaudado_pendiente: float
    donaciones_confirmadas: int
    donaciones_pendientes: int
    donantes: int
    gastado_aprobado: float
    saldo_disponible: float
    entregas_realizadas: int
    hogares_atendidos: int
    unidades_entregadas: int
    voluntarios_participantes: int
    entregas_programadas: int
    pct_meta_recaudacion: float
    pct_meta_hogares: float | None = None
    pct_meta_unidades: float | None = None
    dias_restantes: int


class FiltroCampanas(FiltroBase):
    estado: EstadoCampana | None = None
    id_categoria: int | None = None
    desde: date | None = None
    hasta: date | None = None
    orden: Literal["nombre", "fecha_inicio", "recaudado", "avance"] | None = None
    desc: bool = False


class PorMetodoOut(Salida):
    metodo: str
    cantidad: int
    total: float


class PorTipoOut(Salida):
    tipo: str
    cantidad: int
    total: float


class PorSectorCierreOut(Salida):
    sector: str
    hogares: int
    entregas: int
    unidades: int


class FeedbackCierreOut(Salida):
    total: int
    satisfaccion_promedio: float | None = None
    quejas: int
    quejas_abiertas: int


class CierreCampanaOut(Salida):
    resumen: CampanaOut
    donaciones_por_metodo: list[PorMetodoOut]
    gastos_por_tipo: list[PorTipoOut]
    entregas_por_sector: list[PorSectorCierreOut]
    retroalimentacion: FeedbackCierreOut


# =============================== DONANTES ===============================
class DonanteIn(ConCorreo):
    nombre: str = Field(min_length=2, max_length=100)
    tipo: TipoDonante
    confirmar_duplicado: bool = False


class DonanteOut(Salida):
    id_donante: int
    nombre: str
    tipo: TipoDonante
    correo: str
    fecha_registro: date
    activo: bool
    creado_en: datetime
    total_donado: float
    donaciones_confirmadas: int
    donaciones_pendientes: int
    campanas_apoyadas: int
    ultima_donacion: date | None = None


class FiltroDonantes(FiltroBase):
    tipo: TipoDonante | None = None
    activo: bool | None = None
    orden: Literal["nombre", "total_donado", "ultima_donacion"] | None = None
    desc: bool = False


# =============================== DONACIONES ===============================
class DonacionIn(Entrada):
    id_donante: int
    id_campana: int
    fecha: date
    monto: Decimal = Dinero
    id_metodo_pago: int
    referencia: str | None = Field(None, max_length=60)
    observacion: str | None = Field(None, max_length=200)
    confirmar: bool = False
    confirmar_duplicado: bool = False


class DonacionEstadoIn(ConMotivo):
    estado: Literal["Confirmada", "Rechazada", "Anulada"]


class DonacionOut(Salida):
    id_donacion: int
    fecha: date
    monto: float
    moneda: str
    estado: EstadoDonacion
    referencia: str | None = None
    observacion: str | None = None
    motivo_estado: str | None = None
    id_donante: int
    donante: str
    donante_tipo: TipoDonante
    id_campana: int
    campana: str
    id_metodo_pago: int
    metodo_pago: str
    confirmado_en: datetime | None = None
    confirmado_por: str | None = None
    creado_en: datetime


class FiltroDonaciones(FiltroBase):
    id_campana: int | None = None
    id_donante: int | None = None
    estado: EstadoDonacion | None = None
    id_metodo_pago: int | None = None
    desde: date | None = None
    hasta: date | None = None
    orden: Literal["fecha", "monto", "donante"] | None = None
    desc: bool = True


# =============================== GASTOS ===============================
class GastoIn(Entrada):
    id_campana: int
    fecha: date
    concepto: str = Field(min_length=3, max_length=150)
    tipo: TipoGasto
    proveedor: str | None = Field(None, max_length=100)
    monto: Decimal = Dinero
    comprobante: str | None = Field(None, max_length=60)


class GastoEstadoIn(ConMotivo):
    estado: Literal["Aprobado", "Anulado"]


class GastoOut(Salida):
    id_gasto: int
    id_campana: int
    campana: str
    moneda: str
    fecha: date
    concepto: str
    tipo: TipoGasto
    proveedor: str | None = None
    monto: float
    comprobante: str | None = None
    estado: EstadoGasto
    motivo_estado: str | None = None
    id_usuario_registra: int | None = None
    registrado_por: str | None = None
    id_aprobador: int | None = None
    aprobado_por: str | None = None
    aprobado_en: datetime | None = None
    creado_en: datetime


class FiltroGastos(FiltroBase):
    id_campana: int | None = None
    estado: EstadoGasto | None = None
    tipo: TipoGasto | None = None
    desde: date | None = None
    hasta: date | None = None

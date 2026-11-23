"""Hogares, necesidades, voluntarios, entregas y retroalimentación."""
from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import Field

from app.schemas.common import (
    ConCorreo, ConMotivo, Entrada, EstadoEntrega, EstadoFeedback, EstadoNecesidad, FiltroBase,
    Salida, TipoFeedback, Urgencia,
)


# =============================== HOGARES ===============================
class BeneficiarioIn(Entrada):
    nombres: str = Field(min_length=2, max_length=60)
    apellidos: str = Field(min_length=2, max_length=60)
    id_sector: int
    integrantes_hogar: int = Field(ge=1, le=30)
    consentimiento_datos: bool = False
    confirmar_duplicado: bool = False


class BeneficiarioOut(Salida):
    id_beneficiario: int
    nombres: str
    apellidos: str
    nombre_completo: str
    id_sector: int
    sector: str
    integrantes_hogar: int
    fecha_registro: date
    consentimiento_datos: bool
    fecha_consentimiento: date | None = None
    activo: bool
    creado_en: datetime
    entregas_recibidas: int
    unidades_recibidas: int
    ultima_entrega: date | None = None
    necesidades_abiertas: int


class FiltroBeneficiarios(FiltroBase):
    id_sector: int | None = None
    activo: bool | None = None
    sin_consentimiento: bool = False
    sin_entregas: bool = False
    con_necesidades: bool = False
    orden: Literal["nombre", "integrantes", "ultima_entrega"] | None = None
    desc: bool = False


# =============================== NECESIDADES ===============================
class NecesidadIn(Entrada):
    id_beneficiario: int
    id_categoria: int
    urgencia: Urgencia
    descripcion: str | None = Field(None, max_length=300)


class NecesidadEdicionIn(Entrada):
    id_categoria: int
    urgencia: Urgencia
    descripcion: str | None = Field(None, max_length=300)


class NecesidadEstadoIn(ConMotivo):
    estado: EstadoNecesidad


class NecesidadOut(Salida):
    id_necesidad: int
    id_beneficiario: int
    hogar: str
    id_sector: int
    sector: str
    integrantes_hogar: int
    id_categoria: int
    categoria: str
    urgencia: Urgencia
    estado: EstadoNecesidad
    descripcion: str | None = None
    fecha_registro: date
    fecha_cobertura: date | None = None
    motivo_estado: str | None = None
    prioridad: int
    dias_espera: int
    registrado_por: str | None = None
    creado_en: datetime


class FiltroNecesidades(FiltroBase):
    id_beneficiario: int | None = None
    id_categoria: int | None = None
    id_sector: int | None = None
    estado: EstadoNecesidad | None = None
    urgencia: Urgencia | None = None
    solo_abiertas: bool = False


# =============================== VOLUNTARIOS ===============================
class VoluntarioIn(ConCorreo):
    nombres: str = Field(min_length=2, max_length=60)
    apellidos: str = Field(min_length=2, max_length=60)
    fecha_ingreso: date | None = None


class VoluntarioOut(Salida):
    id_voluntario: int
    nombres: str
    apellidos: str
    nombre_completo: str
    correo: str
    fecha_ingreso: date
    activo: bool
    creado_en: datetime
    entregas_realizadas: int
    unidades_entregadas: int
    campanas_participadas: int
    entregas_programadas: int
    ultima_entrega: date | None = None


class FiltroVoluntarios(FiltroBase):
    activo: bool | None = None
    orden: Literal["entregas", "ingreso"] | None = None
    desc: bool = False


# =============================== ENTREGAS ===============================
class EntregaIn(Entrada):
    id_campana: int
    id_beneficiario: int
    id_voluntario: int
    fecha: date
    cantidad: int = Field(ge=1, le=1000)
    detalle: str | None = Field(None, max_length=200)
    estado: Literal["Entregada", "Programada"] = "Entregada"
    id_necesidad: int | None = None
    confirmar_repetida: bool = False


class EntregaEstadoIn(ConMotivo):
    estado: Literal["Entregada", "No realizada", "Anulada"]
    fecha: date | None = None


class EntregaOut(Salida):
    id_entrega: int
    fecha: date
    cantidad: int
    detalle: str | None = None
    estado: EstadoEntrega
    motivo_estado: str | None = None
    id_campana: int
    campana: str
    categoria: str
    id_beneficiario: int
    hogar: str
    id_sector: int
    sector: str
    integrantes_hogar: int
    id_voluntario: int
    voluntario: str
    id_necesidad: int | None = None
    creado_en: datetime


class FiltroEntregas(FiltroBase):
    id_campana: int | None = None
    id_beneficiario: int | None = None
    id_voluntario: int | None = None
    id_sector: int | None = None
    estado: EstadoEntrega | None = None
    desde: date | None = None
    hasta: date | None = None
    orden: Literal["fecha", "cantidad", "hogar"] | None = None
    desc: bool = True


# =============================== RETROALIMENTACIÓN ===============================
class FeedbackIn(Entrada):
    tipo: TipoFeedback
    mensaje: str = Field(min_length=3, max_length=1000)
    calificacion: int | None = Field(None, ge=1, le=5)
    id_beneficiario: int | None = None
    id_entrega: int | None = None
    id_campana: int | None = None
    confidencial: bool = False


class FeedbackGestionIn(Entrada):
    estado: EstadoFeedback
    respuesta: str | None = Field(None, max_length=1000)
    id_responsable: int | None = None


class FeedbackOut(Salida):
    id_retroalimentacion: int
    tipo: TipoFeedback
    mensaje: str
    calificacion: int | None = None
    estado: EstadoFeedback
    confidencial: bool
    id_beneficiario: int | None = None
    hogar: str | None = None
    id_entrega: int | None = None
    id_campana: int | None = None
    campana: str | None = None
    id_responsable: int | None = None
    responsable: str | None = None
    respuesta: str | None = None
    fecha_limite: date
    vencida: bool
    dias_para_vencer: int
    resuelta_en: datetime | None = None
    creado_en: datetime


class FiltroFeedback(FiltroBase):
    tipo: TipoFeedback | None = None
    estado: EstadoFeedback | None = None
    id_campana: int | None = None
    id_beneficiario: int | None = None
    vencidas: bool = False

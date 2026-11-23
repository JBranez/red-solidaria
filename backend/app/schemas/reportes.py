"""Dashboard, reportes y portal público."""
from __future__ import annotations

from datetime import date

from app.schemas.common import Salida


class KpiFinanciero(Salida):
    recaudado_confirmado: float
    recaudado_pendiente: float
    donaciones_confirmadas: int
    donaciones_pendientes: int
    gastado_aprobado: float
    saldo_disponible: float
    meta_recaudacion: float
    pct_meta: float | None = None
    ticket_promedio: float | None = None
    donantes_activos: int
    moneda: str


class KpiCobertura(Salida):
    hogares_registrados: int
    hogares_atendidos: int
    hogares_sin_atender: int
    pct_cobertura: float | None = None
    personas_estimadas: int
    entregas_realizadas: int
    unidades_entregadas: int
    entregas_programadas: int
    hogares_sin_consentimiento: int


class KpiOperacion(Salida):
    campanas_activas: int
    campanas_borrador: int
    campanas_pausadas: int
    campanas_finalizadas: int
    campanas_por_vencer: int
    campanas_vencidas_sin_cerrar: int
    voluntarios_activos: int
    voluntarios_participantes: int
    entregas_programadas_vencidas: int
    donaciones_por_verificar: int
    gastos_por_aprobar: int


class KpiResultados(Salida):
    necesidades_abiertas: int
    necesidades_cubiertas: int
    necesidades_urgentes: int
    pct_necesidades_cubiertas: float | None = None
    dias_promedio_cobertura: float | None = None
    satisfaccion_promedio: float | None = None
    feedback_abierto: int
    feedback_vencido: int
    pct_quejas_en_plazo: float | None = None


class KpisOut(Salida):
    financiero: KpiFinanciero
    cobertura: KpiCobertura
    operacion: KpiOperacion
    resultados: KpiResultados


class SerieMensualOut(Salida):
    mes: str
    donaciones: float
    n_donaciones: int
    entregas: int
    unidades: int


class PorCategoriaOut(Salida):
    id_categoria: int
    categoria: str
    campanas: int
    recaudado: float
    gastado: float
    entregas: int
    unidades: int
    hogares: int


class PorSectorOut(Salida):
    id_sector: int
    sector: str
    hogares_registrados: int
    hogares_atendidos: int
    personas_estimadas: int
    entregas: int
    unidades: int
    pct_cobertura: float | None = None
    necesidades_abiertas: int


class TopDonanteOut(Salida):
    id_donante: int
    nombre: str
    tipo: str
    donaciones: int
    total_donado: float
    campanas: int


# ---- Público ----------------------------------------------------------------
class PublicoTotalesOut(Salida):
    campanas_activas: int
    campanas_finalizadas: int
    recaudado_confirmado: float
    gastado_aprobado: float
    hogares_atendidos: int
    entregas_realizadas: int
    voluntarios_participantes: int
    donantes: int
    moneda: str


class PublicoSectorOut(Salida):
    sector: str
    hogares_atendidos: int | None = None  # None = "menos de 3" (supresión de celdas pequeñas)
    publicable: bool


class PublicoCategoriaOut(Salida):
    categoria: str
    recaudado: float
    entregas: int
    unidades: int


class PublicoResumenOut(Salida):
    totales: PublicoTotalesOut
    por_sector: list[PublicoSectorOut]
    por_categoria: list[PublicoCategoriaOut]


class PublicoCampanaOut(Salida):
    id_campana: int
    nombre: str
    categoria: str
    descripcion: str | None = None
    objetivo_social: str | None = None
    fecha_inicio: date
    fecha_fin: date
    estado: str
    moneda: str
    meta_recaudacion: float
    recaudado_confirmado: float
    pct_meta_recaudacion: float
    gastado_aprobado: float
    saldo_disponible: float
    meta_hogares: int | None = None
    hogares_atendidos: int
    pct_meta_hogares: float | None = None
    unidades_entregadas: int
    dias_restantes: int

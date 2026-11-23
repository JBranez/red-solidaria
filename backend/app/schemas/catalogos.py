"""Categorías de ayuda, sectores y métodos de pago."""
from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.schemas.common import Entrada, Salida


class CategoriaIn(Entrada):
    nombre: str = Field(min_length=2, max_length=50)
    descripcion: str = Field(min_length=3, max_length=150)


class CategoriaOut(Salida):
    id_categoria: int
    nombre: str
    descripcion: str
    activo: bool
    creado_en: datetime
    campanas: int
    campanas_vigentes: int


class SectorIn(Entrada):
    nombre: str = Field(min_length=2, max_length=60)


class SectorOut(Salida):
    id_sector: int
    nombre: str
    activo: bool
    creado_en: datetime
    hogares: int


class MetodoPagoOut(Salida):
    id_metodo_pago: int
    nombre: str
    requiere_referencia: bool
    activo: bool

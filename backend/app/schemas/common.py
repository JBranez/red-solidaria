"""Tipos y bases comunes de los esquemas Pydantic."""
from __future__ import annotations

import re
from typing import Annotated, Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

T = TypeVar("T")

EstadoCampana = Literal["Borrador", "Activa", "Pausada", "Finalizada", "Cancelada"]
EstadoDonacion = Literal["Pendiente", "Confirmada", "Rechazada", "Anulada"]
EstadoGasto = Literal["Registrado", "Aprobado", "Anulado"]
EstadoEntrega = Literal["Programada", "Entregada", "No realizada", "Anulada"]
EstadoNecesidad = Literal["Pendiente", "En atencion", "Cubierta", "Descartada"]
Urgencia = Literal["Baja", "Media", "Alta", "Critica"]
TipoDonante = Literal["Persona", "Empresa"]
TipoGasto = Literal["Bienes", "Transporte", "Logistica", "Administrativo", "Otro"]
TipoFeedback = Literal["Consulta", "Sugerencia", "Queja", "Felicitacion"]
EstadoFeedback = Literal["Abierta", "En revision", "Resuelta", "Cerrada"]

_CORREO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
Texto = Annotated[str, StringConstraints(strip_whitespace=True)]


class Entrada(BaseModel):
    """Base de los cuerpos de petición: se recortan espacios y se rechazan campos desconocidos."""

    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")


class Salida(BaseModel):
    model_config = ConfigDict(from_attributes=True, extra="ignore")


class Pagina(BaseModel, Generic[T]):
    items: list[T]
    total: int
    pagina: int
    tamano: int


class FiltroBase(BaseModel):
    """Parámetros de consulta comunes. `extra=forbid` rechaza filtros mal escritos en vez de ignorarlos."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    pagina: int = Field(1, ge=1, le=100_000)
    tamano: int = Field(25, ge=1, le=100)
    q: str | None = Field(None, max_length=100)


class ConMotivo(Entrada):
    motivo: str | None = Field(None, max_length=200)


class CambioActivo(Entrada):
    activo: bool


class IdCreado(Salida):
    id: int


def validar_correo(valor: str) -> str:
    valor = valor.strip().lower()
    if len(valor) > 100 or not _CORREO.match(valor):
        raise ValueError("Ingrese un correo electrónico válido.")
    return valor


class ConCorreo(Entrada):
    correo: str

    @field_validator("correo")
    @classmethod
    def _correo(cls, v: str) -> str:
        return validar_correo(v)


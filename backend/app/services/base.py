"""Ayudas comunes de la capa de servicios."""
from __future__ import annotations

from typing import Any, Iterable, TypeVar

from pydantic import BaseModel

from app.core.errors import NotFoundError
from app.core.utils import like_pattern
from app.schemas.common import FiltroBase, Pagina

M = TypeVar("M", bound=BaseModel)
Fila = dict[str, Any]


def kwargs_filtro(filtro: FiltroBase, *, excluir: Iterable[str] = ()) -> dict[str, Any]:
    """Convierte un modelo de filtros en argumentos del repositorio (escapando el texto de búsqueda)."""
    datos = filtro.model_dump(exclude=set(excluir))
    if "q" in datos:
        datos["q"] = like_pattern(datos["q"])
    return datos


def a_pagina(filas: list[Fila], total: int, filtro: FiltroBase, modelo: type[M]) -> Pagina[M]:
    return Pagina[modelo](  # type: ignore[valid-type]
        items=[modelo.model_validate(f) for f in filas], total=total, pagina=filtro.pagina, tamano=filtro.tamano
    )


def existente(fila: Fila | None, que: str) -> Fila:
    if fila is None:
        raise NotFoundError(f"{que} no existe.")
    return fila

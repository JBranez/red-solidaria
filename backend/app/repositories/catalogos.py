"""Categorías de ayuda, sectores y métodos de pago."""
from __future__ import annotations

from typing import Any

from app.db.executor import Executor

Fila = dict[str, Any]


class CatalogoRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    # -- categorías
    def categorias(self, *, solo_activas: bool) -> list[Fila]:
        return self.db.fetch_all("usp_categoria_listar", solo_activas=solo_activas)

    def categoria(self, id_categoria: int) -> Fila | None:
        return self.db.fetch_one("usp_categoria_listar", id=id_categoria)

    def categoria_guardar(self, *, id_categoria: int | None, nombre: str, descripcion: str, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_categoria_guardar", id_categoria=id_categoria, nombre=nombre,
                                 descripcion=descripcion, id_actor=id_actor)
        return int(fila["id_categoria"])  # type: ignore[index]

    def categoria_estado(self, *, id_categoria: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_categoria_estado", id_categoria=id_categoria, activo=activo, id_actor=id_actor)

    # -- sectores
    def sectores(self, *, solo_activos: bool) -> list[Fila]:
        return self.db.fetch_all("usp_sector_listar", solo_activos=solo_activos)

    def sector(self, id_sector: int) -> Fila | None:
        return self.db.fetch_one("usp_sector_listar", id=id_sector)

    def sector_guardar(self, *, id_sector: int | None, nombre: str, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_sector_guardar", id_sector=id_sector, nombre=nombre, id_actor=id_actor)
        return int(fila["id_sector"])  # type: ignore[index]

    def sector_estado(self, *, id_sector: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_sector_estado", id_sector=id_sector, activo=activo, id_actor=id_actor)

    # -- métodos de pago
    def metodos_pago(self, *, solo_activos: bool) -> list[Fila]:
        return self.db.fetch_all("usp_metodo_pago_listar", solo_activos=solo_activos)

"""Categorías de ayuda, sectores y métodos de pago."""
from __future__ import annotations

from app.repositories.catalogos import CatalogoRepository
from app.schemas.auth import UsuarioActualOut
from app.schemas.catalogos import CategoriaIn, CategoriaOut, MetodoPagoOut, SectorIn, SectorOut
from app.services.base import existente


class CatalogoService:
    def __init__(self, repo: CatalogoRepository) -> None:
        self.repo = repo

    # categorías
    def categorias(self, solo_activas: bool = False) -> list[CategoriaOut]:
        return [CategoriaOut.model_validate(f) for f in self.repo.categorias(solo_activas=solo_activas)]

    def categoria(self, id_categoria: int) -> CategoriaOut:
        return CategoriaOut.model_validate(existente(self.repo.categoria(id_categoria), "La categoría"))

    def categoria_guardar(self, id_categoria: int | None, datos: CategoriaIn, actor: UsuarioActualOut) -> CategoriaOut:
        nuevo = self.repo.categoria_guardar(id_categoria=id_categoria, nombre=datos.nombre,
                                            descripcion=datos.descripcion, id_actor=actor.id_usuario)
        return self.categoria(nuevo)

    def categoria_estado(self, id_categoria: int, activo: bool, actor: UsuarioActualOut) -> CategoriaOut:
        self.repo.categoria_estado(id_categoria=id_categoria, activo=activo, id_actor=actor.id_usuario)
        return self.categoria(id_categoria)

    # sectores
    def sectores(self, solo_activos: bool = False) -> list[SectorOut]:
        return [SectorOut.model_validate(f) for f in self.repo.sectores(solo_activos=solo_activos)]

    def sector(self, id_sector: int) -> SectorOut:
        return SectorOut.model_validate(existente(self.repo.sector(id_sector), "El sector"))

    def sector_guardar(self, id_sector: int | None, datos: SectorIn, actor: UsuarioActualOut) -> SectorOut:
        nuevo = self.repo.sector_guardar(id_sector=id_sector, nombre=datos.nombre, id_actor=actor.id_usuario)
        return self.sector(nuevo)

    def sector_estado(self, id_sector: int, activo: bool, actor: UsuarioActualOut) -> SectorOut:
        self.repo.sector_estado(id_sector=id_sector, activo=activo, id_actor=actor.id_usuario)
        return self.sector(id_sector)

    # métodos de pago
    def metodos_pago(self, solo_activos: bool = True) -> list[MetodoPagoOut]:
        return [MetodoPagoOut.model_validate(f) for f in self.repo.metodos_pago(solo_activos=solo_activos)]

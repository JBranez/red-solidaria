"""Campañas, donantes, donaciones y gastos."""
from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any

from app.db.executor import Executor

Fila = dict[str, Any]


class CampanaRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, estado: str | None, id_categoria: int | None, desde: date | None,
               hasta: date | None, orden: str | None, desc: bool, pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_campana_listar", q=q, estado=estado, id_categoria=id_categoria, desde=desde,
                            hasta=hasta, orden=orden, desc=desc, pagina=pagina, tamano=tamano)

    def obtener(self, id_campana: int) -> Fila | None:
        return self.db.fetch_one("usp_campana_listar", id=id_campana)

    def guardar(self, *, id_campana: int | None, nombre: str, descripcion: str | None, objetivo_social: str | None,
                id_categoria: int, fecha_inicio: date, fecha_fin: date, meta_recaudacion: Decimal,
                meta_hogares: int | None, meta_unidades: int | None, moneda: str, id_responsable: int | None,
                id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_campana_guardar", id_campana=id_campana, nombre=nombre, descripcion=descripcion,
                                 objetivo_social=objetivo_social, id_categoria=id_categoria, fecha_inicio=fecha_inicio,
                                 fecha_fin=fecha_fin, meta_recaudacion=meta_recaudacion, meta_hogares=meta_hogares,
                                 meta_unidades=meta_unidades, moneda=moneda, id_responsable=id_responsable,
                                 id_actor=id_actor)
        return int(fila["id_campana"])  # type: ignore[index]

    def cambiar_estado(self, *, id_campana: int, nuevo_estado: str, motivo: str | None, id_actor: int | None) -> None:
        self.db.execute("usp_campana_estado", id_campana=id_campana, nuevo_estado=nuevo_estado, motivo=motivo,
                        id_actor=id_actor)

    def cierre(self, id_campana: int) -> list[list[Fila]]:
        return self.db.fetch_sets("usp_campana_cierre", id_campana=id_campana)


class DonanteRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, tipo: str | None, activo: bool | None, orden: str | None, desc: bool,
               pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_donante_listar", q=q, tipo=tipo, activo=activo, orden=orden, desc=desc,
                            pagina=pagina, tamano=tamano)

    def obtener(self, id_donante: int) -> Fila | None:
        return self.db.fetch_one("usp_donante_listar", id=id_donante)

    def guardar(self, *, id_donante: int | None, nombre: str, tipo: str, correo: str, confirmar_duplicado: bool,
                id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_donante_guardar", id_donante=id_donante, nombre=nombre, tipo=tipo, correo=correo,
                                 confirmar_duplicado=confirmar_duplicado, id_actor=id_actor)
        return int(fila["id_donante"])  # type: ignore[index]

    def cambiar_estado(self, *, id_donante: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_donante_estado", id_donante=id_donante, activo=activo, id_actor=id_actor)


class DonacionRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, id_campana: int | None, id_donante: int | None, estado: str | None,
               id_metodo_pago: int | None, desde: date | None, hasta: date | None, orden: str | None, desc: bool,
               pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_donacion_listar", q=q, id_campana=id_campana, id_donante=id_donante, estado=estado,
                            id_metodo_pago=id_metodo_pago, desde=desde, hasta=hasta, orden=orden, desc=desc,
                            pagina=pagina, tamano=tamano)

    def obtener(self, id_donacion: int) -> Fila | None:
        return self.db.fetch_one("usp_donacion_listar", id=id_donacion)

    def crear(self, *, id_donante: int, id_campana: int, fecha: date, monto: Decimal, id_metodo_pago: int,
              referencia: str | None, observacion: str | None, confirmar: bool, confirmar_duplicado: bool,
              id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_donacion_crear", id_donante=id_donante, id_campana=id_campana, fecha=fecha,
                                 monto=monto, id_metodo_pago=id_metodo_pago, referencia=referencia,
                                 observacion=observacion, confirmar=confirmar,
                                 confirmar_duplicado=confirmar_duplicado, id_actor=id_actor)
        return int(fila["id_donacion"])  # type: ignore[index]

    def cambiar_estado(self, *, id_donacion: int, nuevo_estado: str, motivo: str | None, id_actor: int | None) -> None:
        self.db.execute("usp_donacion_estado", id_donacion=id_donacion, nuevo_estado=nuevo_estado, motivo=motivo,
                        id_actor=id_actor)


class GastoRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, id_campana: int | None, estado: str | None, tipo: str | None,
               desde: date | None, hasta: date | None, pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_gasto_listar", q=q, id_campana=id_campana, estado=estado, tipo=tipo, desde=desde,
                            hasta=hasta, pagina=pagina, tamano=tamano)

    def obtener(self, id_gasto: int) -> Fila | None:
        return self.db.fetch_one("usp_gasto_listar", id=id_gasto)

    def crear(self, *, id_campana: int, fecha: date, concepto: str, tipo: str, proveedor: str | None,
              monto: Decimal, comprobante: str | None, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_gasto_crear", id_campana=id_campana, fecha=fecha, concepto=concepto, tipo=tipo,
                                 proveedor=proveedor, monto=monto, comprobante=comprobante, id_actor=id_actor)
        return int(fila["id_gasto"])  # type: ignore[index]

    def cambiar_estado(self, *, id_gasto: int, nuevo_estado: str, motivo: str | None, id_actor: int | None) -> None:
        self.db.execute("usp_gasto_estado", id_gasto=id_gasto, nuevo_estado=nuevo_estado, motivo=motivo,
                        id_actor=id_actor)

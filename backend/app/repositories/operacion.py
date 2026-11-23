"""Hogares, necesidades, voluntarios, entregas y retroalimentación."""
from __future__ import annotations

from datetime import date
from typing import Any

from app.db.executor import Executor

Fila = dict[str, Any]


class BeneficiarioRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, id_sector: int | None, activo: bool | None, sin_consentimiento: bool,
               sin_entregas: bool, con_necesidades: bool, orden: str | None, desc: bool, pagina: int,
               tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_beneficiario_listar", q=q, id_sector=id_sector, activo=activo,
                            sin_consentimiento=sin_consentimiento, sin_entregas=sin_entregas,
                            con_necesidades=con_necesidades, orden=orden, desc=desc, pagina=pagina, tamano=tamano)

    def obtener(self, id_beneficiario: int) -> Fila | None:
        return self.db.fetch_one("usp_beneficiario_listar", id=id_beneficiario)

    def guardar(self, *, id_beneficiario: int | None, nombres: str, apellidos: str, id_sector: int,
                integrantes_hogar: int, consentimiento_datos: bool, confirmar_duplicado: bool,
                id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_beneficiario_guardar", id_beneficiario=id_beneficiario, nombres=nombres,
                                 apellidos=apellidos, id_sector=id_sector, integrantes_hogar=integrantes_hogar,
                                 consentimiento_datos=consentimiento_datos, confirmar_duplicado=confirmar_duplicado,
                                 id_actor=id_actor)
        return int(fila["id_beneficiario"])  # type: ignore[index]

    def cambiar_estado(self, *, id_beneficiario: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_beneficiario_estado", id_beneficiario=id_beneficiario, activo=activo, id_actor=id_actor)


class NecesidadRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, id_beneficiario: int | None, id_categoria: int | None, id_sector: int | None,
               estado: str | None, urgencia: str | None, solo_abiertas: bool, pagina: int,
               tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_necesidad_listar", id_beneficiario=id_beneficiario, id_categoria=id_categoria,
                            id_sector=id_sector, estado=estado, urgencia=urgencia, solo_abiertas=solo_abiertas,
                            pagina=pagina, tamano=tamano)

    def obtener(self, id_necesidad: int) -> Fila | None:
        return self.db.fetch_one("usp_necesidad_listar", id=id_necesidad)

    def guardar(self, *, id_necesidad: int | None, id_beneficiario: int, id_categoria: int, urgencia: str,
                descripcion: str | None, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_necesidad_guardar", id_necesidad=id_necesidad, id_beneficiario=id_beneficiario,
                                 id_categoria=id_categoria, urgencia=urgencia, descripcion=descripcion,
                                 id_actor=id_actor)
        return int(fila["id_necesidad"])  # type: ignore[index]

    def cambiar_estado(self, *, id_necesidad: int, nuevo_estado: str, motivo: str | None, id_actor: int | None) -> None:
        self.db.execute("usp_necesidad_estado", id_necesidad=id_necesidad, nuevo_estado=nuevo_estado, motivo=motivo,
                        id_actor=id_actor)


class VoluntarioRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, activo: bool | None, orden: str | None, desc: bool, pagina: int,
               tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_voluntario_listar", q=q, activo=activo, orden=orden, desc=desc, pagina=pagina,
                            tamano=tamano)

    def obtener(self, id_voluntario: int) -> Fila | None:
        return self.db.fetch_one("usp_voluntario_listar", id=id_voluntario)

    def guardar(self, *, id_voluntario: int | None, nombres: str, apellidos: str, correo: str,
                fecha_ingreso: date | None, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_voluntario_guardar", id_voluntario=id_voluntario, nombres=nombres,
                                 apellidos=apellidos, correo=correo, fecha_ingreso=fecha_ingreso, id_actor=id_actor)
        return int(fila["id_voluntario"])  # type: ignore[index]

    def cambiar_estado(self, *, id_voluntario: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_voluntario_estado", id_voluntario=id_voluntario, activo=activo, id_actor=id_actor)


class EntregaRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, id_campana: int | None, id_beneficiario: int | None,
               id_voluntario: int | None, id_sector: int | None, estado: str | None, desde: date | None,
               hasta: date | None, orden: str | None, desc: bool, pagina: int,
               tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_entrega_listar", q=q, id_campana=id_campana, id_beneficiario=id_beneficiario,
                            id_voluntario=id_voluntario, id_sector=id_sector, estado=estado, desde=desde,
                            hasta=hasta, orden=orden, desc=desc, pagina=pagina, tamano=tamano)

    def obtener(self, id_entrega: int) -> Fila | None:
        return self.db.fetch_one("usp_entrega_listar", id=id_entrega)

    def crear(self, *, id_campana: int, id_beneficiario: int, id_voluntario: int, fecha: date, cantidad: int,
              detalle: str | None, estado: str, id_necesidad: int | None, confirmar_repetida: bool,
              id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_entrega_crear", id_campana=id_campana, id_beneficiario=id_beneficiario,
                                 id_voluntario=id_voluntario, fecha=fecha, cantidad=cantidad, detalle=detalle,
                                 estado=estado, id_necesidad=id_necesidad, confirmar_repetida=confirmar_repetida,
                                 id_actor=id_actor)
        return int(fila["id_entrega"])  # type: ignore[index]

    def cambiar_estado(self, *, id_entrega: int, nuevo_estado: str, motivo: str | None, fecha: date | None,
                       id_actor: int | None) -> None:
        self.db.execute("usp_entrega_estado", id_entrega=id_entrega, nuevo_estado=nuevo_estado, motivo=motivo,
                        fecha=fecha, id_actor=id_actor)


class FeedbackRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, tipo: str | None, estado: str | None, id_campana: int | None,
               id_beneficiario: int | None, vencidas: bool, incluir_confidenciales: bool, pagina: int,
               tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_feedback_listar", q=q, tipo=tipo, estado=estado, id_campana=id_campana,
                            id_beneficiario=id_beneficiario, vencidas=vencidas,
                            incluir_confidenciales=incluir_confidenciales, pagina=pagina, tamano=tamano)

    def obtener(self, id_retroalimentacion: int, *, incluir_confidenciales: bool) -> Fila | None:
        return self.db.fetch_one("usp_feedback_listar", id=id_retroalimentacion,
                                 incluir_confidenciales=incluir_confidenciales)

    def crear(self, *, tipo: str, mensaje: str, calificacion: int | None, id_beneficiario: int | None,
              id_entrega: int | None, id_campana: int | None, confidencial: bool, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_feedback_crear", tipo=tipo, mensaje=mensaje, calificacion=calificacion,
                                 id_beneficiario=id_beneficiario, id_entrega=id_entrega, id_campana=id_campana,
                                 confidencial=confidencial, id_actor=id_actor)
        return int(fila["id_retroalimentacion"])  # type: ignore[index]

    def gestionar(self, *, id_retroalimentacion: int, nuevo_estado: str, respuesta: str | None,
                  id_responsable: int | None, incluir_confidenciales: bool, id_actor: int | None) -> None:
        self.db.execute("usp_feedback_gestionar", id_retroalimentacion=id_retroalimentacion,
                        nuevo_estado=nuevo_estado, respuesta=respuesta, id_responsable=id_responsable,
                        incluir_confidenciales=incluir_confidenciales, id_actor=id_actor)

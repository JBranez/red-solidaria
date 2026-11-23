"""Acceso a datos de autenticación, usuarios, roles y auditoría (solo procedimientos almacenados)."""
from __future__ import annotations

from datetime import date
from typing import Any

from app.db.executor import Executor

Fila = dict[str, Any]


class AuditoriaRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def registrar(self, *, id_usuario: int | None, accion: str, entidad: str, id_entidad: int | None,
                  detalle: str | None, ip: str | None) -> None:
        self.db.execute("usp_auditoria_registrar", id_usuario=id_usuario, accion=accion, entidad=entidad,
                        id_entidad=id_entidad, detalle=detalle, ip=ip)

    def listar(self, *, q: str | None, accion: str | None, entidad: str | None, id_usuario: int | None,
               desde: date | None, hasta: date | None, pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_auditoria_listar", q=q, accion=accion, entidad=entidad, id_usuario=id_usuario,
                            desde=desde, hasta=hasta, pagina=pagina, tamano=tamano)


class AuthRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def obtener_credenciales(self, username: str) -> Fila | None:
        return self.db.fetch_one("usp_auth_obtener_credenciales", username=username)

    def registrar_intento(self, *, id_usuario: int, exitoso: bool, ip: str | None,
                          max_intentos: int, minutos_bloqueo: int) -> None:
        self.db.execute("usp_auth_registrar_intento", id_usuario=id_usuario, exitoso=exitoso, ip=ip,
                        max_intentos=max_intentos, minutos_bloqueo=minutos_bloqueo)

    def obtener_usuario(self, id_usuario: int) -> tuple[Fila | None, list[str]]:
        conjuntos = self.db.fetch_sets("usp_auth_obtener_usuario", id_usuario=id_usuario)
        if not conjuntos or not conjuntos[0]:
            return None, []
        permisos = [f["codigo"] for f in conjuntos[1]] if len(conjuntos) > 1 else []
        return conjuntos[0][0], permisos


class UsuarioRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def listar(self, *, q: str | None, id_rol: int | None, activo: bool | None,
               pagina: int, tamano: int) -> tuple[list[Fila], int]:
        return self.db.page("usp_usuario_listar", q=q, id_rol=id_rol, activo=activo, pagina=pagina, tamano=tamano)

    def obtener(self, id_usuario: int) -> Fila | None:
        return self.db.fetch_one("usp_usuario_listar", id=id_usuario)

    def guardar(self, *, id_usuario: int | None, username: str, nombre_completo: str, correo: str,
                password_hash: str | None, id_rol: int, id_donante: int | None, id_voluntario: int | None,
                debe_cambiar_password: bool, id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_usuario_guardar", id_usuario=id_usuario, username=username,
                                 nombre_completo=nombre_completo, correo=correo, password_hash=password_hash,
                                 id_rol=id_rol, id_donante=id_donante, id_voluntario=id_voluntario,
                                 debe_cambiar_password=debe_cambiar_password, id_actor=id_actor)
        return int(fila["id_usuario"])  # type: ignore[index]

    def cambiar_password(self, *, id_usuario: int, password_hash: str, debe_cambiar_password: bool,
                         id_actor: int | None) -> int:
        fila = self.db.fetch_one("usp_usuario_password", id_usuario=id_usuario, password_hash=password_hash,
                                 debe_cambiar_password=debe_cambiar_password, id_actor=id_actor)
        return int(fila["token_version"])  # type: ignore[index]

    def cambiar_estado(self, *, id_usuario: int, activo: bool, id_actor: int | None) -> None:
        self.db.execute("usp_usuario_estado", id_usuario=id_usuario, activo=activo, id_actor=id_actor)

    def roles(self) -> list[Fila]:
        return self.db.fetch_all("usp_rol_listar")

    def matriz(self) -> tuple[list[Fila], list[Fila]]:
        conjuntos = self.db.fetch_sets("usp_rol_matriz")
        return conjuntos[0], conjuntos[1]

"""Autenticación, usuarios, roles y auditoría."""
from __future__ import annotations

import re
from datetime import date, datetime

from pydantic import Field, field_validator, model_validator

from app.schemas.common import ConCorreo, Entrada, FiltroBase, Salida

_USERNAME = re.compile(r"^[a-z0-9._-]{3,50}$")


def validar_password(valor: str, username: str | None = None) -> str:
    """Política: 10+ caracteres, con letras y números, distinta del usuario (NIST 800-63B: longitud > complejidad)."""
    if len(valor) < 10:
        raise ValueError("La contraseña debe tener al menos 10 caracteres.")
    if len(valor) > 128:
        raise ValueError("La contraseña no puede superar 128 caracteres.")
    if not re.search(r"[A-Za-zÁÉÍÓÚáéíóúÑñ]", valor) or not re.search(r"\d", valor):
        raise ValueError("La contraseña debe combinar letras y números.")
    if username and valor.lower() == username.lower():
        raise ValueError("La contraseña no puede ser igual al nombre de usuario.")
    return valor


class LoginIn(Entrada):
    username: str = Field(min_length=1, max_length=50)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("username")
    @classmethod
    def _min(cls, v: str) -> str:
        return v.lower()


class CambiarPasswordIn(Entrada):
    password_actual: str = Field(min_length=1, max_length=128)
    password_nueva: str

    @field_validator("password_nueva")
    @classmethod
    def _pw(cls, v: str) -> str:
        return validar_password(v)

    @model_validator(mode="after")
    def _distinta(self) -> "CambiarPasswordIn":
        if self.password_actual == self.password_nueva:
            raise ValueError("La nueva contraseña debe ser distinta de la actual.")
        return self


class UsuarioActualOut(Salida):
    id_usuario: int
    username: str
    nombre_completo: str
    correo: str
    id_rol: int
    rol_codigo: str
    rol_nombre: str
    id_donante: int | None = None
    id_voluntario: int | None = None
    debe_cambiar_password: bool = False
    permisos: list[str] = []

    def tiene(self, permiso: str) -> bool:
        return permiso in self.permisos


class TokenOut(Salida):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    usuario: UsuarioActualOut


# ---- Usuarios -----------------------------------------------------------------
class UsuarioIn(ConCorreo):
    username: str
    nombre_completo: str = Field(min_length=3, max_length=120)
    password: str | None = None
    id_rol: int
    id_donante: int | None = None
    id_voluntario: int | None = None
    debe_cambiar_password: bool = True

    @field_validator("username")
    @classmethod
    def _user(cls, v: str) -> str:
        v = v.strip().lower()
        if not _USERNAME.match(v):
            raise ValueError("El usuario debe tener 3-50 caracteres: letras minúsculas, números, punto, guion o guion bajo.")
        return v

    @model_validator(mode="after")
    def _pw(self) -> "UsuarioIn":
        if self.password is not None:
            validar_password(self.password, self.username)
        return self


class UsuarioEdicionIn(ConCorreo):
    nombre_completo: str = Field(min_length=3, max_length=120)
    id_rol: int
    id_donante: int | None = None
    id_voluntario: int | None = None


class RestablecerPasswordIn(Entrada):
    password_nueva: str
    debe_cambiar_password: bool = True

    @field_validator("password_nueva")
    @classmethod
    def _pw(cls, v: str) -> str:
        return validar_password(v)


class UsuarioOut(Salida):
    id_usuario: int
    username: str
    nombre_completo: str
    correo: str
    id_rol: int
    rol_codigo: str
    rol_nombre: str
    id_donante: int | None = None
    donante: str | None = None
    id_voluntario: int | None = None
    voluntario: str | None = None
    activo: bool
    debe_cambiar_password: bool
    ultimo_acceso: datetime | None = None
    bloqueado_hasta: datetime | None = None
    creado_en: datetime


class FiltroUsuarios(FiltroBase):
    id_rol: int | None = None
    activo: bool | None = None


class RolOut(Salida):
    id_rol: int
    codigo: str
    nombre: str
    descripcion: str
    permisos: int
    usuarios_activos: int


class PermisoOut(Salida):
    codigo: str
    modulo: str
    descripcion: str


class MatrizOut(Salida):
    roles: list[RolOut]
    permisos: list[PermisoOut]
    asignaciones: dict[str, list[str]]  # rol_codigo -> permisos


# ---- Auditoría ----------------------------------------------------------------
class AuditoriaOut(Salida):
    id_evento: int
    fecha: datetime
    id_usuario: int | None = None
    username: str | None = None
    accion: str
    entidad: str
    id_entidad: int | None = None
    detalle: str | None = None
    ip: str | None = None


class FiltroAuditoria(FiltroBase):
    accion: str | None = Field(None, max_length=30)
    entidad: str | None = Field(None, max_length=40)
    id_usuario: int | None = None
    desde: date | None = None
    hasta: date | None = None

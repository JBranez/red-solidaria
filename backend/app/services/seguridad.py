"""Autenticación, usuarios, roles y auditoría."""
from __future__ import annotations

from typing import Any

from app.core.config import Settings
from app.core.errors import AccountLockedError, BusinessRuleError, UnauthorizedError
from app.core.security import (
    burn_password_check, create_access_token, hash_password, verify_password,
)
from app.repositories.seguridad import AuditoriaRepository, AuthRepository, UsuarioRepository
from app.schemas.auth import (
    AuditoriaOut, FiltroAuditoria, FiltroUsuarios, MatrizOut, PermisoOut, RolOut, TokenOut, UsuarioActualOut,
    UsuarioEdicionIn, UsuarioIn, UsuarioOut, validar_password,
)
from app.schemas.common import Pagina
from app.services.base import a_pagina, existente, kwargs_filtro

CREDENCIALES_INVALIDAS = "Usuario o contraseña incorrectos."


class AuthService:
    def __init__(self, auth: AuthRepository, usuarios: UsuarioRepository, auditoria: AuditoriaRepository,
                 settings: Settings) -> None:
        self.auth, self.usuarios, self.auditoria, self.settings = auth, usuarios, auditoria, settings

    @staticmethod
    def _modelo(fila: dict[str, Any], permisos: list[str]) -> UsuarioActualOut:
        return UsuarioActualOut(**{k: fila[k] for k in UsuarioActualOut.model_fields if k != "permisos"}, permisos=permisos)

    def _token(self, usuario: UsuarioActualOut, token_version: int) -> TokenOut:
        token, expira = create_access_token(user_id=usuario.id_usuario, token_version=token_version, settings=self.settings)
        return TokenOut(access_token=token, expires_in=expira, usuario=usuario)

    def login(self, username: str, password: str, ip: str | None) -> TokenOut:
        cred = self.auth.obtener_credenciales(username)
        if cred is None:
            burn_password_check(password)  # mismo costo que un usuario real: no se puede enumerar por latencia
            self.auditoria.registrar(id_usuario=None, accion="LOGIN_FALLIDO", entidad="usuario", id_entidad=None,
                                     detalle=f"Usuario inexistente: {username[:50]}", ip=ip)
            raise UnauthorizedError(CREDENCIALES_INVALIDAS)
        if cred["bloqueado"]:
            burn_password_check(password)
            raise AccountLockedError("La cuenta está bloqueada temporalmente por intentos fallidos. Intente más tarde.")
        correcta = verify_password(password, cred["password_hash"])
        if not (correcta and cred["activo"]):
            if cred["activo"]:
                self.auth.registrar_intento(id_usuario=cred["id_usuario"], exitoso=False, ip=ip,
                                            max_intentos=self.settings.login_max_attempts,
                                            minutos_bloqueo=self.settings.login_lock_minutes)
            else:
                self.auditoria.registrar(id_usuario=cred["id_usuario"], accion="LOGIN_FALLIDO", entidad="usuario",
                                         id_entidad=cred["id_usuario"], detalle="Cuenta desactivada", ip=ip)
            raise UnauthorizedError(CREDENCIALES_INVALIDAS)  # mismo mensaje: no revela si la cuenta existe o está inactiva
        self.auth.registrar_intento(id_usuario=cred["id_usuario"], exitoso=True, ip=ip,
                                    max_intentos=self.settings.login_max_attempts,
                                    minutos_bloqueo=self.settings.login_lock_minutes)
        fila, permisos = self.auth.obtener_usuario(cred["id_usuario"])
        fila = existente(fila, "El usuario")
        return self._token(self._modelo(fila, permisos), fila["token_version"])

    def autenticar_token(self, payload: dict[str, Any]) -> UsuarioActualOut:
        """Valida el JWT contra el estado ACTUAL del usuario (activo y versión de token)."""
        try:
            id_usuario = int(payload["sub"])
        except (KeyError, ValueError, TypeError) as exc:
            raise UnauthorizedError("Token de autenticación no válido.") from exc
        fila, permisos = self.auth.obtener_usuario(id_usuario)
        if fila is None or not fila["activo"]:
            raise UnauthorizedError("La sesión ya no es válida.", codigo="SESION_INVALIDA")
        if fila["token_version"] != payload.get("tv"):
            raise UnauthorizedError("La sesión fue cerrada. Inicie sesión nuevamente.", codigo="SESION_REVOCADA")
        return self._modelo(fila, permisos)

    def cambiar_password(self, actor: UsuarioActualOut, actual: str, nueva: str) -> TokenOut:
        cred = self.auth.obtener_credenciales(actor.username)
        if cred is None or not verify_password(actual, cred["password_hash"]):
            raise BusinessRuleError("La contraseña actual no es correcta.", codigo="PASSWORD_ACTUAL_INCORRECTA")
        try:
            validar_password(nueva, actor.username)
        except ValueError as exc:
            raise BusinessRuleError(str(exc)) from exc
        version = self.usuarios.cambiar_password(id_usuario=actor.id_usuario, password_hash=hash_password(nueva),
                                                 debe_cambiar_password=False, id_actor=actor.id_usuario)
        return self._token(actor.model_copy(update={"debe_cambiar_password": False}), version)

    def cerrar_sesion(self, actor: UsuarioActualOut, ip: str | None) -> None:
        self.auditoria.registrar(id_usuario=actor.id_usuario, accion="LOGOUT", entidad="usuario",
                                 id_entidad=actor.id_usuario, detalle=None, ip=ip)


class UsuarioService:
    def __init__(self, repo: UsuarioRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroUsuarios) -> Pagina[UsuarioOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, UsuarioOut)

    def obtener(self, id_usuario: int) -> UsuarioOut:
        return UsuarioOut.model_validate(existente(self.repo.obtener(id_usuario), "El usuario"))

    def _validar_vinculos(self, id_rol: int, id_donante: int | None, id_voluntario: int | None) -> None:
        codigo = {r["id_rol"]: r["codigo"] for r in self.repo.roles()}.get(id_rol)
        if codigo is None:
            raise BusinessRuleError("El rol indicado no existe.")
        if codigo == "DONANTE" and (id_donante is None or id_voluntario is not None):
            raise BusinessRuleError("Una cuenta de donante debe estar vinculada a un donante (y solo a uno).")
        if codigo == "VOLUNTARIO" and (id_voluntario is None or id_donante is not None):
            raise BusinessRuleError("Una cuenta de voluntario debe estar vinculada a un voluntario (y solo a uno).")
        if codigo not in {"DONANTE", "VOLUNTARIO"} and (id_donante is not None or id_voluntario is not None):
            raise BusinessRuleError("Solo las cuentas de donante o voluntario se vinculan a esas personas.")

    def crear(self, datos: UsuarioIn, actor: UsuarioActualOut) -> UsuarioOut:
        if not datos.password:
            raise BusinessRuleError("Indique una contraseña inicial.")
        self._validar_vinculos(datos.id_rol, datos.id_donante, datos.id_voluntario)
        nuevo = self.repo.guardar(id_usuario=None, username=datos.username, nombre_completo=datos.nombre_completo,
                                  correo=datos.correo, password_hash=hash_password(datos.password), id_rol=datos.id_rol,
                                  id_donante=datos.id_donante, id_voluntario=datos.id_voluntario,
                                  debe_cambiar_password=datos.debe_cambiar_password, id_actor=actor.id_usuario)
        return self.obtener(nuevo)

    def actualizar(self, id_usuario: int, datos: UsuarioEdicionIn, actor: UsuarioActualOut) -> UsuarioOut:
        actual = existente(self.repo.obtener(id_usuario), "El usuario")
        self._validar_vinculos(datos.id_rol, datos.id_donante, datos.id_voluntario)
        if id_usuario == actor.id_usuario and datos.id_rol != actual["id_rol"]:
            raise BusinessRuleError("No puede cambiar su propio rol.")
        self.repo.guardar(id_usuario=id_usuario, username=actual["username"], nombre_completo=datos.nombre_completo,
                          correo=datos.correo, password_hash=None, id_rol=datos.id_rol, id_donante=datos.id_donante,
                          id_voluntario=datos.id_voluntario, debe_cambiar_password=actual["debe_cambiar_password"],
                          id_actor=actor.id_usuario)
        return self.obtener(id_usuario)

    def restablecer_password(self, id_usuario: int, nueva: str, debe_cambiar: bool, actor: UsuarioActualOut) -> None:
        actual = existente(self.repo.obtener(id_usuario), "El usuario")
        try:
            validar_password(nueva, actual["username"])
        except ValueError as exc:
            raise BusinessRuleError(str(exc)) from exc
        self.repo.cambiar_password(id_usuario=id_usuario, password_hash=hash_password(nueva),
                                   debe_cambiar_password=debe_cambiar, id_actor=actor.id_usuario)

    def cambiar_estado(self, id_usuario: int, activo: bool, actor: UsuarioActualOut) -> UsuarioOut:
        if id_usuario == actor.id_usuario and not activo:
            raise BusinessRuleError("No puede desactivar su propia cuenta.")
        self.repo.cambiar_estado(id_usuario=id_usuario, activo=activo, id_actor=actor.id_usuario)
        return self.obtener(id_usuario)

    def roles(self) -> list[RolOut]:
        return [RolOut.model_validate(r) for r in self.repo.roles()]

    def matriz(self) -> MatrizOut:
        permisos, asignaciones = self.repo.matriz()
        mapa: dict[str, list[str]] = {}
        for a in asignaciones:
            mapa.setdefault(a["rol_codigo"], []).append(a["permiso_codigo"])
        return MatrizOut(roles=self.roles(), permisos=[PermisoOut.model_validate(p) for p in permisos], asignaciones=mapa)


class AuditoriaService:
    def __init__(self, repo: AuditoriaRepository) -> None:
        self.repo = repo

    def listar(self, filtro: FiltroAuditoria) -> Pagina[AuditoriaOut]:
        filas, total = self.repo.listar(**kwargs_filtro(filtro))
        return a_pagina(filas, total, filtro, AuditoriaOut)


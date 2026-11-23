"""Inicio de sesión, perfil y cambio de contraseña."""
from typing import Annotated

from fastapi import APIRouter, Depends, Response

from app.apis.deps import AuthSvc, Ip, usuario_sesion
from app.schemas.auth import CambiarPasswordIn, LoginIn, TokenOut, UsuarioActualOut

router = APIRouter(prefix="/auth", tags=["Autenticación"])
Sesion = Annotated[UsuarioActualOut, Depends(usuario_sesion)]


@router.post("/login", response_model=TokenOut, summary="Iniciar sesión")
def login(datos: LoginIn, svc: AuthSvc, ip: Ip) -> TokenOut:
    return svc.login(datos.username, datos.password, ip)


@router.get("/me", response_model=UsuarioActualOut, summary="Usuario de la sesión y sus permisos")
def me(usuario: Sesion) -> UsuarioActualOut:
    return usuario


@router.post("/cambiar-password", response_model=TokenOut, summary="Cambiar la contraseña propia")
def cambiar_password(datos: CambiarPasswordIn, usuario: Sesion, svc: AuthSvc) -> TokenOut:
    return svc.cambiar_password(usuario, datos.password_actual, datos.password_nueva)


@router.post("/logout", status_code=204, summary="Registrar el cierre de sesión")
def logout(usuario: Sesion, svc: AuthSvc, ip: Ip) -> Response:
    svc.cerrar_sesion(usuario, ip)
    return Response(status_code=204)

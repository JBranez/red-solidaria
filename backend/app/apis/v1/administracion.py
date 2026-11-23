"""Usuarios, roles, auditoría y catálogos."""
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from app.apis.deps import AuditoriaSvc, CatalogoSvc, UsuarioSvc, requiere
from app.core import permissions as P
from app.schemas.auth import (
    AuditoriaOut, FiltroAuditoria, FiltroUsuarios, MatrizOut, RestablecerPasswordIn, RolOut, UsuarioActualOut,
    UsuarioEdicionIn, UsuarioIn, UsuarioOut,
)
from app.schemas.catalogos import CategoriaIn, CategoriaOut, MetodoPagoOut, SectorIn, SectorOut
from app.schemas.common import CambioActivo, Pagina

Leer = Annotated[UsuarioActualOut, Depends(requiere(P.USUARIOS_LEER))]
Escribir = Annotated[UsuarioActualOut, Depends(requiere(P.USUARIOS_ESCRIBIR))]

usuarios = APIRouter(prefix="/usuarios", tags=["Usuarios"])
roles = APIRouter(prefix="/roles", tags=["Roles y permisos"])
auditoria = APIRouter(prefix="/auditoria", tags=["Auditoría"])
catalogos = APIRouter(tags=["Catálogos"])


# ---------------------------------------------------------------- usuarios
@usuarios.get("", response_model=Pagina[UsuarioOut])
def listar_usuarios(filtro: Annotated[FiltroUsuarios, Query()], svc: UsuarioSvc, _: Leer):
    return svc.listar(filtro)


@usuarios.post("", response_model=UsuarioOut, status_code=201)
def crear_usuario(datos: UsuarioIn, svc: UsuarioSvc, actor: Escribir):
    return svc.crear(datos, actor)


@usuarios.get("/{id_usuario}", response_model=UsuarioOut)
def obtener_usuario(id_usuario: int, svc: UsuarioSvc, _: Leer):
    return svc.obtener(id_usuario)


@usuarios.put("/{id_usuario}", response_model=UsuarioOut)
def actualizar_usuario(id_usuario: int, datos: UsuarioEdicionIn, svc: UsuarioSvc, actor: Escribir):
    return svc.actualizar(id_usuario, datos, actor)


@usuarios.post("/{id_usuario}/password", status_code=204, summary="Restablecer contraseña (cierra sus sesiones)")
def restablecer_password(id_usuario: int, datos: RestablecerPasswordIn, svc: UsuarioSvc, actor: Escribir):
    svc.restablecer_password(id_usuario, datos.password_nueva, datos.debe_cambiar_password, actor)
    return Response(status_code=204)


@usuarios.patch("/{id_usuario}/estado", response_model=UsuarioOut)
def estado_usuario(id_usuario: int, datos: CambioActivo, svc: UsuarioSvc, actor: Escribir):
    return svc.cambiar_estado(id_usuario, datos.activo, actor)


# ---------------------------------------------------------------- roles
@roles.get("", response_model=list[RolOut])
def listar_roles(svc: UsuarioSvc, _: Leer):
    return svc.roles()


@roles.get("/matriz", response_model=MatrizOut, summary="Matriz de permisos por rol")
def matriz(svc: UsuarioSvc, _: Leer):
    return svc.matriz()


# ---------------------------------------------------------------- auditoría
@auditoria.get("", response_model=Pagina[AuditoriaOut], summary="Bitácora de auditoría (solo lectura)")
def listar_auditoria(filtro: Annotated[FiltroAuditoria, Query()], svc: AuditoriaSvc,
                     _: Annotated[UsuarioActualOut, Depends(requiere(P.AUDITORIA_LEER))]):
    return svc.listar(filtro)


# ---------------------------------------------------------------- catálogos
CatLeer = Annotated[UsuarioActualOut, Depends(requiere(P.CATALOGOS_LEER))]
CatEscribir = Annotated[UsuarioActualOut, Depends(requiere(P.CATALOGOS_ESCRIBIR))]


@catalogos.get("/categorias", response_model=list[CategoriaOut])
def listar_categorias(svc: CatalogoSvc, _: CatLeer, solo_activas: bool = False):
    return svc.categorias(solo_activas)


@catalogos.post("/categorias", response_model=CategoriaOut, status_code=201)
def crear_categoria(datos: CategoriaIn, svc: CatalogoSvc, actor: CatEscribir):
    return svc.categoria_guardar(None, datos, actor)


@catalogos.put("/categorias/{id_categoria}", response_model=CategoriaOut)
def actualizar_categoria(id_categoria: int, datos: CategoriaIn, svc: CatalogoSvc, actor: CatEscribir):
    return svc.categoria_guardar(id_categoria, datos, actor)


@catalogos.patch("/categorias/{id_categoria}/estado", response_model=CategoriaOut)
def estado_categoria(id_categoria: int, datos: CambioActivo, svc: CatalogoSvc, actor: CatEscribir):
    return svc.categoria_estado(id_categoria, datos.activo, actor)


@catalogos.get("/sectores", response_model=list[SectorOut])
def listar_sectores(svc: CatalogoSvc, _: CatLeer, solo_activos: bool = False):
    return svc.sectores(solo_activos)


@catalogos.post("/sectores", response_model=SectorOut, status_code=201)
def crear_sector(datos: SectorIn, svc: CatalogoSvc, actor: CatEscribir):
    return svc.sector_guardar(None, datos, actor)


@catalogos.put("/sectores/{id_sector}", response_model=SectorOut)
def actualizar_sector(id_sector: int, datos: SectorIn, svc: CatalogoSvc, actor: CatEscribir):
    return svc.sector_guardar(id_sector, datos, actor)


@catalogos.patch("/sectores/{id_sector}/estado", response_model=SectorOut)
def estado_sector(id_sector: int, datos: CambioActivo, svc: CatalogoSvc, actor: CatEscribir):
    return svc.sector_estado(id_sector, datos.activo, actor)


@catalogos.get("/metodos-pago", response_model=list[MetodoPagoOut])
def listar_metodos_pago(svc: CatalogoSvc, _: CatLeer, solo_activos: bool = True):
    return svc.metodos_pago(solo_activos)

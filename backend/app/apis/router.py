"""Agrupa todos los routers bajo /api/v1."""
from fastapi import APIRouter

from app.apis.v1 import administracion, auth, finanzas, operacion, reportes

api_router = APIRouter()
for r in (
    auth.router, administracion.usuarios, administracion.roles, administracion.auditoria, administracion.catalogos,
    finanzas.campanas, finanzas.donantes, finanzas.donaciones, finanzas.gastos,
    operacion.beneficiarios, operacion.necesidades, operacion.voluntarios, operacion.entregas, operacion.feedback,
    reportes.dashboard, reportes.mi, reportes.publico,
):
    api_router.include_router(r)

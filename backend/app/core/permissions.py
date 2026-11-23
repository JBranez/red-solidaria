"""Permisos del sistema (RBAC). FUENTE DE VERDAD en código; coincide con database/10_reference_data.sql.

Una prueba automática (tests/test_contrato_sql.py) falla si ambos divergen.
"""

CAMPANAS_LEER = "campanas:leer"
CAMPANAS_ESCRIBIR = "campanas:escribir"
CAMPANAS_ESTADO = "campanas:estado"
CATALOGOS_LEER = "catalogos:leer"
CATALOGOS_ESCRIBIR = "catalogos:escribir"
DONANTES_LEER = "donantes:leer"
DONANTES_ESCRIBIR = "donantes:escribir"
DONACIONES_LEER = "donaciones:leer"
DONACIONES_REGISTRAR = "donaciones:registrar"
DONACIONES_VERIFICAR = "donaciones:verificar"
DONACIONES_EXPORTAR = "donaciones:exportar"
GASTOS_LEER = "gastos:leer"
GASTOS_REGISTRAR = "gastos:registrar"
GASTOS_APROBAR = "gastos:aprobar"
BENEFICIARIOS_LEER = "beneficiarios:leer"
BENEFICIARIOS_ESCRIBIR = "beneficiarios:escribir"
NECESIDADES_LEER = "necesidades:leer"
NECESIDADES_ESCRIBIR = "necesidades:escribir"
VOLUNTARIOS_LEER = "voluntarios:leer"
VOLUNTARIOS_ESCRIBIR = "voluntarios:escribir"
ENTREGAS_LEER = "entregas:leer"
ENTREGAS_REGISTRAR = "entregas:registrar"
ENTREGAS_GESTIONAR = "entregas:gestionar"
ENTREGAS_PROPIAS = "entregas:propias"
FEEDBACK_LEER = "feedback:leer"
FEEDBACK_REGISTRAR = "feedback:registrar"
FEEDBACK_GESTIONAR = "feedback:gestionar"
FEEDBACK_CONFIDENCIAL = "feedback:confidencial"
DASHBOARD_LEER = "dashboard:leer"
REPORTES_LEER = "reportes:leer"
REPORTES_EXPORTAR = "reportes:exportar"
USUARIOS_LEER = "usuarios:leer"
USUARIOS_ESCRIBIR = "usuarios:escribir"
AUDITORIA_LEER = "auditoria:leer"
PORTAL_DONANTE = "portal:donante"
PORTAL_VOLUNTARIO = "portal:voluntario"

TODOS = (
    "campanas:leer",
    "campanas:escribir",
    "campanas:estado",
    "catalogos:leer",
    "catalogos:escribir",
    "donantes:leer",
    "donantes:escribir",
    "donaciones:leer",
    "donaciones:registrar",
    "donaciones:verificar",
    "donaciones:exportar",
    "gastos:leer",
    "gastos:registrar",
    "gastos:aprobar",
    "beneficiarios:leer",
    "beneficiarios:escribir",
    "necesidades:leer",
    "necesidades:escribir",
    "voluntarios:leer",
    "voluntarios:escribir",
    "entregas:leer",
    "entregas:registrar",
    "entregas:gestionar",
    "entregas:propias",
    "feedback:leer",
    "feedback:registrar",
    "feedback:gestionar",
    "feedback:confidencial",
    "dashboard:leer",
    "reportes:leer",
    "reportes:exportar",
    "usuarios:leer",
    "usuarios:escribir",
    "auditoria:leer",
    "portal:donante",
    "portal:voluntario",
)

# Rol (código) -> permisos asignados. ADMIN recibe todos.
ROL_PERMISOS: dict[str, tuple[str, ...]] = {
    "COORDINADOR": (
        "campanas:leer",
        "campanas:escribir",
        "campanas:estado",
        "catalogos:leer",
        "catalogos:escribir",
        "donantes:leer",
        "donaciones:leer",
        "gastos:leer",
        "gastos:aprobar",
        "beneficiarios:leer",
        "necesidades:leer",
        "necesidades:escribir",
        "voluntarios:leer",
        "voluntarios:escribir",
        "entregas:leer",
        "entregas:registrar",
        "entregas:gestionar",
        "feedback:leer",
        "feedback:registrar",
        "feedback:gestionar",
        "dashboard:leer",
        "reportes:leer",
    ),
    "FINANZAS": (
        "campanas:leer",
        "catalogos:leer",
        "donantes:leer",
        "donantes:escribir",
        "donaciones:leer",
        "donaciones:registrar",
        "donaciones:verificar",
        "donaciones:exportar",
        "gastos:leer",
        "gastos:registrar",
        "dashboard:leer",
        "reportes:leer",
        "reportes:exportar",
    ),
    "TRABAJO_SOCIAL": (
        "campanas:leer",
        "catalogos:leer",
        "beneficiarios:leer",
        "beneficiarios:escribir",
        "necesidades:leer",
        "necesidades:escribir",
        "voluntarios:leer",
        "entregas:leer",
        "entregas:registrar",
        "feedback:leer",
        "feedback:registrar",
        "feedback:gestionar",
        "feedback:confidencial",
        "dashboard:leer",
    ),
    "VOLUNTARIO": (
        "campanas:leer",
        "catalogos:leer",
        "entregas:propias",
        "feedback:registrar",
        "portal:voluntario",
    ),
    "AUDITOR": (
        "campanas:leer",
        "catalogos:leer",
        "donantes:leer",
        "donaciones:leer",
        "gastos:leer",
        "beneficiarios:leer",
        "necesidades:leer",
        "voluntarios:leer",
        "entregas:leer",
        "feedback:leer",
        "dashboard:leer",
        "reportes:leer",
        "usuarios:leer",
        "auditoria:leer",
    ),
    "DONANTE": (
        "portal:donante",
    ),
    "ADMIN": TODOS,
}

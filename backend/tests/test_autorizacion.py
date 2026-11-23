"""Matriz de autorización por rol: lo que el menú del frontend oculta, la API lo hace cumplir."""
import pytest

# (rol, método, ruta, cuerpo)  →  esperado 403
DENEGADOS = [
    ("VOLUNTARIO", "GET", "/api/v1/donaciones", None),
    ("VOLUNTARIO", "GET", "/api/v1/beneficiarios", None),
    ("VOLUNTARIO", "POST", "/api/v1/entregas", {}),
    ("VOLUNTARIO", "POST", "/api/v1/campanas", {}),
    ("VOLUNTARIO", "GET", "/api/v1/usuarios", None),
    ("VOLUNTARIO", "GET", "/api/v1/auditoria", None),
    ("VOLUNTARIO", "GET", "/api/v1/dashboard/kpis", None),
    ("VOLUNTARIO", "GET", "/api/v1/mi/donaciones", None),
    ("DONANTE", "GET", "/api/v1/campanas", None),
    ("DONANTE", "GET", "/api/v1/donaciones", None),
    ("DONANTE", "GET", "/api/v1/mi/entregas", None),
    ("DONANTE", "GET", "/api/v1/donantes", None),
    ("AUDITOR", "POST", "/api/v1/donaciones", {}),
    ("AUDITOR", "POST", "/api/v1/campanas", {}),
    ("AUDITOR", "GET", "/api/v1/donaciones/export", None),
    ("AUDITOR", "GET", "/api/v1/entregas/export", None),
    ("AUDITOR", "POST", "/api/v1/usuarios", {}),
    ("FINANZAS", "GET", "/api/v1/beneficiarios", None),           # datos personales de hogares
    ("FINANZAS", "POST", "/api/v1/gastos/1/estado", {}),          # separación de funciones: registra, no aprueba
    ("FINANZAS", "POST", "/api/v1/campanas", {}),
    ("FINANZAS", "GET", "/api/v1/auditoria", None),
    ("COORDINADOR", "POST", "/api/v1/donaciones", {}),
    ("COORDINADOR", "POST", "/api/v1/donaciones/1/estado", {}),
    ("COORDINADOR", "GET", "/api/v1/auditoria", None),
    ("COORDINADOR", "POST", "/api/v1/usuarios", {}),
    ("TRABAJO_SOCIAL", "GET", "/api/v1/donantes", None),
    ("TRABAJO_SOCIAL", "GET", "/api/v1/donaciones", None),
    ("TRABAJO_SOCIAL", "POST", "/api/v1/campanas/1/estado", {}),
    ("TRABAJO_SOCIAL", "GET", "/api/v1/reportes/top-donantes", None),
]

PERMITIDOS = [
    ("ADMIN", "GET", "/api/v1/usuarios"), ("ADMIN", "GET", "/api/v1/auditoria"), ("ADMIN", "GET", "/api/v1/roles/matriz"),
    ("ADMIN", "GET", "/api/v1/donaciones/export"),
    ("VOLUNTARIO", "GET", "/api/v1/entregas"), ("VOLUNTARIO", "GET", "/api/v1/mi/entregas"),
    ("VOLUNTARIO", "GET", "/api/v1/campanas"),
    ("DONANTE", "GET", "/api/v1/mi/donaciones"),
    ("AUDITOR", "GET", "/api/v1/auditoria"), ("AUDITOR", "GET", "/api/v1/donaciones"), ("AUDITOR", "GET", "/api/v1/feedback"),
    ("FINANZAS", "GET", "/api/v1/donaciones"), ("FINANZAS", "GET", "/api/v1/donaciones/export"),
    ("COORDINADOR", "GET", "/api/v1/beneficiarios"), ("COORDINADOR", "GET", "/api/v1/gastos"),
    ("TRABAJO_SOCIAL", "GET", "/api/v1/beneficiarios"), ("TRABAJO_SOCIAL", "GET", "/api/v1/necesidades"),
]


@pytest.mark.parametrize("rol,metodo,ruta,cuerpo", DENEGADOS, ids=[f"{r}:{m}:{p}" for r, m, p, _ in DENEGADOS])
def test_rol_sin_permiso_recibe_403(client, autenticar, rol, metodo, ruta, cuerpo):
    h = autenticar(rol, id_voluntario=4 if rol == "VOLUNTARIO" else None, id_donante=9 if rol == "DONANTE" else None)
    r = client.request(metodo, ruta, headers=h, json=cuerpo) if cuerpo is not None else client.request(metodo, ruta, headers=h)
    assert r.status_code == 403, (r.status_code, r.text)
    assert r.json()["error"]["codigo"] == "PERMISO_INSUFICIENTE"


@pytest.mark.parametrize("rol,metodo,ruta", PERMITIDOS, ids=[f"{r}:{m}:{p}" for r, m, p in PERMITIDOS])
def test_rol_con_permiso_no_es_bloqueado(client, autenticar, rol, metodo, ruta):
    h = autenticar(rol, id_voluntario=4 if rol == "VOLUNTARIO" else None, id_donante=9 if rol == "DONANTE" else None)
    assert client.request(metodo, ruta, headers=h).status_code not in (401, 403)


def test_la_denegacion_ocurre_antes_de_tocar_la_base_de_datos(client, fake, autenticar):
    client.post("/api/v1/donaciones", headers=autenticar("AUDITOR"), json={})
    assert not [c for c in fake.calls if c[0].startswith("usp_donacion")]


def test_validacion_ocurre_despues_de_autorizar(client, autenticar):
    """Un rol sin permiso recibe 403 aunque el cuerpo sea inválido (no se filtra nada sobre el esquema)."""
    assert client.post("/api/v1/campanas", headers=autenticar("VOLUNTARIO", id_voluntario=4), json={"x": 1}).status_code == 403
    assert client.post("/api/v1/campanas", headers=autenticar("ADMIN"), json={"x": 1}).status_code == 422

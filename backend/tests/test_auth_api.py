"""Flujo de autenticación de punta a punta (API + servicios + repositorios, BD simulada)."""
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.core.security import create_access_token, hash_password
from tests.conftest import fila_usuario

CLAVE = "ClaveSegura2026"
MSG_GENERICO = "Usuario o contraseña incorrectos."


@pytest.fixture(scope="module")
def hash_clave():
    return hash_password(CLAVE)


def _credenciales(hash_clave, **extra):
    return {"id_usuario": 7, "username": "ana", "password_hash": hash_clave, "activo": True,
            "intentos_fallidos": 0, "bloqueado_hasta": None, "bloqueado": False, **extra}


def _login(client, usuario="ana", clave=CLAVE):
    return client.post("/api/v1/auth/login", json={"username": usuario, "password": clave})


def test_login_correcto_devuelve_token_usuario_y_permisos(client, fake, hash_clave):
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave)])
    fake.stub("usp_auth_obtener_usuario", [[fila_usuario("FINANZAS")], [{"codigo": "donaciones:leer"}]])
    r = _login(client, "ANA")  # el usuario se normaliza a minúsculas
    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["token_type"] == "bearer" and cuerpo["expires_in"] == 3600
    assert cuerpo["usuario"]["permisos"] == ["donaciones:leer"]
    assert "password_hash" not in r.text and "argon2" not in r.text and CLAVE not in r.text
    assert fake.llamadas("usp_auth_obtener_credenciales")[0]["username"] == "ana"
    assert fake.llamadas("usp_auth_registrar_intento")[0]["exitoso"] is True


def test_contrasena_incorrecta_registra_intento_fallido(client, fake, hash_clave):
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave)])
    r = _login(client, clave="otraClave123")
    assert r.status_code == 401 and r.json()["error"]["mensaje"] == MSG_GENERICO
    assert fake.llamadas("usp_auth_registrar_intento")[0]["exitoso"] is False


def test_usuario_inexistente_da_el_mismo_mensaje_y_queda_auditado(client, fake):
    fake.stub("usp_auth_obtener_credenciales", [])
    r = _login(client, "nadie")
    assert r.status_code == 401 and r.json()["error"]["mensaje"] == MSG_GENERICO
    evento = fake.llamadas("usp_auditoria_registrar")[0]
    assert evento["accion"] == "LOGIN_FALLIDO" and evento["id_usuario"] is None


def test_cuenta_desactivada_no_revela_que_existe(client, fake, hash_clave):
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave, activo=False)])
    r = _login(client)
    assert r.status_code == 401 and r.json()["error"]["mensaje"] == MSG_GENERICO
    assert not fake.llamadas("usp_auth_registrar_intento")  # no cuenta como intento de una cuenta activa


def test_cuenta_bloqueada_responde_423_sin_contar_el_intento(client, fake, hash_clave):
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave, bloqueado=True)])
    r = _login(client)
    assert r.status_code == 423 and r.json()["error"]["codigo"] == "CUENTA_BLOQUEADA"
    assert not fake.llamadas("usp_auth_registrar_intento")


def test_login_valida_el_cuerpo(client):
    assert client.post("/api/v1/auth/login", json={"username": "", "password": "x"}).status_code == 422
    assert client.post("/api/v1/auth/login", json={"username": "a", "password": "x", "extra": 1}).status_code == 422


# ---------------------------------------------------------------- sesión
def test_sin_token_es_401(client):
    r = client.get("/api/v1/campanas")
    assert r.status_code == 401 and r.json()["error"]["codigo"] == "NO_AUTENTICADO"


def test_me_devuelve_permisos_de_la_bd(client, autenticar):
    r = client.get("/api/v1/auth/me", headers=autenticar("VOLUNTARIO", id_voluntario=4))
    assert r.status_code == 200
    assert r.json()["rol_codigo"] == "VOLUNTARIO" and "entregas:propias" in r.json()["permisos"]
    assert "usuarios:escribir" not in r.json()["permisos"]


def test_token_manipulado_es_rechazado(client, autenticar):
    h = autenticar()
    token = h["Authorization"].split()[1]
    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer " + token[:-3] + "abc"}).status_code == 401


def test_token_de_otra_clave_es_rechazado(client):
    falso = jwt.encode({"sub": "7", "tv": 0, "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, "x" * 48, algorithm="HS256")
    assert client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {falso}"}).status_code == 401


def test_token_expirado_indica_el_codigo(client, settings):
    vencido = jwt.encode({"sub": "7", "tv": 0, "exp": datetime.now(timezone.utc) - timedelta(minutes=1)},
                         settings.jwt_secret_key.get_secret_value(), algorithm="HS256")
    r = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {vencido}"})
    assert r.status_code == 401 and r.json()["error"]["codigo"] == "SESION_EXPIRADA"


def test_cambio_de_version_revoca_la_sesion(client, fake, autenticar, settings):
    h = autenticar("ADMIN", token_version=0)
    fake.stub("usp_auth_obtener_usuario", [[fila_usuario("ADMIN", token_version=1)], []])  # se cambió la contraseña
    r = client.get("/api/v1/auth/me", headers=h)
    assert r.status_code == 401 and r.json()["error"]["codigo"] == "SESION_REVOCADA"


def test_usuario_desactivado_pierde_la_sesion_al_instante(client, fake, autenticar):
    h = autenticar("ADMIN")
    fake.stub("usp_auth_obtener_usuario", [[fila_usuario("ADMIN", activo=False)], []])
    assert client.get("/api/v1/auth/me", headers=h).status_code == 401


def test_contrasena_temporal_bloquea_todo_salvo_cambiarla(client, autenticar):
    h = autenticar("ADMIN", debe_cambiar_password=True)
    r = client.get("/api/v1/campanas", headers=h)
    assert r.status_code == 403 and r.json()["error"]["codigo"] == "CAMBIO_PASSWORD_REQUERIDO"
    assert client.get("/api/v1/auth/me", headers=h).status_code == 200


def test_cambiar_password_emite_token_con_la_nueva_version(client, fake, autenticar, hash_clave, settings):
    h = autenticar("ADMIN", debe_cambiar_password=True)
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave, username="admin.prueba")])
    fake.stub("usp_usuario_password", [{"token_version": 5}])
    r = client.post("/api/v1/auth/cambiar-password", headers=h,
                    json={"password_actual": CLAVE, "password_nueva": "NuevaClave2026"})
    assert r.status_code == 200, r.text
    assert r.json()["usuario"]["debe_cambiar_password"] is False
    from app.core.security import decode_access_token
    assert decode_access_token(r.json()["access_token"], settings)["tv"] == 5
    llamada = fake.llamadas("usp_usuario_password")[0]
    assert llamada["password_hash"].startswith("$argon2id$") and "NuevaClave2026" not in str(llamada)


def test_cambiar_password_con_actual_incorrecta(client, fake, autenticar, hash_clave):
    h = autenticar("ADMIN")
    fake.stub("usp_auth_obtener_credenciales", [_credenciales(hash_clave)])
    r = client.post("/api/v1/auth/cambiar-password", headers=h, json={"password_actual": "equivocada1", "password_nueva": "NuevaClave2026"})
    assert r.status_code == 422 and r.json()["error"]["codigo"] == "PASSWORD_ACTUAL_INCORRECTA"


def test_cambiar_password_debil_indica_el_campo(client, autenticar):
    r = client.post("/api/v1/auth/cambiar-password", headers=autenticar(), json={"password_actual": "x", "password_nueva": "corta"})
    assert r.status_code == 422 and r.json()["error"]["detalles"][0]["campo"] == "password_nueva"


def test_logout_queda_en_la_bitacora(client, fake, autenticar):
    assert client.post("/api/v1/auth/logout", headers=autenticar()).status_code == 204
    assert fake.llamadas("usp_auditoria_registrar")[0]["accion"] == "LOGOUT"


def test_error_de_bd_no_filtra_detalles(client, fake, autenticar):
    from app.core.errors import DatabaseUnavailableError
    fake.stub("usp_campana_listar", DatabaseUnavailableError("La base de datos no está disponible en este momento."))
    r = client.get("/api/v1/campanas", headers=autenticar())
    assert r.status_code == 503 and "Server" not in r.text


def test_error_inesperado_responde_500_generico(client, fake, autenticar):
    fake.stub("usp_campana_listar", RuntimeError("password=secreto conexión interna"))
    r = client.get("/api/v1/campanas", headers=autenticar())
    assert r.status_code == 500 and "secreto" not in r.text


def test_cabeceras_de_seguridad_y_no_cache_en_la_api(client, autenticar):
    r = client.get("/api/v1/auth/me", headers=autenticar())
    assert r.headers["x-content-type-options"] == "nosniff" and r.headers["cache-control"] == "no-store"


def test_cors_solo_permite_el_origen_configurado(client):
    ok = client.options("/api/v1/campanas", headers={"Origin": "http://localhost:4200", "Access-Control-Request-Method": "GET"})
    mal = client.options("/api/v1/campanas", headers={"Origin": "http://malo.example", "Access-Control-Request-Method": "GET"})
    assert ok.headers.get("access-control-allow-origin") == "http://localhost:4200"
    assert "access-control-allow-origin" not in mal.headers


def test_la_documentacion_se_desactiva_en_produccion():
    from app.core.config import Settings
    from app.main import create_app
    prod = create_app(Settings(_env_file=None, jwt_secret_key="s" * 40, db_app_password="p", app_env="production", db_trust_server_certificate="no"))
    from fastapi.testclient import TestClient
    assert TestClient(prod).get("/docs").status_code == 404
    assert TestClient(prod).get("/openapi.json").status_code == 404


def test_rutas_publicas_no_requieren_token(client, fake):
    fake.stub("usp_publico_campanas", [])
    assert client.get("/api/v1/public/campanas").status_code == 200
    assert client.get("/health").json() == {"estado": "ok"}
    assert client.get("/api/v1/public/campanas").headers["cache-control"] == "public, max-age=60"

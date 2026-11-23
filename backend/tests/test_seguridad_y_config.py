"""Hash de contraseñas, JWT, configuración, cadena de conexión y utilidades."""
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from pydantic import ValidationError

from app.core.config import Settings
from app.core.errors import UnauthorizedError
from app.core.security import create_access_token, decode_access_token, hash_password, verify_password
from app.core.utils import like_pattern, to_csv
from app.db.connection import build_connection_string
from app.schemas.auth import CambiarPasswordIn, UsuarioIn, validar_password


# ---------------------------------------------------------------- contraseñas
def test_hash_es_argon2_y_distinto_cada_vez():
    a, b = hash_password("Clave12345!"), hash_password("Clave12345!")
    assert a.startswith("$argon2id$") and a != b
    assert verify_password("Clave12345!", a) and not verify_password("otra", a)


def test_hash_corrupto_no_lanza_excepcion():
    assert verify_password("x", "no-es-un-hash") is False


@pytest.mark.parametrize("pw", ["corta1", "sololetrasmuylarga", "1234567890123"])
def test_politica_rechaza_contrasenas_debiles(pw):
    with pytest.raises(ValueError):
        validar_password(pw)


def test_politica_rechaza_igual_al_usuario():
    with pytest.raises(ValueError):
        validar_password("usuario1234", "usuario1234")


def test_cambio_de_password_exige_que_sea_distinta():
    with pytest.raises(ValidationError):
        CambiarPasswordIn(password_actual="Clave12345", password_nueva="Clave12345")


def test_usuario_username_se_normaliza_y_valida():
    assert UsuarioIn(username="Ana.Lopez", nombre_completo="Ana López", correo="ANA@x.pe", id_rol=1).username == "ana.lopez"
    with pytest.raises(ValidationError):
        UsuarioIn(username="a b", nombre_completo="Ana López", correo="ana@x.pe", id_rol=1)


# ---------------------------------------------------------------- JWT
def test_jwt_ida_y_vuelta(settings):
    token, seg = create_access_token(user_id=5, token_version=3, settings=settings)
    datos = decode_access_token(token, settings)
    assert datos["sub"] == "5" and datos["tv"] == 3 and seg == settings.access_token_expire_minutes * 60


def test_jwt_expirado(settings):
    clave = settings.jwt_secret_key.get_secret_value()
    token = jwt.encode({"sub": "1", "tv": 0, "exp": datetime.now(timezone.utc) - timedelta(seconds=5)}, clave, algorithm="HS256")
    with pytest.raises(UnauthorizedError) as e:
        decode_access_token(token, settings)
    assert e.value.codigo == "SESION_EXPIRADA"


def test_jwt_firmado_con_otra_clave(settings):
    token = jwt.encode({"sub": "1", "tv": 0, "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, "o" * 40, algorithm="HS256")
    with pytest.raises(UnauthorizedError):
        decode_access_token(token, settings)


def test_jwt_alg_none_es_rechazado(settings):
    token = jwt.encode({"sub": "1", "tv": 0, "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, None, algorithm="none")
    with pytest.raises(UnauthorizedError):
        decode_access_token(token, settings)


def test_jwt_sin_claims_obligatorios(settings):
    token = jwt.encode({"sub": "1", "exp": datetime.now(timezone.utc) + timedelta(hours=1)}, settings.jwt_secret_key.get_secret_value(), algorithm="HS256")
    with pytest.raises(UnauthorizedError):
        decode_access_token(token, settings)


# ---------------------------------------------------------------- configuración
def _cfg(**kw):
    base = dict(_env_file=None, jwt_secret_key="s" * 40, db_app_password="p")
    return Settings(**{**base, **kw})


def test_clave_jwt_corta_se_rechaza():
    with pytest.raises(ValidationError):
        _cfg(jwt_secret_key="corta")


def test_cors_comodin_se_rechaza():
    with pytest.raises(ValidationError):
        _cfg(cors_origins="*")


def test_produccion_no_acepta_certificado_no_verificado():
    with pytest.raises(ValidationError):
        _cfg(app_env="production", db_trust_server_certificate="yes")
    assert _cfg(app_env="production", db_trust_server_certificate="no").is_production


def test_cors_lista_de_origenes():
    assert _cfg(cors_origins="http://a.test, http://b.test").cors_origins_list == ["http://a.test", "http://b.test"]


def test_cadena_de_conexion_escapa_llaves_en_la_contrasena():
    cs = build_connection_string(_cfg(db_app_password="a}b;c=d"))
    assert "PWD={a}}b;c=d}" in cs and "Encrypt=yes" in cs and "UID={redsolidaria_app}" in cs


def test_el_secreto_no_aparece_en_el_repr():
    assert "s" * 40 not in repr(_cfg())


# ---------------------------------------------------------------- utilidades
@pytest.mark.parametrize("entrada,esperado", [
    (None, None), ("", None), ("   ", None), ("Ana", "%Ana%"), ("50%", "%50\\%%"), ("a_b", "%a\\_b%"),
    ("[x]", "%\\[x]%"), ("a\\b", "%a\\\\b%"),
])
def test_like_pattern_escapa_comodines(entrada, esperado):
    assert like_pattern(entrada) == esperado


def test_csv_con_bom_encabezados_y_formatos():
    from datetime import date
    from decimal import Decimal
    csv = to_csv([{"a": date(2026, 1, 2), "b": Decimal("10.50"), "c": None, "d": True}],
                 [("a", "Fecha"), ("b", "Monto"), ("c", "Nada"), ("d", "Sí")])
    assert csv.startswith("\ufeff") and "Fecha,Monto,Nada,Sí" in csv and "2026-01-02,10.50,,Sí" in csv


@pytest.mark.parametrize("peligroso", ["=1+1", "+cmd|' /C calc'!A0", "-2+3", "@SUM(A1)"])
def test_csv_neutraliza_inyeccion_de_formulas(peligroso):
    assert "'" + peligroso in to_csv([{"x": peligroso}], [("x", "X")])

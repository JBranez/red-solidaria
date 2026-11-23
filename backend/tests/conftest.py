"""Fixtures: aplicación con base de datos simulada (FakeExecutor). Ninguna prueba necesita SQL Server."""
from __future__ import annotations

import os

# Debe fijarse ANTES de importar app.main (que crea la aplicación al importarse)
os.environ.setdefault("JWT_SECRET_KEY", "clave-de-pruebas-" + "x" * 40)
os.environ.setdefault("DB_APP_PASSWORD", "pwd-de-pruebas")
os.environ["APP_ENV"] = "test"

from typing import Any, Callable  # noqa: E402

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.apis.deps import get_db  # noqa: E402
from app.core import permissions as P  # noqa: E402
from app.core.config import Settings, get_settings  # noqa: E402
from app.core.security import create_access_token  # noqa: E402
from app.main import create_app  # noqa: E402


class FakeExecutor:
    """Sustituye a Executor: registra las llamadas y devuelve lo que cada prueba programe."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self._respuestas: dict[str, Any] = {}

    def stub(self, proc: str, respuesta: Any) -> None:
        """`respuesta` puede ser un valor, una excepción (se lanza) o una función(params) -> valor."""
        self._respuestas[proc] = respuesta

    def _resolver(self, proc: str, params: dict[str, Any], defecto: Any) -> Any:
        self.calls.append((proc, params))
        r = self._respuestas.get(proc, defecto)
        if isinstance(r, BaseException):
            raise r
        return r(params) if callable(r) else r

    def fetch_all(self, proc, /, **params):
        return self._resolver(proc, params, [])

    def fetch_one(self, proc, /, **params):
        r = self._resolver(proc, params, [])
        return (r[0] if r else None) if isinstance(r, list) else r

    def fetch_sets(self, proc, /, **params):
        return self._resolver(proc, params, [])

    def execute(self, proc, /, **params):
        self._resolver(proc, params, None)

    def page(self, proc, /, *, pagina, tamano, **params):
        r = self._resolver(proc, {**params, "pagina": pagina, "tamano": tamano}, ([], 0))
        return r

    # utilidades de aserción
    def llamadas(self, proc: str) -> list[dict[str, Any]]:
        return [p for n, p in self.calls if n == proc]


def fila_usuario(rol: str = "ADMIN", **extra: Any) -> dict[str, Any]:
    ids = {r: i for i, r in enumerate(P.ROL_PERMISOS, start=1)}
    base = {
        "id_usuario": 7, "username": f"{rol.lower()}.prueba", "nombre_completo": f"Usuario {rol.title()}",
        "correo": f"{rol.lower()}@redsolidaria.test", "id_rol": ids[rol], "rol_codigo": rol, "rol_nombre": rol.title(),
        "id_donante": None, "id_voluntario": None, "activo": True, "debe_cambiar_password": False, "token_version": 0,
    }
    return {**base, **extra}


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, jwt_secret_key="s" * 48, db_app_password="pwd", app_env="test")


@pytest.fixture
def fake() -> FakeExecutor:
    return FakeExecutor()


@pytest.fixture
def client(fake: FakeExecutor, settings: Settings):
    app = create_app(settings)
    app.dependency_overrides[get_db] = lambda: fake
    app.dependency_overrides[get_settings] = lambda: settings
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


@pytest.fixture
def autenticar(fake: FakeExecutor, settings: Settings) -> Callable[..., dict[str, str]]:
    """Programa la BD para que el token pertenezca a un usuario del rol indicado; devuelve la cabecera Authorization."""

    def _autenticar(rol: str = "ADMIN", **extra: Any) -> dict[str, str]:
        fila = fila_usuario(rol, **extra)
        fake.stub("usp_auth_obtener_usuario", [[fila], [{"codigo": c} for c in P.ROL_PERMISOS[rol]]])
        token, _ = create_access_token(user_id=fila["id_usuario"], token_version=fila["token_version"], settings=settings)
        return {"Authorization": f"Bearer {token}"}

    return _autenticar

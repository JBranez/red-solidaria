"""Hash de contraseñas (Argon2id) y tokens JWT firmados."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any

import jwt
from pwdlib import PasswordHash
from pwdlib.hashers.argon2 import Argon2Hasher

from app.core.config import Settings
from app.core.errors import UnauthorizedError

_hasher = PasswordHash((Argon2Hasher(),))


def hash_password(plain: str) -> str:
    return _hasher.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return _hasher.verify(plain, hashed)
    except Exception:  # hash corrupto o de otro formato: se trata como no válido
        return False


@lru_cache
def _dummy_hash() -> str:
    return _hasher.hash("contraseña-ficticia-para-igualar-tiempos")


def burn_password_check(plain: str) -> None:
    """Gasta el mismo tiempo que una verificación real (evita enumerar usuarios por latencia)."""
    verify_password(plain, _dummy_hash())


def create_access_token(*, user_id: int, token_version: int, settings: Settings) -> tuple[str, int]:
    """Devuelve (token, segundos de vigencia). `tv` permite revocar sesiones desde la BD."""
    ahora = datetime.now(timezone.utc)
    vigencia = timedelta(minutes=settings.access_token_expire_minutes)
    payload: dict[str, Any] = {"sub": str(user_id), "tv": token_version, "iat": ahora, "exp": ahora + vigencia}
    token = jwt.encode(payload, settings.jwt_secret_key.get_secret_value(), algorithm=settings.jwt_algorithm)
    return token, int(vigencia.total_seconds())


def decode_access_token(token: str, settings: Settings) -> dict[str, Any]:
    try:
        return jwt.decode(
            token,
            settings.jwt_secret_key.get_secret_value(),
            algorithms=[settings.jwt_algorithm],  # lista cerrada: impide el ataque "alg=none"
            options={"require": ["exp", "sub", "tv"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise UnauthorizedError("La sesión expiró. Inicie sesión nuevamente.", codigo="SESION_EXPIRADA") from exc
    except jwt.PyJWTError as exc:
        raise UnauthorizedError("Token de autenticación no válido.") from exc

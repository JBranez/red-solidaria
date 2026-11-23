"""Comprueba que la API podrá conectarse: abre la conexión con la CUENTA DE APLICACIÓN y ejecuta un procedimiento."""
from __future__ import annotations

from app.core.config import get_settings
from app.db.connection import open_connection
from app.db.executor import Executor


def main() -> int:
    cfg = get_settings()
    ex = Executor(open_connection(cfg))
    metodos = ex.fetch_all("usp_metodo_pago_listar", solo_activos=True)
    roles = ex.fetch_all("usp_rol_listar")
    print(f"✓ Conexión como '{cfg.db_app_user}' a {cfg.db_server}:{cfg.db_port}/{cfg.db_name}: {len(metodos)} métodos de pago, {len(roles)} roles.")
    try:  # la cuenta de aplicación NO debe poder leer tablas directamente
        ex._cn.cursor().execute("SELECT TOP 1 * FROM dbo.donante")
        print("✗ ADVERTENCIA: la cuenta de aplicación puede leer tablas directamente. Revise 09_permissions.sql.")
        return 1
    except Exception:  # noqa: BLE001
        print("✓ La cuenta de aplicación no tiene acceso directo a las tablas (mínimo privilegio).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

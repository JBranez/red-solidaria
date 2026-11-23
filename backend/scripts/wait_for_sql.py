"""Espera la disponibilidad de SQL Server antes de aplicar el esquema."""
from __future__ import annotations

import time

import pyodbc

from scripts._comunes import cargar_env, cadena_admin


def main() -> int:
    cfg = cargar_env()
    servidor = f"{cfg.get('DB_SERVER', 'sqlserver')}:{cfg.get('DB_PORT', '1433')}"
    intentos = int(cfg.get('DB_WAIT_ATTEMPTS', '60'))
    pausa = float(cfg.get('DB_WAIT_SECONDS', '5'))
    cadena = cadena_admin(cfg, base='master')

    for intento in range(1, intentos + 1):
        try:
            cn = pyodbc.connect(cadena, timeout=4, autocommit=True)
            cn.cursor().execute('SELECT 1').fetchone()
            cn.close()
            print(f"SQL Server disponible en {servidor} (intento {intento}/{intentos}).", flush=True)
            return 0
        except (pyodbc.Error, OSError) as exc:
            print(f"Esperando SQL Server en {servidor} ({intento}/{intentos}): {str(exc)[:180]}", flush=True)
            if intento < intentos:
                time.sleep(pausa)

    raise SystemExit(f"SQL Server no estuvo disponible en {servidor} tras {intentos} intentos.")


if __name__ == '__main__':
    raise SystemExit(main())

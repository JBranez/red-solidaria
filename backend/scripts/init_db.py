"""Crea o actualiza la base de datos ejecutando database/NN_*.sql en orden.

Uso:  python -m scripts.init_db            (desde la carpeta backend/, con el entorno virtual activo)

Es idempotente: no borra datos. Requiere cuenta administrativa (MSSQL_SA_PASSWORD o autenticación de Windows).
La cuenta de aplicación se crea con permiso exclusivo de EXECUTE (ver database/09_permissions.sql).
"""
from __future__ import annotations

import re
import sys

from scripts._comunes import (
    DB_DIR, cargar_env, conectar_admin, dividir_lotes, escapar_literal, sustituir_variables, validar_identificador,
)


def variables_sql(cfg: dict[str, str]) -> dict[str, str]:
    for obligatoria in ("DB_NAME", "DB_APP_USER", "DB_APP_PASSWORD"):
        if not cfg.get(obligatoria):
            raise SystemExit(f"Falta {obligatoria}. Ejecute setup.ps1 para generar el archivo .env.")
    return {
        "DB_NAME": validar_identificador(cfg["DB_NAME"], "DB_NAME"),
        "DB_APP_USER": validar_identificador(cfg["DB_APP_USER"], "DB_APP_USER"),
        "DB_APP_PASSWORD": escapar_literal(cfg["DB_APP_PASSWORD"]),
    }


def archivos_sql():
    return sorted(p for p in DB_DIR.glob("*.sql") if re.match(r"\d\d_", p.name))


def main() -> int:
    cfg = cargar_env()
    variables = variables_sql(cfg)
    cn = conectar_admin(cfg)
    cur = cn.cursor()
    total = 0
    for archivo in archivos_sql():
        lotes = dividir_lotes(sustituir_variables(archivo.read_text(encoding="utf-8"), variables))
        print(f"→ {archivo.name:<36} {len(lotes):>3} lotes", flush=True)
        for i, lote in enumerate(lotes, 1):
            try:
                cur.execute(lote)
                while cur.nextset():  # agota resultados para que afloren errores diferidos
                    pass
            except Exception as exc:  # noqa: BLE001
                print(f"\n✗ Error en {archivo.name}, lote {i}:\n{lote[:400]}\n\n{exc}", file=sys.stderr)
                return 1
            total += 1
    cur.execute(f"USE [{variables['DB_NAME']}]")
    resumen = cur.execute(
        "SELECT (SELECT COUNT(*) FROM sys.tables), (SELECT COUNT(*) FROM sys.procedures WHERE name LIKE 'usp[_]%'), "
        "(SELECT COUNT(*) FROM dbo.schema_migracion)"
    ).fetchone()
    print(f"\n✓ Base de datos lista: {resumen[0]} tablas, {resumen[1]} procedimientos, {resumen[2]} migraciones registradas ({total} lotes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

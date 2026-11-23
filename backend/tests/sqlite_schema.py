"""Convierte database/02_tables.sql y 03_indexes.sql a SQLite para VALIDAR LOS DATOS DE CARGA contra las restricciones.

No sustituye a SQL Server (no prueba los procedimientos). Sirve para verificar que la carga cumple PK, FK,
NOT NULL, CHECK y los índices únicos filtrados: es decir, que `seed.py` no fallará por datos inválidos.
"""
from __future__ import annotations

import re
import sqlite3

from tests.sql_utils import DB_DIR, strip_comments

_TIPOS = [
    (r"\bN?VARCHAR\(\w+\)|\bCHAR\(\d+\)", "TEXT"), (r"\bDATETIME2\(\d\)|\bDATE\b", "TEXT"),
    (r"\bDECIMAL\(\d+,\d+\)", "NUMERIC"), (r"\bBIGINT\b|\bTINYINT\b|\bBIT\b|\bINT\b", "INTEGER"),
]
# Restricciones que usan sintaxis exclusiva de T-SQL (clases [a-z], LEN): no se pueden trasladar
_OMITIR = ("ck_usuario_username", "ck_campana_moneda")


def _definiciones(cuerpo: str) -> list[str]:
    """Divide el cuerpo de CREATE TABLE por las comas de nivel 0 (un CHECK puede ocupar varias líneas)."""
    partes, actual, nivel = [], [], 0
    for ch in cuerpo:
        nivel += (ch == "(") - (ch == ")")
        if ch == "," and nivel == 0:
            partes.append("".join(actual)); actual = []
        else:
            actual.append(ch)
    partes.append("".join(actual))
    return [" ".join(p.split()) for p in partes if p.strip()]


def esquema_sqlite() -> list[str]:
    texto = strip_comments((DB_DIR / "02_tables.sql").read_text(encoding="utf-8"))
    sentencias = []
    for m in re.finditer(r"CREATE\s+TABLE\s+dbo\.(\w+)\s*\((.*?)\n\);", texto, re.S | re.I):
        lineas = []
        for linea in _definiciones(m.group(2)):
            if not linea or any(o in linea for o in _OMITIR):
                continue
            linea = re.sub(r"\bN'", "'", linea)
            linea = re.sub(r"CONSTRAINT\s+\w+\s+DEFAULT\s+CONVERT\(DATE,\s*SYSDATETIME\(\)\)", "DEFAULT CURRENT_DATE", linea)
            linea = re.sub(r"CONSTRAINT\s+\w+\s+DEFAULT\s+SYSUTCDATETIME\(\)", "DEFAULT CURRENT_TIMESTAMP", linea)
            linea = re.sub(r"CONSTRAINT\s+\w+\s+DEFAULT", "DEFAULT", linea)
            linea = re.sub(r"\bIDENTITY\(\d+,\d+\)", "", linea)
            linea = re.sub(r"REFERENCES\s+dbo\.", "REFERENCES ", linea)
            if re.match(r"anio\s+AS", linea):
                linea = "anio INTEGER GENERATED ALWAYS AS (CAST(strftime('%Y', fecha_inicio) AS INTEGER)) STORED"
            else:
                for patron, tipo in _TIPOS:
                    linea = re.sub(patron, tipo, linea, count=1) if not linea.startswith("CONSTRAINT") else linea
            lineas.append(linea)
        sentencias.append(f"CREATE TABLE {m.group(1)} (\n  " + ",\n  ".join(lineas) + "\n)")
    idx = strip_comments((DB_DIR / "03_indexes.sql").read_text(encoding="utf-8"))
    for m in re.finditer(r"CREATE\s+(UNIQUE\s+)INDEX\s+(\w+)\s+ON\s+dbo\.(\w+)\s*\(([^)]*)\)(?:\s+INCLUDE\s*\([^)]*\))?\s*(WHERE[^;]*);", idx, re.I | re.S):
        sentencias.append(f"CREATE UNIQUE INDEX {m.group(2)} ON {m.group(3)} ({m.group(4)}) {m.group(5)}")
    for m in re.finditer(r"CREATE\s+(UNIQUE\s+)INDEX\s+(\w+)\s+ON\s+dbo\.(\w+)\s*\(([^)]*)\)\s*;", idx, re.I):
        sentencias.append(f"CREATE UNIQUE INDEX {m.group(2)} ON {m.group(3)} ({m.group(4)})")
    return sentencias


def base_en_memoria() -> sqlite3.Connection:
    cn = sqlite3.connect(":memory:", check_same_thread=False)
    cn.execute("PRAGMA foreign_keys = ON")
    for s in esquema_sqlite():
        cn.execute(s)
    return cn

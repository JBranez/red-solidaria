"""Utilidades para analizar los scripts SQL sin necesitar SQL Server.

Se usan en las pruebas estáticas (test_sql_estatico.py) y de contrato
(test_contrato_sql.py): ninguna requiere una instancia de base de datos.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

DB_DIR = Path(__file__).resolve().parents[2] / "database"

_STR = re.compile(r"N?'(?:[^']|'')*'")
_LINE_COMMENT = re.compile(r"--[^\n]*")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_TYPE = r"(?:N?VARCHAR|VARCHAR|CHAR|INT|BIGINT|TINYINT|BIT|DATE|DATETIME2|DECIMAL|NVARCHAR)"
_DECLARATION = re.compile(rf"@(\w+)\s+(?:AS\s+)?{_TYPE}\b", re.I)


def strip_comments(sql: str) -> str:
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", sql))


def strip_strings(sql: str) -> str:
    return _STR.sub("''", sql)


def sql_files() -> list[Path]:
    return sorted(p for p in DB_DIR.glob("*.sql") if re.match(r"\d\d_", p.name))


def batches(path: Path) -> list[str]:
    """Divide un script en lotes usando GO (como hace sqlcmd / SSMS)."""
    texto = path.read_text(encoding="utf-8")
    return [b.strip() for b in re.split(r"^\s*GO\s*$", texto, flags=re.M | re.I) if b.strip()]


@dataclass
class Param:
    name: str
    has_default: bool


@dataclass
class Procedure:
    name: str
    file: str
    params: list[Param]
    body: str
    required: set[str] = field(init=False)
    names: set[str] = field(init=False)

    def __post_init__(self) -> None:
        self.required = {p.name for p in self.params if not p.has_default}
        self.names = {p.name for p in self.params}


_PROC_HEADER = re.compile(
    r"CREATE\s+OR\s+ALTER\s+PROCEDURE\s+dbo\.(\w+)(.*?)\bAS\b\s*BEGIN", re.I | re.S
)
_PARAM = re.compile(rf"@(\w+)\s+{_TYPE}(?:\s*\([^)]*\))?(\s*=)?", re.I)


def procedures() -> dict[str, Procedure]:
    result: dict[str, Procedure] = {}
    for path in sql_files():
        for batch in batches(path):
            clean = strip_comments(batch)
            m = _PROC_HEADER.search(clean)
            if not m:
                continue
            params = [Param(p.group(1).lower(), bool(p.group(2))) for p in _PARAM.finditer(m.group(2))]
            result[m.group(1)] = Procedure(m.group(1), path.name, params, clean[m.end() - len("BEGIN"):])
    return result


def undeclared_variables(proc: Procedure) -> set[str]:
    """Variables @x usadas en el cuerpo sin estar declaradas como parámetro ni con DECLARE."""
    body = strip_strings(proc.body)
    declared = {m.group(1).lower() for m in _DECLARATION.finditer(body)} | proc.names
    used = {m.group(1).lower() for m in re.finditer(r"(?<!@)@(\w+)", body)}
    return used - declared


def duplicate_declarations(proc: Procedure) -> set[str]:
    body = strip_strings(proc.body)
    seen: dict[str, int] = {}
    for m in re.finditer(r"DECLARE\s+([^;]*?)(?=;|\n\s*(?:SET|IF|SELECT|INSERT|UPDATE|DELETE|EXEC|BEGIN|THROW|DECLARE)\b)",
                         body, re.I | re.S):
        for d in _DECLARATION.finditer(m.group(1)):
            seen[d.group(1).lower()] = seen.get(d.group(1).lower(), 0) + 1
    return {k for k, v in seen.items() if v > 1} & {k for k in seen}


def exec_arguments_with_expressions(proc: Procedure) -> list[str]:
    """En T-SQL los argumentos de EXEC no pueden ser expresiones (+, CASE, funciones)."""
    problems = []
    for m in re.finditer(r"\bEXEC(?:UTE)?\s+dbo\.\w+\s+([^;]*);", strip_strings(proc.body), re.I | re.S):
        args = m.group(1)
        if re.search(r"\+|\bCASE\b|\b(?:LEFT|CONVERT|CAST|ISNULL|COALESCE)\s*\(", args, re.I):
            problems.append(" ".join(args.split())[:80])
    return problems


def block_balance(proc: Procedure) -> dict[str, tuple[int, int]]:
    """Pares (aperturas, cierres) de BEGIN/END, TRY y CATCH. Los END de CASE se descuentan."""
    body = strip_strings(proc.body)
    begin = len(re.findall(r"\bBEGIN\b(?!\s+(?:TRY|CATCH|TRAN|TRANSACTION)\b)", body, re.I))
    end_all = len(re.findall(r"\bEND\b(?!\s+(?:TRY|CATCH)\b)", body, re.I))
    case = len(re.findall(r"\bCASE\b", body, re.I))
    return {
        "BEGIN/END": (begin, end_all - case),
        "TRY": (len(re.findall(r"\bBEGIN\s+TRY\b", body, re.I)), len(re.findall(r"\bEND\s+TRY\b", body, re.I))),
        "CATCH": (len(re.findall(r"\bBEGIN\s+CATCH\b", body, re.I)), len(re.findall(r"\bEND\s+CATCH\b", body, re.I))),
    }


def table_columns() -> dict[str, set[str]]:
    """Columnas de cada tabla según 02_tables.sql (para validar referencias alias.columna)."""
    texto = strip_comments((DB_DIR / "02_tables.sql").read_text(encoding="utf-8"))
    tablas: dict[str, set[str]] = {}
    for m in re.finditer(r"CREATE\s+TABLE\s+dbo\.(\w+)\s*\((.*?)\n\);", texto, re.S | re.I):
        cols = set()
        for linea in m.group(2).splitlines():
            linea = linea.strip()
            c = re.match(r"(\w+)\s+(?:INT|BIGINT|TINYINT|BIT|DATE|DATETIME2|DECIMAL|CHAR|VARCHAR|NVARCHAR)\b|(\w+)\s+AS\s*\(", linea, re.I)
            if c and not re.match(r"CONSTRAINT\b", linea, re.I):
                cols.add((c.group(1) or c.group(2)).lower())
        tablas[m.group(1).lower()] = cols
    return tablas


def unknown_columns(proc: Procedure, tablas: dict[str, set[str]]) -> list[str]:
    """Referencias alias.columna que no existen en la tabla (solo alias de tablas físicas)."""
    body = strip_strings(proc.body)
    alias: dict[str, str] = {}
    for m in re.finditer(r"\b(?:FROM|JOIN|UPDATE)\s+dbo\.(\w+)(?:\s+WITH\s*\([^)]*\))?(?:\s+(?:AS\s+)?(?!WHERE\b|SET\b|ON\b|JOIN\b|LEFT\b|INNER\b|OUTER\b|CROSS\b|WITH\b)(\w+))?",
                         body, re.I):
        tabla = m.group(1).lower()
        if tabla in tablas:
            alias[(m.group(2) or tabla).lower()] = tabla
    errores = []
    for m in re.finditer(r"(?<![\w@.])(\w+)\.(\w+)\b", body):
        a, col = m.group(1).lower(), m.group(2).lower()
        if a in alias and col not in tablas[alias[a]]:
            errores.append(f"{a}.{col} (tabla {alias[a]})")
    return sorted(set(errores))

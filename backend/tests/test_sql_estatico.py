"""Pruebas estáticas del SQL: se ejecutan sin SQL Server.

Cubren lo que un revisor de bases de datos miraría primero: sintaxis, variables, integridad
referencial indexada y coherencia entre el SQL y el código de la aplicación.
"""
import re
from typing import get_args

import pytest

from app.core import permissions as P
from app.schemas import common
from tests import sql_utils as u

PROCS = u.procedures()
TABLAS = u.table_columns()


# ------------------------------------------------------------------ procedimientos
@pytest.mark.parametrize("nombre", sorted(PROCS))
def test_procedimiento_bien_formado(nombre):
    p = PROCS[nombre]
    assert not u.undeclared_variables(p), f"variables sin declarar: {u.undeclared_variables(p)}"
    assert not u.duplicate_declarations(p), f"DECLARE duplicado: {u.duplicate_declarations(p)}"
    assert not u.exec_arguments_with_expressions(p), "los argumentos de EXEC no pueden ser expresiones"
    for bloque, (abre, cierra) in u.block_balance(p).items():
        assert abre == cierra, f"{bloque}: {abre} aperturas vs {cierra} cierres"
    assert not u.unknown_columns(p, TABLAS), f"columnas inexistentes: {u.unknown_columns(p, TABLAS)}"


@pytest.mark.parametrize("nombre", sorted(n for n, p in PROCS.items() if re.search(r"\b(?:INSERT|UPDATE|DELETE)\b", p.body, re.I)))
def test_escritura_es_transaccional_y_propaga_errores(nombre):
    cuerpo = PROCS[nombre].body
    if nombre == "usp_auditoria_registrar":  # un único INSERT atómico; se invoca dentro de la transacción del llamador
        return
    assert re.search(r"SET\s+XACT_ABORT\s+ON", cuerpo, re.I), "falta SET XACT_ABORT ON"
    assert re.search(r"BEGIN\s+TRAN", cuerpo, re.I) and re.search(r"\bCOMMIT\b", cuerpo, re.I)
    assert re.search(r"BEGIN\s+CATCH.*?ROLLBACK.*?THROW\s*;", cuerpo, re.I | re.S), "el CATCH debe hacer ROLLBACK y relanzar con THROW"


def test_ningun_procedimiento_usa_sql_dinamico():
    """El SQL dinámico rompe el encadenamiento de propietarios (la cuenta de aplicación solo tiene EXECUTE)."""
    for p in PROCS.values():
        assert not re.search(r"\bsp_executesql\b|\bEXEC(?:UTE)?\s*\(", p.body, re.I), p.name


def test_listados_paginados_devuelven_total_filas():
    paginados = [n for n, p in PROCS.items() if "OFFSET" in p.body.upper()]
    assert len(paginados) >= 10
    for n in paginados:
        assert "total_filas" in PROCS[n].body, n


# ------------------------------------------------------------------ esquema
def _fks():
    texto = u.strip_comments((u.DB_DIR / "02_tables.sql").read_text(encoding="utf-8"))
    for m in re.finditer(r"CREATE\s+TABLE\s+dbo\.(\w+)\s*\((.*?)\n\);", texto, re.S | re.I):
        for fk in re.finditer(r"FOREIGN\s+KEY\s*\((\w+)\)", m.group(2), re.I):
            yield m.group(1).lower(), fk.group(1).lower()


def _columnas_inicio_de_indices() -> set[tuple[str, str]]:
    cubiertas = set()
    idx = u.strip_comments((u.DB_DIR / "03_indexes.sql").read_text(encoding="utf-8"))
    for m in re.finditer(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+\w+\s+ON\s+dbo\.(\w+)\s*\(\s*(\w+)", idx, re.I):
        cubiertas.add((m.group(1).lower(), m.group(2).lower()))
    tablas = u.strip_comments((u.DB_DIR / "02_tables.sql").read_text(encoding="utf-8"))
    for m in re.finditer(r"CREATE\s+TABLE\s+dbo\.(\w+)\s*\((.*?)\n\);", tablas, re.S | re.I):
        for c in re.finditer(r"(?:PRIMARY\s+KEY|UNIQUE)\s*\(\s*(\w+)", m.group(2), re.I):
            cubiertas.add((m.group(1).lower(), c.group(1).lower()))
    return cubiertas


@pytest.mark.parametrize("tabla,columna", sorted(_fks()))
def test_toda_clave_foranea_tiene_indice(tabla, columna):
    """En SQL Server una FK NO crea índice. El esquema original olvidó entrega.id_voluntario."""
    assert (tabla, columna) in _columnas_inicio_de_indices(), f"{tabla}.{columna} sin índice que la encabece"


def test_toda_tabla_tiene_clave_primaria():
    texto = (u.DB_DIR / "02_tables.sql").read_text(encoding="utf-8")
    for m in re.finditer(r"CREATE\s+TABLE\s+dbo\.(\w+)\s*\((.*?)\n\);", texto, re.S | re.I):
        assert re.search(r"PRIMARY\s+KEY", m.group(2), re.I), m.group(1)


def test_no_hay_instrucciones_destructivas_en_los_scripts():
    for archivo in u.sql_files():
        texto = u.strip_comments(archivo.read_text(encoding="utf-8"))
        assert not re.search(r"\bDROP\s+(?:TABLE|DATABASE|SCHEMA)\b|\bTRUNCATE\b", texto, re.I), archivo.name


# ------------------------------------------------------------------ coherencia SQL ↔ aplicación
def _valores_check(tabla_constraint: str) -> set[str]:
    texto = u.strip_comments((u.DB_DIR / "02_tables.sql").read_text(encoding="utf-8"))
    m = re.search(rf"CONSTRAINT\s+{tabla_constraint}\s+CHECK\s*\(\s*\w+\s+IN\s*\(([^)]*)\)", texto, re.I)
    assert m, tabla_constraint
    return set(re.findall(r"'([^']+)'", m.group(1)))


@pytest.mark.parametrize("constraint,literal", [
    ("ck_campana_estado", common.EstadoCampana),
    ("ck_donacion_estado", common.EstadoDonacion),
    ("ck_gasto_estado", common.EstadoGasto),
    ("ck_entrega_estado", common.EstadoEntrega),
    ("ck_necesidad_estado", common.EstadoNecesidad),
    ("ck_necesidad_urgencia", common.Urgencia),
    ("ck_donante_tipo", common.TipoDonante),
    ("ck_gasto_tipo", common.TipoGasto),
    ("ck_retro_tipo", common.TipoFeedback),
    ("ck_retro_estado", common.EstadoFeedback),
])
def test_valores_de_check_coinciden_con_los_tipos_pydantic(constraint, literal):
    assert _valores_check(constraint) == set(get_args(literal))


def test_permisos_sql_coinciden_con_permisos_python():
    sql = u.strip_comments((u.DB_DIR / "10_reference_data.sql").read_text(encoding="utf-8"))
    bloque = sql.split("MERGE dbo.permiso", 1)[1].split("GO", 1)[0]
    permisos_sql = set(re.findall(r"\('([a-z]+:[a-z]+)',\s*'[a-z]+',", bloque))
    assert permisos_sql == set(P.TODOS)
    asignaciones = set(re.findall(r"\('([A-Z_]+)',\s*'([a-z]+:[a-z]+)'\)", sql.split("FROM (VALUES", 1)[1]))
    esperadas = {(rol, p) for rol, lista in P.ROL_PERMISOS.items() if rol != "ADMIN" for p in lista}
    assert asignaciones == esperadas


def test_roles_sql_coinciden_con_roles_python():
    sql = (u.DB_DIR / "10_reference_data.sql").read_text(encoding="utf-8")
    roles_sql = set(re.findall(r"\(\d, '([A-Z_]+)', N'", sql))
    assert roles_sql == set(P.ROL_PERMISOS)


def test_los_permisos_usados_en_los_routers_existen():
    import pathlib
    usados = set()
    for f in pathlib.Path(u.DB_DIR.parent / "backend" / "app" / "apis").rglob("*.py"):
        usados |= set(re.findall(r"\bP\.([A-Z_]+)\b", f.read_text(encoding="utf-8")))
    definidos = {n for n in dir(P) if n.isupper() and n not in ("TODOS", "ROL_PERMISOS")}
    assert usados <= definidos, usados - definidos


# ------------------------------------------------------------------ gramática T-SQL (sqlfluff)
def test_sintaxis_tsql_con_sqlfluff():
    sqlfluff = pytest.importorskip("sqlfluff")
    from sqlfluff.core import Linter

    sustituciones = {"$(DB_NAME)": "red_solidaria", "$(DB_APP_USER)": "rs_app", "$(DB_APP_PASSWORD)": "x"}
    linter = Linter(dialect="tsql")
    problemas = []
    for archivo in u.sql_files():
        for i, lote in enumerate(u.batches(archivo)):
            for k, v in sustituciones.items():
                lote = lote.replace(k, v)
            if re.search(r"CREATE\s+LOGIN", lote, re.I):  # limitación conocida de la gramática de sqlfluff
                continue
            resultado = linter.parse_string(lote + "\n")
            for v in resultado.violations:
                if v.rule_code().startswith("PRS"):
                    problemas.append(f"{archivo.name} lote {i}: línea {v.line_no}: {v.desc()[:100]}")
    assert not problemas, "\n".join(problemas)
    assert sqlfluff.__version__

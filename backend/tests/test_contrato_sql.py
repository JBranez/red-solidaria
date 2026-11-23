"""Contrato repositorios ↔ procedimientos almacenados (sin necesidad de SQL Server).

Garantiza que cada llamada `db.fetch_*("usp_x", a=..., b=...)` de los repositorios coincide con la firma
real del procedimiento: que exista, que no se envíen parámetros inexistentes y que no falte ninguno obligatorio.
"""
import ast
from pathlib import Path

import pytest

from tests.sql_utils import procedures

REPO_DIR = Path(__file__).resolve().parents[1] / "app" / "repositories"
METODOS = {"fetch_all", "fetch_one", "fetch_sets", "execute", "page"}


def _llamadas():
    for archivo in sorted(REPO_DIR.glob("*.py")):
        arbol = ast.parse(archivo.read_text(encoding="utf-8"))
        for nodo in ast.walk(arbol):
            if (isinstance(nodo, ast.Call) and isinstance(nodo.func, ast.Attribute) and nodo.func.attr in METODOS
                    and nodo.args and isinstance(nodo.args[0], ast.Constant)
                    and isinstance(nodo.args[0].value, str) and nodo.args[0].value.startswith("usp_")):
                kwargs = {k.arg for k in nodo.keywords}
                assert None not in kwargs, f"{archivo.name}:{nodo.lineno} usa **kwargs: el contrato no es verificable"
                yield archivo.name, nodo.lineno, nodo.args[0].value, kwargs


PROCS = procedures()
LLAMADAS = list(_llamadas())


def test_se_encontraron_llamadas_y_procedimientos():
    assert len(PROCS) >= 50
    assert len(LLAMADAS) >= 50


@pytest.mark.parametrize("archivo,linea,proc,kwargs", LLAMADAS, ids=[f"{a}:{l}:{p}" for a, l, p, _ in LLAMADAS])
def test_llamada_coincide_con_la_firma(archivo, linea, proc, kwargs):
    assert proc in PROCS, f"{archivo}:{linea} llama a {proc}, que no existe en database/*.sql"
    firma = PROCS[proc]
    desconocidos = kwargs - firma.names
    assert not desconocidos, f"{archivo}:{linea} {proc}: parámetros inexistentes {sorted(desconocidos)}"
    faltantes = firma.required - kwargs
    assert not faltantes, f"{archivo}:{linea} {proc}: faltan parámetros obligatorios {sorted(faltantes)}"


def test_no_hay_procedimientos_huerfanos():
    usados = {p for _, _, p, _ in LLAMADAS}
    # Se invocan solo desde otros procedimientos
    internos = set()
    huerfanos = set(PROCS) - usados - internos
    assert not huerfanos, f"Procedimientos sin uso en la aplicación: {sorted(huerfanos)}"

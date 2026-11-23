"""Executor: construcción segura de llamadas, lectura de conjuntos de resultados y traducción de errores."""
import pytest

from app.core.errors import (
    AppError, BusinessRuleError, ConfirmationRequiredError, ConflictError, DatabaseUnavailableError, ForbiddenError,
    NotFoundError,
)
from app.db.executor import Executor, parse_sql_error, translate_db_error


class FakeCursor:
    def __init__(self, conjuntos, error_en_nextset=None, error_en_execute=None):
        self._conjuntos, self._i = conjuntos, 0
        self.error_en_nextset, self.error_en_execute = error_en_nextset, error_en_execute
        self.sql = self.args = None
        self.closed = False

    def execute(self, sql, args):
        self.sql, self.args = sql, args
        if self.error_en_execute:
            raise self.error_en_execute

    @property
    def description(self):
        if self._i >= len(self._conjuntos) or self._conjuntos[self._i] is None:
            return None
        return [(c,) for c in self._conjuntos[self._i][0]]

    def fetchall(self):
        return list(self._conjuntos[self._i][1])

    def nextset(self):
        if self.error_en_nextset:
            raise self.error_en_nextset
        self._i += 1
        return self._i < len(self._conjuntos)

    def close(self):
        self.closed = True


class FakeConn:
    def __init__(self, cursor):
        self.cursor_ = cursor

    def cursor(self):
        return self.cursor_


def _ex(*conjuntos, **kw):
    cur = FakeCursor(list(conjuntos), **kw)
    return Executor(FakeConn(cur)), cur


# ---------------------------------------------------------------- construcción segura
def test_build_call_usa_parametros_nombrados_y_marcadores():
    sql, args = Executor.build_call("usp_donacion_crear", {"id_donante": 3, "monto": 10})
    assert sql == "EXEC dbo.usp_donacion_crear @id_donante = ?, @monto = ?"
    assert args == [3, 10]


def test_build_call_sin_parametros():
    assert Executor.build_call("usp_rol_listar", {})[0] == "EXEC dbo.usp_rol_listar"


@pytest.mark.parametrize("nombre", ["usp_x; DROP TABLE donante", "sp_who", "dbo.usp_x", "USP_x", "usp_x--", "", "usp_x y"])
def test_rechaza_nombres_de_procedimiento_peligrosos(nombre):
    with pytest.raises(ValueError):
        Executor.build_call(nombre, {})


@pytest.mark.parametrize("nombre", ["a; DROP", "a b", "1a", "A", "a-b", "a=?"])
def test_rechaza_nombres_de_parametro_peligrosos(nombre):
    with pytest.raises(ValueError):
        Executor.build_call("usp_ok", {nombre: 1})


def test_el_valor_nunca_se_concatena_en_el_sql():
    ex, cur = _ex((["a"], [(1,)]))
    ex.fetch_all("usp_donante_listar", q="'; DROP TABLE donante;--")
    assert "DROP" not in cur.sql
    assert cur.args == ["'; DROP TABLE donante;--"]


# ---------------------------------------------------------------- lectura
def test_fetch_all_devuelve_dicts_y_cierra_el_cursor():
    ex, cur = _ex((["id", "nombre"], [(1, "Ana"), (2, "Luis")]))
    assert ex.fetch_all("usp_x") == [{"id": 1, "nombre": "Ana"}, {"id": 2, "nombre": "Luis"}]
    assert cur.closed


def test_fetch_one_y_vacio():
    ex, _ = _ex((["id"], []))
    assert ex.fetch_one("usp_x") is None


def test_procedimiento_sin_resultado_devuelve_lista_vacia():
    ex, _ = _ex(None)
    assert ex.fetch_all("usp_x") == []


def test_fetch_sets_lee_todos_los_conjuntos():
    ex, _ = _ex((["a"], [(1,)]), (["b"], [(2,), (3,)]))
    assert ex.fetch_sets("usp_x") == [[{"a": 1}], [{"b": 2}, {"b": 3}]]


def test_execute_agota_los_conjuntos_para_que_afloren_errores_diferidos():
    ex, _ = _ex((["a"], [(1,)]), error_en_nextset=Exception("42000", "[SQL Server]Boom (50422) (SQLMoreResults)"))
    with pytest.raises(BusinessRuleError):
        ex.execute("usp_x")


def test_page_extrae_total_y_lo_quita_de_las_filas():
    ex, _ = _ex((["id", "total_filas"], [(1, 42), (2, 42)]))
    filas, total = ex.page("usp_x", pagina=1, tamano=2)
    assert total == 42 and filas == [{"id": 1}, {"id": 2}]


def test_page_fuera_de_rango_averigua_el_total_real():
    llamadas = []

    class Cur(FakeCursor):
        def execute(self, sql, args):
            llamadas.append(args)
            self._conjuntos = [None] if args[0] == 5 else [(["id", "total_filas"], [(1, 11)])]
            self._i = 0

    cur = Cur([])
    filas, total = Executor(FakeConn(cur)).page("usp_x", pagina=5, tamano=10)
    assert filas == [] and total == 11 and len(llamadas) == 2


# ---------------------------------------------------------------- errores
def _msg(texto, numero):
    return ("42000", f"[42000] [Microsoft][ODBC Driver 18 for SQL Server][SQL Server]{texto} ({numero}) (SQLExecDirectW)")


@pytest.mark.parametrize("numero,clase", [
    (50404, NotFoundError), (50409, ConflictError), (50410, ConfirmationRequiredError),
    (50422, BusinessRuleError), (50403, ForbiddenError),
])
def test_traduce_la_serie_50xxx_conservando_el_mensaje(numero, clase):
    err = translate_db_error(Exception(*_msg("La campaña no existe.", numero)))
    assert isinstance(err, clase) and err.mensaje == "La campaña no existe."


def test_parse_sql_error_con_mensaje_multilinea():
    num, msg = parse_sql_error("[SQL Server]Línea 1\nLínea 2 (50422) (SQLExecDirectW)")
    assert num == 50422 and "Línea 2" in msg


def test_violacion_de_unicidad_no_filtra_detalles_internos():
    err = translate_db_error(Exception(*_msg("Violation of UNIQUE KEY constraint 'uq_donante_correo'. The duplicate key value is (a@b.c).", 2627)))
    assert isinstance(err, ConflictError)
    assert "uq_donante_correo" not in err.mensaje and "a@b.c" not in err.mensaje


def test_interbloqueo_se_informa_como_conflicto_reintentable():
    err = translate_db_error(Exception(*_msg("Transaction was deadlocked", 1205)))
    assert isinstance(err, ConflictError) and err.codigo == "CONCURRENCIA"


@pytest.mark.parametrize("sqlstate", ["08001", "08S01", "HYT00", "28000"])
def test_fallos_de_conexion_son_503(sqlstate):
    assert isinstance(translate_db_error(Exception(sqlstate, "Login timeout expired")), DatabaseUnavailableError)


def test_error_desconocido_es_generico_y_no_expone_el_mensaje():
    err = translate_db_error(Exception("42000", "[SQL Server]Invalid object name 'dbo.secreta' (208) (SQLExecDirectW)"))
    assert type(err) is AppError and "secreta" not in err.mensaje


def test_una_excepcion_de_dominio_pasa_sin_cambios():
    original = NotFoundError("x")
    assert translate_db_error(original) is original


def test_errores_en_execute_se_traducen():
    ex, cur = _ex((["a"], [(1,)]), error_en_execute=Exception(*_msg("No existe.", 50404)))
    with pytest.raises(NotFoundError):
        ex.fetch_all("usp_x")
    assert cur.closed

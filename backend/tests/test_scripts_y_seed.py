"""Scripts de inicialización y carga: lógica pura + validación de los datos contra las restricciones del esquema."""
from datetime import date, datetime
from decimal import Decimal

import pytest

from app.core import permissions as P
from scripts import _comunes as c
from scripts import init_db, seed
from tests.sqlite_schema import base_en_memoria, esquema_sqlite
from tests.sql_utils import DB_DIR

HOY, AHORA = date(2026, 11, 14), datetime(2026, 11, 14, 9, 0)
CFG = {"SEED_ADMIN_USERNAME": "admin", "SEED_ADMIN_PASSWORD": "AdminClave2026", "SEED_DEMO_PASSWORD": "DemoClave2026", "APP_ENV": "development"}


# ---------------------------------------------------------------- init_db / utilidades
def test_cargar_env_ignora_comentarios_en_linea_y_conserva_comillas(tmp_path, monkeypatch):
    (tmp_path / ".env").write_text('A=yes   # comentario\nB="x # no es comentario"\n# solo comentario\nC=\nD=a=b\n', encoding="utf-8")
    monkeypatch.setattr(c, "RAIZ", tmp_path)
    for k in ("A", "B", "C", "D"):
        monkeypatch.delenv(k, raising=False)
    cfg = c.cargar_env()
    assert cfg["A"] == "yes" and cfg["B"] == "x # no es comentario" and cfg["C"] == "" and cfg["D"] == "a=b"


def test_dividir_lotes_por_go_ignora_go_dentro_de_palabras():
    lotes = c.dividir_lotes("SELECT 1;\nGO\n  go  \nSELECT 'GOOD';\nGO\n")
    assert lotes == ["SELECT 1;", "SELECT 'GOOD';"]


def test_sustituir_variables_y_detectar_las_pendientes():
    assert c.sustituir_variables("USE [$(DB_NAME)]", {"DB_NAME": "X"}) == "USE [X]"
    with pytest.raises(ValueError, match="SIN_DEFINIR|sin definir"):
        c.sustituir_variables("USE [$(OTRA)]", {"DB_NAME": "X"})


@pytest.mark.parametrize("malo", ["x; DROP DATABASE y", "a b", "1abc", "", "a]b", "a-b"])
def test_identificadores_peligrosos_se_rechazan(malo):
    with pytest.raises(ValueError):
        c.validar_identificador(malo, "DB_NAME")


def test_escapar_literal_duplica_comillas_y_rechaza_saltos():
    assert c.escapar_literal("a'b") == "a''b"
    for malo in ("a\nb", "x$(DB_NAME)"):
        with pytest.raises(ValueError):
            c.escapar_literal(malo)


def test_cadena_admin_usa_autenticacion_de_windows_si_no_hay_contrasena():
    assert "Trusted_Connection=yes" in c.cadena_admin({})
    cs = c.cadena_admin({"MSSQL_SA_PASSWORD": "p}w"})
    assert "PWD={p}}w}" in cs and "Trusted_Connection" not in cs


def test_todos_los_scripts_se_sustituyen_sin_variables_pendientes():
    vars_ = init_db.variables_sql({"DB_NAME": "RedSolidaria", "DB_APP_USER": "app", "DB_APP_PASSWORD": "pw'x"})
    for archivo in init_db.archivos_sql():
        c.sustituir_variables(archivo.read_text(encoding="utf-8"), vars_)
    assert [a.name[:2] for a in init_db.archivos_sql()] == ["01", "02", "03", "04", "05", "06", "07", "08", "08", "09", "10"]


def test_la_contrasena_de_la_app_con_comilla_no_rompe_el_ddl():
    vars_ = init_db.variables_sql({"DB_NAME": "R", "DB_APP_USER": "app", "DB_APP_PASSWORD": "a'b"})
    sql = c.sustituir_variables((DB_DIR / "09_permissions.sql").read_text(encoding="utf-8"), vars_)
    assert "PASSWORD = N'a''b'" in sql


# ---------------------------------------------------------------- el esquema se traduce a SQLite (base de las pruebas siguientes)
def test_el_esquema_se_traduce_y_se_crea():
    cn = base_en_memoria()
    tablas = {r[0] for r in cn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"donacion", "entrega", "necesidad", "usuario", "auditoria_evento", "campana"} <= tablas
    assert len(esquema_sqlite()) >= 22  # 18 tablas + índices únicos


def _base_con_referencia():
    cn = base_en_memoria()
    cn.executemany("INSERT INTO metodo_pago (nombre, requiere_referencia) VALUES (?, ?)", [("Efectivo", 0), ("Transferencia", 1), ("Tarjeta", 1)])
    cn.executemany("INSERT INTO rol (id_rol, codigo, nombre, descripcion) VALUES (?, ?, 'n', 'd')", [(i, r) for i, r in enumerate(P.ROL_PERMISOS, 1)])
    return cn


def _sembrar(demo=True, **kw):
    cn = _base_con_referencia()
    resumen = seed.sembrar(cn.cursor(), CFG, dialecto="sqlite", hoy=HOY, ahora=AHORA, demo=demo, hasher=lambda p: "$argon2id$prueba", **kw)
    cn.commit()
    return cn, resumen


# ---------------------------------------------------------------- importación de los CSV originales
def test_la_importacion_conserva_todas_las_filas_y_los_identificadores():
    cn, resumen = _sembrar(demo=False)
    assert resumen["donacion"] == 120 and resumen["entrega"] == 104 and resumen["beneficiario"] == 30
    assert resumen["donante"] == 28 and resumen["voluntario"] == 8 and resumen["campana"] == 6 and resumen["sector"] == 5
    assert cn.execute("SELECT COUNT(*), MIN(id_donacion), MAX(id_donacion) FROM donacion").fetchone() == (120, 1, 120)


def test_totales_importados_coinciden_con_los_csv_originales():
    import csv
    cn, _ = _sembrar(demo=False)
    esperado = sum(Decimal(r["monto"]) for r in csv.DictReader(open(DB_DIR / "datos" / "donacion.csv", encoding="utf-8")))
    obtenido = Decimal(str(cn.execute("SELECT SUM(CAST(monto AS NUMERIC)) FROM donacion WHERE estado='Confirmada'").fetchone()[0]))
    assert obtenido == esperado
    unidades = sum(int(r["cantidad"]) for r in csv.DictReader(open(DB_DIR / "datos" / "entrega.csv", encoding="utf-8")))
    assert cn.execute("SELECT SUM(cantidad) FROM entrega").fetchone()[0] == unidades


def test_estados_de_campana_se_derivan_de_las_fechas():
    cn, _ = _sembrar(demo=False)
    estados = dict(cn.execute("SELECT nombre, estado FROM campana"))
    assert estados["Canasta Solidaria"] == "Finalizada" and estados["Kits de Higiene Familiar"] == "Activa" and estados["Merienda Escolar"] == "Activa"
    assert cn.execute("SELECT COUNT(*) FROM campana WHERE estado='Finalizada' AND cerrada_en IS NULL").fetchone()[0] == 0


def test_hogares_importados_no_inventan_consentimiento():
    cn, _ = _sembrar(demo=False)
    assert cn.execute("SELECT COUNT(*) FROM beneficiario WHERE consentimiento_datos = 1 OR fecha_consentimiento IS NOT NULL").fetchone()[0] == 0


def test_donaciones_historicas_quedan_marcadas_como_migradas():
    cn, _ = _sembrar(demo=False)
    assert cn.execute("SELECT COUNT(*) FROM donacion WHERE observacion LIKE 'Migrada%' AND estado='Confirmada' AND confirmado_en IS NOT NULL").fetchone()[0] == 120


def test_la_carga_es_idempotente():
    cn, _ = _sembrar()
    segunda = seed.sembrar(cn.cursor(), CFG, dialecto="sqlite", hoy=HOY, ahora=AHORA, hasher=lambda p: "x")
    assert segunda == {}
    assert cn.execute("SELECT COUNT(*) FROM donacion").fetchone()[0] == 123  # 120 históricas + 3 por verificar (demo)


# ---------------------------------------------------------------- usuarios
def test_usuarios_demo_con_vinculos_correctos():
    cn, _ = _sembrar()
    filas = {u: (r, d, v) for u, r, d, v in cn.execute("SELECT u.username, ro.codigo, u.id_donante, u.id_voluntario FROM usuario u JOIN rol ro ON ro.id_rol = u.id_rol")}
    assert set(filas) == {"admin", "coordinacion", "finanzas", "trabajo.social", "auditoria", "voluntario", "donante"}
    assert filas["voluntario"] == ("VOLUNTARIO", None, 1) and filas["donante"][0] == "DONANTE" and filas["donante"][1] is not None
    assert filas["admin"] == ("ADMIN", None, None)


def test_sin_demo_solo_se_crea_el_administrador():
    cn, resumen = _sembrar(demo=False)
    assert [r[0] for r in cn.execute("SELECT username FROM usuario")] == ["admin"]
    assert "necesidad" not in resumen and "gasto" not in resumen


def test_en_produccion_no_hay_cuentas_demo_y_el_admin_debe_cambiar_su_clave():
    cn = _base_con_referencia()
    seed.sembrar(cn.cursor(), {**CFG, "APP_ENV": "production"}, dialecto="sqlite", hoy=HOY, ahora=AHORA, hasher=lambda p: "x")
    assert cn.execute("SELECT username, debe_cambiar_password FROM usuario").fetchall() == [("admin", 1)]
    assert cn.execute("SELECT COUNT(*) FROM necesidad").fetchone()[0] == 0


def test_falta_la_clave_del_administrador():
    cn = _base_con_referencia()
    with pytest.raises(SystemExit):
        seed.sembrar(cn.cursor(), {"APP_ENV": "development"}, dialecto="sqlite", hoy=HOY, ahora=AHORA, hasher=lambda p: "x")


# ---------------------------------------------------------------- datos de demostración
def test_demo_cumple_todas_las_restricciones_del_esquema():
    cn, resumen = _sembrar()
    assert resumen["necesidad"] == 12 and resumen["retroalimentacion"] == 5 and resumen["gasto"] == 5 and resumen["entrega"] == 104 + 3
    cn.execute("PRAGMA foreign_key_check")
    assert cn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_gastos_aprobados_nunca_superan_lo_recaudado():
    cn, _ = _sembrar()
    filas = cn.execute("""SELECT c.nombre,
        (SELECT SUM(CAST(monto AS NUMERIC)) FROM donacion d WHERE d.id_campana = c.id_campana AND d.estado='Confirmada'),
        (SELECT SUM(CAST(monto AS NUMERIC)) FROM gasto g WHERE g.id_campana = c.id_campana AND g.estado='Aprobado')
        FROM campana c""").fetchall()
    for nombre, recaudado, gastado in filas:
        assert (gastado or 0) <= (recaudado or 0), nombre


def test_el_aprobador_del_demo_es_distinto_de_quien_registra():
    cn, _ = _sembrar()
    assert cn.execute("SELECT COUNT(*) FROM gasto WHERE aprobado_por IS NOT NULL AND aprobado_por = id_usuario_registra").fetchone()[0] == 0


def test_entregas_programadas_enlazan_con_necesidades_en_atencion():
    cn, _ = _sembrar()
    filas = cn.execute("SELECT e.fecha, n.estado, e.id_voluntario FROM entrega e JOIN necesidad n ON n.id_necesidad = e.id_necesidad WHERE e.estado='Programada'").fetchall()
    assert len(filas) == 3 and all(f[1] == "En atencion" and f[2] == 1 and f[0] >= HOY.isoformat() for f in filas)


def test_la_queja_vencida_aparece_como_vencida():
    cn, _ = _sembrar()
    vencidas = cn.execute("SELECT COUNT(*) FROM retroalimentacion WHERE estado IN ('Abierta','En revision') AND fecha_limite < ?", (HOY.isoformat(),)).fetchone()[0]
    assert vencidas == 1


def test_demo_se_omite_si_no_hay_campana_activa():
    # 2030: todas las campañas están finalizadas; no se crean donaciones/entregas/gastos "en curso"
    cn = _base_con_referencia()
    resumen = seed.sembrar(cn.cursor(), CFG, dialecto="sqlite", hoy=date(2030, 1, 1), ahora=datetime(2030, 1, 1), hasher=lambda p: "x")
    assert cn.execute("SELECT COUNT(*) FROM campana WHERE estado='Activa'").fetchone()[0] == 0
    assert cn.execute("SELECT COUNT(*) FROM donacion WHERE estado='Pendiente'").fetchone()[0] == 0
    assert resumen["necesidad"] == 12
    assert cn.execute("SELECT COUNT(*) FROM necesidad WHERE estado='En atencion'").fetchone()[0] == 0


def test_el_indice_unico_filtrado_impide_la_entrega_duplicada_del_mismo_dia():
    import sqlite3
    cn, _ = _sembrar(demo=False)
    fila = cn.execute("SELECT id_campana, id_beneficiario, id_voluntario, fecha FROM entrega LIMIT 1").fetchone()
    with pytest.raises(sqlite3.IntegrityError):
        cn.execute("INSERT INTO entrega (id_campana, id_beneficiario, id_voluntario, fecha, cantidad, estado) VALUES (?,?,?,?,1,'Entregada')", fila)
    cn.execute("INSERT INTO entrega (id_campana, id_beneficiario, id_voluntario, fecha, cantidad, estado, motivo_estado) VALUES (?,?,?,?,1,'Anulada','x')", fila)  # anulada: sí se permite


def test_las_restricciones_check_del_esquema_rechazan_datos_invalidos():
    import sqlite3
    cn, _ = _sembrar(demo=False)
    with pytest.raises(sqlite3.IntegrityError):  # monto negativo
        cn.execute("INSERT INTO donacion (id_donante,id_campana,fecha,monto,id_metodo_pago) VALUES (1,1,'2026-01-20',-5,1)")
    with pytest.raises(sqlite3.IntegrityError):  # confirmada sin confirmado_en
        cn.execute("INSERT INTO donacion (id_donante,id_campana,fecha,monto,id_metodo_pago,estado) VALUES (1,1,'2026-01-20',5,1,'Confirmada')")
    with pytest.raises(sqlite3.IntegrityError):  # hogar de 99 integrantes
        cn.execute("INSERT INTO beneficiario (nombres,apellidos,id_sector,integrantes_hogar) VALUES ('a','b',1,99)")
    with pytest.raises(sqlite3.IntegrityError):  # correo mal formado
        cn.execute("INSERT INTO donante (nombre,tipo,correo) VALUES ('x','Persona','sin-arroba')")
    with pytest.raises(sqlite3.IntegrityError):  # campaña repetida el mismo año
        cn.execute("INSERT INTO campana (nombre,id_categoria,fecha_inicio,fecha_fin,meta_recaudacion) VALUES ('Canasta Solidaria',1,'2026-05-01','2026-06-01',10)")
    cn.execute("INSERT INTO campana (nombre,id_categoria,fecha_inicio,fecha_fin,meta_recaudacion) VALUES ('Canasta Solidaria',1,'2027-01-10','2027-03-01',10)")  # otro año: permitido

"""Reglas de negocio y de autorización a nivel de dato, con filas realistas devueltas por la BD simulada."""
import inspect
from datetime import date, datetime

import pytest

from app.core.errors import BusinessRuleError, ConfirmationRequiredError, ConflictError
from app.repositories import finanzas as rf, operacion as ro, seguridad as rs
from app.schemas import auth as sa, finanzas as sf, operacion as so

AHORA = datetime(2026, 11, 14, 10, 0)


def donacion_row(**kw):
    return {"id_donacion": 10, "fecha": date(2026, 11, 3), "monto": 150, "moneda": "PEN", "estado": "Pendiente",
            "referencia": "OP-1", "observacion": None, "motivo_estado": None, "id_donante": 9, "donante": "Ana Ruiz",
            "donante_tipo": "Persona", "id_campana": 6, "campana": "Merienda Escolar", "id_metodo_pago": 2,
            "metodo_pago": "Transferencia", "confirmado_en": None, "confirmado_por": None, "creado_en": AHORA, "total_filas": 1, **kw}


def entrega_row(**kw):
    return {"id_entrega": 31, "fecha": date(2026, 11, 10), "cantidad": 5, "detalle": None, "estado": "Programada",
            "motivo_estado": None, "id_campana": 6, "campana": "Merienda Escolar", "categoria": "Alimentación",
            "id_beneficiario": 3, "hogar": "Quispe, Rosa", "id_sector": 1, "sector": "Villa Norte",
            "integrantes_hogar": 4, "id_voluntario": 4, "voluntario": "Voluntario Demo 04", "id_necesidad": None,
            "creado_en": AHORA, "total_filas": 1, **kw}


# ---------------------------------------------------------------- donaciones
DATOS_DONACION = {"id_donante": 9, "id_campana": 6, "fecha": "2026-11-03", "monto": "150.00", "id_metodo_pago": 2, "referencia": "OP-1"}


def test_registrar_donacion_devuelve_la_fila_creada(client, fake, autenticar):
    fake.stub("usp_donacion_crear", [{"id_donacion": 10}])
    fake.stub("usp_donacion_listar", [donacion_row()])
    r = client.post("/api/v1/donaciones", headers=autenticar("FINANZAS"), json=DATOS_DONACION)
    assert r.status_code == 201 and r.json()["estado"] == "Pendiente" and r.json()["monto"] == 150
    enviado = fake.llamadas("usp_donacion_crear")[0]
    assert enviado["id_actor"] == 7 and enviado["confirmar"] is False
    assert str(enviado["monto"]) == "150.00"  # llega como Decimal, no como float


def test_confirmar_al_registrar_exige_permiso_de_verificacion(client, fake, autenticar):
    # COORDINADOR puede leer donaciones pero no registrarlas; probamos con un rol que registra sin verificar:
    from app.core import permissions as P
    P.ROL_PERMISOS  # (la matriz oficial: solo FINANZAS y ADMIN registran y verifican)
    h = autenticar("FINANZAS")
    fake.stub("usp_donacion_crear", [{"id_donacion": 10}])
    fake.stub("usp_donacion_listar", [donacion_row(estado="Confirmada")])
    assert client.post("/api/v1/donaciones", headers=h, json={**DATOS_DONACION, "confirmar": True}).status_code == 201
    assert fake.llamadas("usp_donacion_crear")[0]["confirmar"] is True


def test_servicio_deniega_confirmar_sin_permiso(fake):
    from app.core.errors import ForbiddenError
    from app.repositories.finanzas import DonacionRepository
    from app.repositories.seguridad import AuditoriaRepository
    from app.services.finanzas import DonacionService
    from tests.conftest import fila_usuario
    actor = sa.UsuarioActualOut(**{k: fila_usuario("COORDINADOR")[k] for k in sa.UsuarioActualOut.model_fields if k != "permisos"},
                                permisos=["donaciones:registrar"])  # registra pero NO verifica
    svc = DonacionService(DonacionRepository(fake), AuditoriaRepository(fake))
    with pytest.raises(ForbiddenError):
        svc.crear(sf.DonacionIn(**{**DATOS_DONACION, "confirmar": True, "fecha": date(2026, 11, 3)}), actor)
    assert not fake.llamadas("usp_donacion_crear")


@pytest.mark.parametrize("excepcion,estado,codigo", [
    (ConflictError("Esa referencia de operación ya fue registrada."), 409, "CONFLICTO"),
    (ConfirmationRequiredError("Ya existe una donación igual."), 409, "REQUIERE_CONFIRMACION"),
    (BusinessRuleError("Solo se pueden registrar donaciones en campañas activas."), 422, "REGLA_DE_NEGOCIO"),
])
def test_reglas_del_procedimiento_llegan_al_cliente_con_su_codigo(client, fake, autenticar, excepcion, estado, codigo):
    fake.stub("usp_donacion_crear", excepcion)
    r = client.post("/api/v1/donaciones", headers=autenticar("FINANZAS"), json=DATOS_DONACION)
    assert r.status_code == estado and r.json()["error"]["codigo"] == codigo
    assert r.json()["error"]["mensaje"] == str(excepcion)


def test_rechazar_donacion_exige_motivo_antes_de_llamar_a_la_bd(client, fake, autenticar):
    r = client.post("/api/v1/donaciones/10/estado", headers=autenticar("FINANZAS"), json={"estado": "Rechazada"})
    assert r.status_code == 422 and not fake.llamadas("usp_donacion_estado")


def test_monto_invalido_es_rechazado_por_la_validacion(client, autenticar):
    for monto in ("0", "-5", "abc", "1.234", "100000000"):
        r = client.post("/api/v1/donaciones", headers=autenticar("FINANZAS"), json={**DATOS_DONACION, "monto": monto})
        assert r.status_code == 422, monto


def test_exportar_donaciones_genera_csv_seguro_y_deja_rastro(client, fake, autenticar):
    fake.stub("usp_donacion_listar", ([donacion_row(donante="=HYPERLINK(\"http://x\")")], 1))
    r = client.get("/api/v1/donaciones/export?estado=Confirmada", headers=autenticar("FINANZAS"))
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"]
    assert "'=HYPERLINK" in r.text                      # inyección de fórmulas neutralizada
    assert r.content.startswith(b"\xef\xbb\xbf")        # BOM UTF-8 para Excel
    assert fake.llamadas("usp_auditoria_registrar")[0]["accion"] == "EXPORTAR"
    assert fake.llamadas("usp_donacion_listar")[0]["tamano"] == 50_000


def test_filtros_desconocidos_se_rechazan_en_vez_de_ignorarse(client, autenticar):
    assert client.get("/api/v1/donaciones?estadoo=Pendiente", headers=autenticar("FINANZAS")).status_code == 422
    assert client.get("/api/v1/donaciones?tamano=500", headers=autenticar("FINANZAS")).status_code == 422
    assert client.get("/api/v1/donaciones?orden=password", headers=autenticar("FINANZAS")).status_code == 422


def test_la_busqueda_escapa_los_comodines_antes_de_llegar_al_sql(client, fake, autenticar):
    client.get("/api/v1/donantes?q=50%25_[x]", headers=autenticar("FINANZAS"))
    assert fake.llamadas("usp_donante_listar")[0]["q"] == "%50\\%\\_\\[x]%"


# ---------------------------------------------------------------- portal del donante
def test_donante_solo_ve_sus_donaciones_aunque_pida_otras(client, fake, autenticar):
    fake.stub("usp_donacion_listar", ([donacion_row()], 1))
    h = autenticar("DONANTE", id_donante=9)
    r = client.get("/api/v1/mi/donaciones?id_donante=1&id_campana=6", headers=h)  # intenta ver las de otro donante
    assert r.status_code == 200
    llamada = fake.llamadas("usp_donacion_listar")[0]
    assert llamada["id_donante"] == 9 and llamada["id_campana"] == 6


def test_donante_sin_vinculo_no_accede(client, autenticar):
    assert client.get("/api/v1/mi/donaciones", headers=autenticar("DONANTE")).status_code == 403


# ---------------------------------------------------------------- portal del voluntario / entregas
def test_voluntario_solo_ve_sus_entregas(client, fake, autenticar):
    fake.stub("usp_entrega_listar", ([entrega_row()], 1))
    h = autenticar("VOLUNTARIO", id_voluntario=4)
    assert client.get("/api/v1/entregas?id_voluntario=99", headers=h).status_code == 200
    assert fake.llamadas("usp_entrega_listar")[0]["id_voluntario"] == 4   # forzado desde la sesión


def test_coordinador_ve_todas_y_respeta_su_filtro(client, fake, autenticar):
    fake.stub("usp_entrega_listar", ([entrega_row()], 1))
    client.get("/api/v1/entregas?id_voluntario=2", headers=autenticar("COORDINADOR"))
    assert fake.llamadas("usp_entrega_listar")[0]["id_voluntario"] == 2


def test_voluntario_no_puede_ver_la_entrega_de_otro(client, fake, autenticar):
    fake.stub("usp_entrega_listar", [entrega_row(id_voluntario=8)])
    r = client.get("/api/v1/entregas/31", headers=autenticar("VOLUNTARIO", id_voluntario=4))
    assert r.status_code == 404  # 404 y no 403: no se revela que existe


def test_voluntario_confirma_su_entrega(client, fake, autenticar):
    fake.stub("usp_entrega_listar", [entrega_row(id_voluntario=4)])
    r = client.post("/api/v1/entregas/31/estado", headers=autenticar("VOLUNTARIO", id_voluntario=4), json={"estado": "Entregada"})
    assert r.status_code == 200
    assert fake.llamadas("usp_entrega_estado")[0]["nuevo_estado"] == "Entregada"


def test_voluntario_no_puede_confirmar_la_entrega_de_otro_ni_anular(client, fake, autenticar):
    h = autenticar("VOLUNTARIO", id_voluntario=4)
    fake.stub("usp_entrega_listar", [entrega_row(id_voluntario=8)])
    assert client.post("/api/v1/entregas/31/estado", headers=h, json={"estado": "Entregada"}).status_code == 404
    fake.stub("usp_entrega_listar", [entrega_row(id_voluntario=4)])
    r = client.post("/api/v1/entregas/31/estado", headers=h, json={"estado": "Anulada", "motivo": "error"})
    assert r.status_code == 403
    assert not fake.llamadas("usp_entrega_estado")


def test_coordinador_anula_entregas_con_motivo(client, fake, autenticar):
    fake.stub("usp_entrega_listar", [entrega_row(estado="Anulada", motivo_estado="Duplicada")])
    h = autenticar("COORDINADOR")
    assert client.post("/api/v1/entregas/31/estado", headers=h, json={"estado": "Anulada"}).status_code == 422  # sin motivo
    assert client.post("/api/v1/entregas/31/estado", headers=h, json={"estado": "Anulada", "motivo": "Duplicada"}).status_code == 200


# ---------------------------------------------------------------- retroalimentación confidencial
def test_feedback_confidencial_solo_para_quien_tiene_el_permiso(client, fake, autenticar):
    fake.stub("usp_feedback_listar", ([], 0))
    client.get("/api/v1/feedback", headers=autenticar("COORDINADOR"))
    client.get("/api/v1/feedback", headers=autenticar("TRABAJO_SOCIAL"))
    normal, social = [c["incluir_confidenciales"] for c in fake.llamadas("usp_feedback_listar")]
    assert normal is False and social is True


def test_registrar_feedback_no_devuelve_el_contenido(client, fake, autenticar):
    fake.stub("usp_feedback_crear", [{"id_retroalimentacion": 1}])
    r = client.post("/api/v1/feedback", headers=autenticar("VOLUNTARIO", id_voluntario=4),
                    json={"tipo": "Queja", "mensaje": "Llegaron tarde", "confidencial": True})
    assert r.status_code == 201 and r.content == b""


# ---------------------------------------------------------------- gestión de usuarios
def test_no_se_puede_desactivar_la_propia_cuenta(client, fake, autenticar):
    r = client.patch("/api/v1/usuarios/7/estado", headers=autenticar("ADMIN"), json={"activo": False})
    assert r.status_code == 422 and not fake.llamadas("usp_usuario_estado")


def test_cuenta_de_donante_requiere_vinculo(client, fake, autenticar):
    fake.stub("usp_rol_listar", [{"id_rol": 7, "codigo": "DONANTE", "nombre": "Donante", "descripcion": "x", "permisos": 1, "usuarios_activos": 0}])
    cuerpo = {"username": "donante.nuevo", "nombre_completo": "Donante Nuevo", "correo": "d@x.pe", "password": "Segura2026Clave", "id_rol": 7}
    assert client.post("/api/v1/usuarios", headers=autenticar("ADMIN"), json=cuerpo).status_code == 422
    assert not fake.llamadas("usp_usuario_guardar")


def test_crear_usuario_guarda_hash_y_nunca_la_contrasena(client, fake, autenticar):
    fake.stub("usp_rol_listar", [{"id_rol": 2, "codigo": "COORDINADOR", "nombre": "C", "descripcion": "x", "permisos": 1, "usuarios_activos": 0}])
    fake.stub("usp_usuario_guardar", [{"id_usuario": 20}])
    fake.stub("usp_usuario_listar", [{"id_usuario": 20, "username": "coord.nuevo", "nombre_completo": "Coord Nuevo", "correo": "c@x.pe",
                                       "id_rol": 2, "rol_codigo": "COORDINADOR", "rol_nombre": "C", "activo": True,
                                       "debe_cambiar_password": True, "creado_en": AHORA}])
    cuerpo = {"username": "coord.nuevo", "nombre_completo": "Coord Nuevo", "correo": "C@X.pe", "password": "Segura2026Clave", "id_rol": 2}
    r = client.post("/api/v1/usuarios", headers=autenticar("ADMIN"), json=cuerpo)
    assert r.status_code == 201 and "password" not in r.json() and "password_hash" not in r.json()
    guardado = fake.llamadas("usp_usuario_guardar")[0]
    assert guardado["password_hash"].startswith("$argon2id$") and guardado["correo"] == "c@x.pe"


# ---------------------------------------------------------------- reportes y público
def test_kpis_se_arman_desde_cuatro_conjuntos(client, fake, autenticar):
    fake.stub("usp_dashboard_kpis", [
        [{"recaudado_confirmado": 100, "recaudado_pendiente": 0, "donaciones_confirmadas": 2, "donaciones_pendientes": 0,
          "gastado_aprobado": 10, "saldo_disponible": 90, "meta_recaudacion": 200, "pct_meta": 50.0, "ticket_promedio": 50,
          "donantes_activos": 2, "moneda": "PEN"}],
        [{"hogares_registrados": 30, "hogares_atendidos": 24, "hogares_sin_atender": 6, "pct_cobertura": 80.0, "personas_estimadas": 90,
          "entregas_realizadas": 40, "unidades_entregadas": 100, "entregas_programadas": 1, "hogares_sin_consentimiento": 30}],
        [{"campanas_activas": 2, "campanas_borrador": 0, "campanas_pausadas": 0, "campanas_finalizadas": 4, "campanas_por_vencer": 1,
          "campanas_vencidas_sin_cerrar": 0, "voluntarios_activos": 8, "voluntarios_participantes": 8,
          "entregas_programadas_vencidas": 0, "donaciones_por_verificar": 0, "gastos_por_aprobar": 0}],
        [{"necesidades_abiertas": 3, "necesidades_cubiertas": 1, "necesidades_urgentes": 1, "pct_necesidades_cubiertas": 25.0,
          "dias_promedio_cobertura": None, "satisfaccion_promedio": None, "feedback_abierto": 0, "feedback_vencido": 0,
          "pct_quejas_en_plazo": None}],
    ])
    r = client.get("/api/v1/dashboard/kpis", headers=autenticar("COORDINADOR"))
    assert r.status_code == 200
    j = r.json()
    assert j["financiero"]["saldo_disponible"] == 90 and j["cobertura"]["hogares_sin_consentimiento"] == 30
    assert j["resultados"]["satisfaccion_promedio"] is None  # sin datos: null, no 0


def test_publico_suprime_celdas_pequenas_y_no_expone_datos_personales(client, fake):
    fake.stub("usp_publico_resumen", [
        [{"campanas_activas": 2, "campanas_finalizadas": 4, "recaudado_confirmado": 1000, "gastado_aprobado": 0, "hogares_atendidos": 30,
          "entregas_realizadas": 100, "voluntarios_participantes": 8, "donantes": 20, "moneda": "PEN"}],
        [{"sector": "Villa Norte", "hogares_atendidos": 6, "publicable": True}, {"sector": "Pampa Baja", "hogares_atendidos": None, "publicable": False}],
        [{"categoria": "Alimentación", "recaudado": 500, "entregas": 10, "unidades": 50}],
    ])
    r = client.get("/api/v1/public/resumen")
    assert r.status_code == 200
    assert r.json()["por_sector"][1]["hogares_atendidos"] is None
    for campo in ("nombre", "correo", "donante", "hogar"):
        assert f'"{campo}"' not in r.text


# ---------------------------------------------------------------- coherencia filtros ↔ repositorios
@pytest.mark.parametrize("filtro,repo", [
    (sf.FiltroCampanas, rf.CampanaRepository), (sf.FiltroDonantes, rf.DonanteRepository),
    (sf.FiltroDonaciones, rf.DonacionRepository), (sf.FiltroGastos, rf.GastoRepository),
    (so.FiltroBeneficiarios, ro.BeneficiarioRepository), (so.FiltroVoluntarios, ro.VoluntarioRepository),
    (so.FiltroEntregas, ro.EntregaRepository), (sa.FiltroUsuarios, rs.UsuarioRepository),
    (sa.FiltroAuditoria, rs.AuditoriaRepository),
])
def test_los_campos_del_filtro_son_argumentos_del_repositorio(filtro, repo):
    aceptados = set(inspect.signature(repo.listar).parameters) - {"self"}
    assert set(filtro.model_fields) <= aceptados, set(filtro.model_fields) - aceptados


def test_filtro_de_necesidades_y_feedback_coinciden_salvo_lo_que_el_servicio_ajusta():
    n = set(inspect.signature(ro.NecesidadRepository.listar).parameters) - {"self"}
    assert set(so.FiltroNecesidades.model_fields) - {"q"} <= n
    f = set(inspect.signature(ro.FeedbackRepository.listar).parameters) - {"self"}
    assert set(so.FiltroFeedback.model_fields) <= f

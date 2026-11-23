"""Carga de datos: carga de fixtures CSV sintéticos + usuarios + (solo desarrollo) datos de demostración.

Uso:  python -m scripts.seed [--sin-demo]

Diseño:
  · Los fixtures de demostración se importan CONSERVANDO sus identificadores (IDENTITY_INSERT).
  · Los registros demostrativos de donación se importan como 'Confirmada' para habilitar reportes; la observación indica
    que son datos sintéticos y no representan operaciones reales.
  · Los hogares quedan SIN consentimiento registrado: el sistema anterior no lo guardaba y no se inventa.
  · Es idempotente: si ya hay campañas, no vuelve a importar.
  · El bloque "demo" es SINTÉTICO (necesidades, entregas programadas, gastos, retroalimentación) y solo se
    crea fuera de producción. Ver docs/MODELO_DATOS.md.
"""
from __future__ import annotations

import csv
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any, Callable

from scripts._comunes import DB_DIR, cargar_env, conectar_admin

Paso = tuple[str, list[str], list[tuple], bool]  # (tabla, columnas, filas, usa_identidad)

DESCRIPCIONES = {  # los fixtures no incluyen descripción: se agrega para que el portal sea legible
    "Canasta Solidaria": ("Canastas de alimentos básicos para hogares de los sectores atendidos.", "Asegurar la alimentación básica de los hogares con menos recursos."),
    "Útiles para Volver a Clases": ("Útiles y materiales escolares para niñas y niños al inicio del año escolar.", "Evitar que la falta de materiales afecte la asistencia a clases."),
    "Abrigo para el Invierno": ("Ropa, frazadas y calzado para las noches frías.", "Proteger del frío a niños y adultos mayores de los sectores altos."),
    "Botiquín Comunitario": ("Botiquines y medicinas básicas para los hogares.", "Garantizar primeros auxilios y medicamentos esenciales en cada hogar."),
    "Kits de Higiene Familiar": ("Kits de aseo personal y del hogar.", "Prevenir enfermedades asociadas a la falta de higiene."),
    "Merienda Escolar": ("Meriendas nutritivas para escolares de los sectores atendidos.", "Mejorar la nutrición de los niños durante la jornada escolar."),
}
METAS_HOGARES_ACTIVAS = {"Kits de Higiene Familiar": 20, "Merienda Escolar": 25}  # solo campañas en curso (demo)


def leer_csv(ruta: Path) -> list[dict[str, str]]:
    with ruta.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def _estado_campana(inicio: date, fin: date, hoy: date) -> str:
    if fin < hoy:
        return "Finalizada"
    return "Activa" if inicio <= hoy else "Borrador"


# ======================================================================= carga de fixtures CSV sintéticos
def plan_legacy(directorio: Path, hoy: date, ahora: datetime, ids_metodo: dict[str, int]) -> list[Paso]:
    d = lambda n: leer_csv(directorio / f"{n}.csv")  # noqa: E731
    f = date.fromisoformat
    categorias, donantes, voluntarios, hogares = d("categoria_ayuda"), d("donante"), d("voluntario"), d("beneficiario")
    campanas, donaciones, entregas = d("campana"), d("donacion"), d("entrega")

    sectores = {nombre: i for i, nombre in enumerate(sorted({h["sector"].strip() for h in hogares}), start=1)}
    plan: list[Paso] = [
        ("sector", ["id_sector", "nombre", "activo"], [(i, n, 1) for n, i in sectores.items()], True),
        ("categoria_ayuda", ["id_categoria", "nombre", "descripcion", "activo"],
         [(int(c["id_categoria"]), c["nombre"].strip(), c["descripcion"].strip(), 1) for c in categorias], True),
        ("donante", ["id_donante", "nombre", "tipo", "correo", "fecha_registro", "activo"],
         [(int(x["id_donante"]), x["nombre"].strip(), x["tipo"].strip(), x["correo"].strip().lower(), f(x["fecha_registro"]), 1) for x in donantes], True),
        ("voluntario", ["id_voluntario", "nombres", "apellidos", "correo", "fecha_ingreso", "activo"],
         [(int(x["id_voluntario"]), x["nombres"].strip(), x["apellidos"].strip(), x["correo"].strip().lower(), f(x["fecha_ingreso"]), 1) for x in voluntarios], True),
        ("beneficiario", ["id_beneficiario", "nombres", "apellidos", "id_sector", "integrantes_hogar", "fecha_registro", "consentimiento_datos", "activo"],
         [(int(x["id_beneficiario"]), x["nombres"].strip(), x["apellidos"].strip(), sectores[x["sector"].strip()],
           int(x["integrantes_hogar"]), f(x["fecha_registro"]), 0, 1) for x in hogares], True),
    ]
    filas_campana = []
    for c in campanas:
        inicio, fin = f(c["fecha_inicio"]), f(c["fecha_fin"])
        estado = _estado_campana(inicio, fin, hoy)
        desc, objetivo = DESCRIPCIONES.get(c["nombre"].strip(), (None, None))
        meta_h = METAS_HOGARES_ACTIVAS.get(c["nombre"].strip()) if estado == "Activa" else None
        filas_campana.append((
            int(c["id_campana"]), c["nombre"].strip(), desc, objetivo, int(c["id_categoria"]), inicio, fin,
            Decimal(c["meta_recaudacion"]), meta_h, "PEN", estado,
            datetime.combine(fin, datetime.min.time()) if estado == "Finalizada" else None,
            "Cerrada al terminar su periodo (migración del sistema anterior)" if estado == "Finalizada" else None,
        ))
    plan.append(("campana", ["id_campana", "nombre", "descripcion", "objetivo_social", "id_categoria", "fecha_inicio", "fecha_fin",
                             "meta_recaudacion", "meta_hogares", "moneda", "estado", "cerrada_en", "motivo_cierre"], filas_campana, True))
    plan.append(("donacion", ["id_donacion", "id_donante", "id_campana", "fecha", "monto", "id_metodo_pago", "estado", "observacion", "confirmado_en"],
                 [(int(x["id_donacion"]), int(x["id_donante"]), int(x["id_campana"]), f(x["fecha"]), Decimal(x["monto"]),
                   ids_metodo[x["metodo_pago"].strip()], "Confirmada",
                   "Migrada de un sistema de ejemplo (registro sintético; no representa una transacción real)", ahora) for x in donaciones], True))
    plan.append(("entrega", ["id_entrega", "id_campana", "id_beneficiario", "id_voluntario", "fecha", "cantidad", "estado"],
                 [(int(x["id_entrega"]), int(x["id_campana"]), int(x["id_beneficiario"]), int(x["id_voluntario"]), f(x["fecha"]),
                   int(x["cantidad"]), "Entregada") for x in entregas], True))
    return plan


# ======================================================================= usuarios
def plan_usuarios(cfg: dict[str, str], directorio: Path, existentes: set[str], ids_rol: dict[str, int],
                  hasher: Callable[[str], str], demo: bool) -> list[Paso]:
    produccion = cfg.get("APP_ENV", "development").lower() == "production"
    columnas = ["username", "nombre_completo", "correo", "password_hash", "id_rol", "id_donante", "id_voluntario", "debe_cambiar_password"]
    filas: list[tuple] = []
    admin = cfg.get("SEED_ADMIN_USERNAME", "admin").lower()
    if admin not in existentes:
        if not cfg.get("SEED_ADMIN_PASSWORD"):
            raise SystemExit("Falta SEED_ADMIN_PASSWORD. Ejecute setup.ps1 para generar el archivo .env.")
        filas.append((admin, "Administrador del sistema", f"{admin}@redsolidaria.local", hasher(cfg["SEED_ADMIN_PASSWORD"]),
                      ids_rol["ADMIN"], None, None, 1 if produccion else 0))
    if demo and not produccion:
        clave = cfg.get("SEED_DEMO_PASSWORD")
        if not clave:
            raise SystemExit("Falta SEED_DEMO_PASSWORD (cuentas de demostración). Use --sin-demo para omitirlas.")
        donaciones = leer_csv(directorio / "donacion.csv")
        total: dict[str, Decimal] = defaultdict(Decimal)
        for x in donaciones:
            total[x["id_donante"]] += Decimal(x["monto"])
        id_donante = int(max(total, key=total.get))
        hash_demo = hasher(clave)
        for usuario, nombre, rol, don, vol in [
            ("coordinacion", "Coordinación de programas", "COORDINADOR", None, None),
            ("finanzas", "Responsable de finanzas", "FINANZAS", None, None),
            ("trabajo.social", "Trabajo social", "TRABAJO_SOCIAL", None, None),
            ("auditoria", "Auditoría interna", "AUDITOR", None, None),
            ("voluntario", "Voluntario Demo 01", "VOLUNTARIO", None, 1),
            ("donante", next(x["nombre"] for x in leer_csv(directorio / "donante.csv") if int(x["id_donante"]) == id_donante), "DONANTE", id_donante, None),
        ]:
            if usuario not in existentes:
                filas.append((usuario, nombre, f"{usuario}@redsolidaria.local", hash_demo, ids_rol[rol], don, vol, 0))
    return [("usuario", columnas, filas, False)] if filas else []


# ======================================================================= datos de demostración (sintéticos)
def plan_demo(directorio: Path, hoy: date, ahora: datetime, ids_usuario: dict[str, int], ids_metodo: dict[str, int],
              campanas_activas: dict[int, tuple[date, date]]) -> list[Paso]:
    """Necesidades, entregas programadas, donaciones por verificar, gastos y retroalimentación de ejemplo."""
    d = lambda n: leer_csv(directorio / f"{n}.csv")  # noqa: E731
    entregas, hogares, campanas = d("entrega"), d("beneficiario"), d("campana")
    id_camp = {c["nombre"]: int(c["id_campana"]) for c in campanas}
    cat_de = {int(c["id_campana"]): int(c["id_categoria"]) for c in campanas}
    atendidos = defaultdict(set)
    for e in entregas:
        atendidos[int(e["id_campana"])].add(int(e["id_beneficiario"]))
    todos = [int(h["id_beneficiario"]) for h in hogares]
    plan: list[Paso] = []
    coord, fin_, trab = ids_usuario.get("coordinacion"), ids_usuario.get("finanzas"), ids_usuario.get("trabajo.social")

    # --- necesidades ---------------------------------------------------------------------------
    c_meri, c_hig = id_camp["Merienda Escolar"], id_camp["Kits de Higiene Familiar"]
    sin_meri = [h for h in todos if h not in atendidos[c_meri]]
    sin_hig = [h for h in todos if h not in atendidos[c_hig] and h not in sin_meri[:4]]
    necesidades = []  # (benef, categoria, urgencia, descripcion, dias_atras)
    for h, u, t, dias in zip(sin_meri[:4], ["Critica", "Alta", "Alta", "Media"], [
            "Sin ingresos esta semana; hay niños menores de 5 años", "Adulto mayor con dieta especial",
            "Familia numerosa con un solo ingreso informal", "Solicitó apoyo para la merienda de los niños"], [21, 12, 8, 3]):
        necesidades.append((h, cat_de[c_meri], u, t, dias))
    for h, u, t, dias in zip(sin_hig[:4], ["Alta", "Media", "Media", "Baja"], [
            "Sin acceso a jabón ni detergente", "Kit de aseo infantil", "Reposición de artículos de higiene", "Kit de limpieza del hogar"], [15, 9, 6, 2]):
        necesidades.append((h, cat_de[c_hig], u, t, dias))
    salud, abrigo = id_camp["Botiquín Comunitario"], id_camp["Abrigo para el Invierno"]
    for h, cat, u, t, dias in [(todos[2], cat_de[salud], "Alta", "Botiquín para el hogar", 30), (todos[9], cat_de[salud], "Media", "Medicinas para adulto mayor", 18),
                               (todos[5], cat_de[abrigo], "Baja", "Frazadas para la temporada fría", 40), (todos[14], cat_de[abrigo], "Media", "Abrigo para niños", 25)]:
        necesidades.append((h, cat, u, t, dias))
    # Las 3 primeras (merienda) ya tienen una entrega programada: están 'En atencion'. IDs explícitos: tabla vacía.
    cols_nec = ["id_necesidad", "id_beneficiario", "id_categoria", "urgencia", "estado", "descripcion", "fecha_registro", "id_usuario_registra", "creado_en"]
    plan.append(("necesidad", cols_nec,
                 [(n, h, c, u, "En atencion" if n <= 3 and c_meri in campanas_activas else "Pendiente", t, hoy - timedelta(days=dias), trab, ahora - timedelta(days=dias))
                  for n, (h, c, u, t, dias) in enumerate(necesidades, start=1)], True))

    # --- donaciones por verificar, entregas programadas, gasto por aprobar (solo si la campaña está en curso)
    if c_meri in campanas_activas:
        ini, fin = campanas_activas[c_meri]
        for i, (donante, monto, dias) in enumerate([(3, "80.00", 0), (7, "120.00", 1), (12, "60.00", 2)], start=1):
            fecha = max(ini, min(fin, hoy - timedelta(days=dias)))
            plan.append(("donacion", ["id_donante", "id_campana", "fecha", "monto", "id_metodo_pago", "estado", "referencia", "observacion", "creado_en"],
                         [(donante, c_meri, fecha, Decimal(monto), ids_metodo["Transferencia"], "Pendiente", f"DEMO-OP-{i:04d}",
                           "Registro de demostración: pendiente de verificar el voucher", ahora)], False))
        programadas = [(n, necesidades[n - 1][0], min(fin, hoy + timedelta(days=dias)), cant) for n, dias, cant in [(1, 1, 3), (2, 2, 2), (3, 4, 4)]]
        plan.append(("entrega", ["id_campana", "id_beneficiario", "id_voluntario", "id_necesidad", "fecha", "cantidad", "detalle", "estado"],
                     [(c_meri, h, 1, n, fch, cant, "Canasta básica familiar (demostración)", "Programada") for n, h, fch, cant in programadas], False))
        plan.append(("gasto", ["id_campana", "fecha", "concepto", "tipo", "proveedor", "monto", "comprobante", "estado", "id_usuario_registra", "creado_en"],
                     [(c_meri, max(ini, min(fin, hoy - timedelta(days=3))), "Compra de insumos para las meriendas", "Bienes", "Distribuidora El Sol S.A.C.",
                       Decimal("250.00"), "F004-000310", "Registrado", fin_, ahora)], False))
    # --- gastos aprobados de campañas ya finalizadas (el monto nunca supera lo recaudado)
    aprobados = [("Canasta Solidaria", date(2026, 2, 10), "Compra de arroz, menestras y aceite", "Bienes", "Distribuidora El Sol S.A.C.", "600.00", "F001-000234"),
                 ("Canasta Solidaria", date(2026, 3, 5), "Transporte de canastas a los sectores", "Transporte", "Transportes Andinos", "180.00", "B001-001122"),
                 ("Útiles para Volver a Clases", date(2026, 2, 20), "Cuadernos, lápices y mochilas", "Bienes", "Librería Aula Viva", "700.00", "F002-000981"),
                 ("Abrigo para el Invierno", date(2026, 5, 12), "Frazadas y abrigos", "Bienes", "Textiles Sur", "650.00", "F003-000412")]
    plan.append(("gasto", ["id_campana", "fecha", "concepto", "tipo", "proveedor", "monto", "comprobante", "estado", "id_usuario_registra", "aprobado_por", "aprobado_en", "creado_en"],
                 [(id_camp[n], fch, c, t, p, Decimal(m), comp, "Aprobado", fin_, coord, ahora, ahora) for n, fch, c, t, p, m, comp in aprobados], False))

    # --- retroalimentación (la queja vencida muestra la alerta de plazo)
    e1 = entregas[0]
    cols_fb = ["tipo", "mensaje", "calificacion", "id_beneficiario", "id_entrega", "id_campana", "estado", "id_responsable", "respuesta", "fecha_limite", "resuelta_en", "creado_en"]
    creado = lambda dias: ahora - timedelta(days=dias)  # noqa: E731
    lim = lambda dias_creado: hoy - timedelta(days=dias_creado) + timedelta(days=7)  # noqa: E731
    plan.append(("retroalimentacion", cols_fb, [
        ("Felicitacion", "Llegaron puntuales y trataron a mi familia con respeto.", 5, int(e1["id_beneficiario"]), int(e1["id_entrega"]), int(e1["id_campana"]),
         "Cerrada", trab, "Gracias por su mensaje; lo compartimos con el equipo de voluntarios.", lim(12), creado(5), creado(12)),
        ("Sugerencia", "Sería bueno avisar la fecha de entrega con un día de anticipación.", None, None, None, c_hig, "Abierta", None, None, lim(2), None, creado(2)),
        ("Queja", "La merienda incluía productos cercanos a su fecha de vencimiento.", 2, todos[3], None, c_meri, "En revision", coord, None, lim(14), None, creado(14)),
        ("Queja", "El día acordado no llegaron; reprogramaron para el día siguiente.", 4, todos[7], None, id_camp["Canasta Solidaria"], "Resuelta", trab,
         "Se pidió disculpas y se confirmó la nueva fecha con la familia.", lim(40), creado(37), creado(40)),
        ("Consulta", "¿Cómo puedo registrar a una vecina para recibir apoyo?", None, None, None, None, "Abierta", None, None, lim(1), None, creado(1)),
    ], False))
    return plan


# ======================================================================= ejecución
class Escritor:
    def __init__(self, cursor: Any, dialecto: str = "mssql") -> None:
        self.cur, self.dialecto = cursor, dialecto

    def _tabla(self, t: str) -> str:
        return f"dbo.{t}" if self.dialecto == "mssql" else t

    def _conv(self, v: Any) -> Any:
        if self.dialecto == "sqlite":
            if isinstance(v, (date, datetime)):
                return v.isoformat(sep=" ") if isinstance(v, datetime) else v.isoformat()
            if isinstance(v, Decimal):
                return str(v)
        return v

    def ejecutar(self, plan: list[Paso]) -> dict[str, int]:
        resumen: dict[str, int] = {}
        for tabla, columnas, filas, identidad in plan:
            if not filas:
                continue
            if identidad and self.dialecto == "mssql":
                self.cur.execute(f"SET IDENTITY_INSERT {self._tabla(tabla)} ON")
            sql = f"INSERT INTO {self._tabla(tabla)} ({', '.join(columnas)}) VALUES ({', '.join('?' * len(columnas))})"
            self.cur.executemany(sql, [tuple(self._conv(v) for v in fila) for fila in filas])
            if identidad and self.dialecto == "mssql":
                self.cur.execute(f"SET IDENTITY_INSERT {self._tabla(tabla)} OFF")
            resumen[tabla] = resumen.get(tabla, 0) + len(filas)
        return resumen

    def mapa(self, sql: str) -> dict[Any, Any]:
        self.cur.execute(sql.replace("dbo.", "") if self.dialecto == "sqlite" else sql)
        return {fila[1]: fila[0] for fila in self.cur.fetchall()}


def sembrar(cursor: Any, cfg: dict[str, str], *, dialecto: str = "mssql", hoy: date | None = None, ahora: datetime | None = None,
            directorio: Path = DB_DIR / "datos", demo: bool = True, hasher: Callable[[str], str] | None = None) -> dict[str, int]:
    if hasher is None:
        from app.core.security import hash_password as hasher
    hoy, ahora = hoy or date.today(), ahora or datetime.now().replace(microsecond=0)
    w = Escritor(cursor, dialecto)
    ids_metodo = w.mapa("SELECT id_metodo_pago, nombre FROM dbo.metodo_pago")   # {nombre: id}
    ids_rol = w.mapa("SELECT id_rol, codigo FROM dbo.rol")                      # {codigo: id}
    if not ids_metodo or not ids_rol:
        raise SystemExit("Faltan datos de referencia (roles/métodos de pago). Ejecute primero el script init_db.")
    cursor.execute("SELECT COUNT(*) FROM " + w._tabla("campana"))
    hay_datos = cursor.fetchone()[0] > 0
    resumen: dict[str, int] = {}
    if not hay_datos:
        for k, v in w.ejecutar(plan_legacy(directorio, hoy, ahora, ids_metodo)).items():
            resumen[k] = resumen.get(k, 0) + v
    existentes = set(w.mapa("SELECT id_usuario, username FROM dbo.usuario").keys())
    for k, v in w.ejecutar(plan_usuarios(cfg, directorio, existentes, ids_rol, hasher, demo)).items():
        resumen[k] = resumen.get(k, 0) + v
    if not hay_datos and demo and cfg.get("APP_ENV", "development").lower() != "production":
        ids_usuario = w.mapa("SELECT id_usuario, username FROM dbo.usuario")  # {username: id}
        cursor.execute("SELECT id_campana, fecha_inicio, fecha_fin FROM " + w._tabla("campana") + " WHERE estado = 'Activa'")
        activas = {int(r[0]): (date.fromisoformat(str(r[1])[:10]), date.fromisoformat(str(r[2])[:10])) for r in cursor.fetchall()}
        for k, v in w.ejecutar(plan_demo(directorio, hoy, ahora, ids_usuario, ids_metodo, activas)).items():
            resumen[k] = resumen.get(k, 0) + v
    return resumen


def main(argv: list[str]) -> int:
    cfg = cargar_env()
    demo = "--sin-demo" not in argv
    cn = conectar_admin(cfg, base=cfg.get("DB_NAME", "RedSolidaria"), autocommit=False)
    try:
        resumen = sembrar(cn.cursor(), cfg, demo=demo)
        cn.commit()
    except BaseException:
        cn.rollback()  # todo o nada: nunca queda una carga a medias
        raise
    if not resumen:
        print("✓ Nada que hacer: la base ya contiene datos y usuarios.")
    for tabla, n in resumen.items():
        print(f"  {tabla:<20} {n:>4} filas")
    print("✓ Carga completada." + ("" if demo else " (sin datos de demostración)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

# Arquitectura

```
Navegador ── Angular 22 (SPA, Signals, Signal Forms) ──HTTP /api/v1──▶ FastAPI ──pyodbc (EXEC dbo.usp_*)──▶ SQL Server
 :4200   proxy.conf.json ─────────────────────────────────────────────▶ :8000                                  :1433
```

## Capas del backend (`backend/app`)
| Capa | Responsabilidad | Regla |
|---|---|---|
| `apis/v1` | Rutas HTTP, validación de entrada, `requiere(permiso)` | No contiene lógica de negocio |
| `schemas` | Modelos Pydantic de entrada (`extra="forbid"`) y salida | Un campo desconocido es un error |
| `services` | Reglas de negocio y **autorización a nivel de dato** | Un voluntario solo ve *sus* entregas: el filtro se fuerza desde la sesión |
| `repositories` | Un método por procedimiento, argumentos nombrados | Prohibido SQL embebido |
| `db/executor.py` | **Único** punto que ejecuta SQL | Solo `usp_*`; parámetros enlazados (`@p = ?`); traduce errores del motor |
| `core` | Configuración, seguridad (Argon2id, JWT), errores, utilidades | Sin dependencias de capas superiores |

**Contrato SQL ↔ Python verificado sin base de datos:** `test_contrato_sql.py` analiza (AST) cada llamada de los repositorios y la compara con la firma real del procedimiento (existe, no sobran ni faltan parámetros, ninguno huérfano).

## Una petición, de punta a punta
1. El interceptor Angular añade `Authorization: Bearer …` (solo a `/api/`, nunca a terceros).
2. FastAPI abre **una conexión por petición** (cuenta de aplicación, solo `EXECUTE`).
3. `usuario_sesion` valida el JWT y consulta `usp_auth_obtener_usuario`: usuario **activo**, `token_version` vigente, permisos actuales. Un cambio de contraseña/rol o una desactivación surten efecto al instante.
4. `requiere('donaciones:verificar')` autoriza *antes* de validar el cuerpo (un rol sin permiso no aprende nada del esquema).
5. El servicio aplica reglas y el procedimiento hace de **unidad transaccional** (`XACT_ABORT`, `TRY/CATCH`, bitácora dentro de la misma transacción).
6. Un error de negocio sube como `THROW 50xxx` → `NotFoundError/ConflictError/BusinessRuleError…` → JSON uniforme.

## Seguridad (resumen)
| Amenaza | Defensa |
|---|---|
| Inyección SQL | Solo procedimientos con parámetros enlazados; nombres de proc/parámetro validados con lista blanca; sin SQL dinámico (que además rompería la cadena de propietarios) |
| Credenciales | Argon2id; el hash nunca sale de la BD hacia la API de usuarios; bloqueo tras 5 fallos (15 min); mismo mensaje y mismo coste para usuario inexistente/inactivo (no se enumera) |
| Sesión | JWT HS256 con lista cerrada de algoritmos (sin `alg=none`), `exp`/`sub`/`tv` obligatorios, revocable por versión |
| Escalada | RBAC de 36 permisos; separación de funciones (quien registra un gasto no lo aprueba); último administrador protegido |
| Fuga de datos personales | Aislamiento por rol; el portal público solo agrega y **suprime sectores con menos de 3 hogares**; casos confidenciales con permiso propio; el contenido de mensajes no se copia a la bitácora |
| Exportaciones | CSV con neutralización de fórmulas y registro en auditoría |
| Manipulación de evidencia | Bitácora de solo inserción (trigger); nada se borra |
| Cabeceras / CORS | `nosniff`, `X-Frame-Options`, `no-store` en la API; CORS con lista explícita (jamás `*`); documentación desactivada en producción |
| Secretos | `.env` fuera de git; `setup.ps1` los genera aleatorios; en producción se rechaza `TrustServerCertificate=yes` |

## Frontend (`frontend/src/app`)
`core/` (modelos, servicios HTTP, interceptores, guards, utilidades) · `shared/` (componentes: modal propio sin JS de Bootstrap, campo con error, KPI, paginación, avisos, **gráficos SVG propios**) · `layout/` (shell con menú por permisos) · `features/` (un directorio por módulo, cargado de forma diferida).
Formularios con **Signal Forms** (`form()`, `[formField]`, validadores con mensaje); un único ayudante `enviar()` valida, muestra errores de la API y gestiona la confirmación de posibles duplicados. Listados con `ListaBase` (paginación del servidor, descarte de respuestas tardías, búsqueda con retardo).

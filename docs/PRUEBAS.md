# Pruebas

| Suite | Pruebas | Qué cubre |
|---|---|---|
| Backend (`pytest`) | **402** | ver tabla inferior |
| Frontend (`ng test`, Vitest) | **36** | formato de fechas sin desfase horario, `ApiError`, sesión, interceptores (Bearer solo a la API; 401/403), guards, `ListaBase` (respuestas tardías, página fuera de rango), `enviar()` (validación, errores, confirmación de duplicados) |
| Compilación | ✓ | `ng build` de producción con `strictTemplates`: 675 kB inicial (126,7 kB transferidos) |

| Archivo (backend) | Pruebas | Qué demuestra |
|---|---|---|
| `test_sql_estatico.py` | 125 | 53 procedimientos bien formados; toda FK con índice; ningún `DROP`/SQL dinámico; `CHECK` = tipos Pydantic; permisos y roles SQL = código; gramática T-SQL (sqlfluff) |
| `test_contrato_sql.py` | 67 | Cada llamada de los repositorios coincide con la firma real del procedimiento; sin procedimientos huérfanos |
| `test_auth_api.py` + `test_autorizacion.py` | 72 | Login, bloqueo, revocación de sesión, tokens manipulados (`alg=none`, otra clave, vencido), **48 casos de la matriz rol × endpoint** |
| `test_flujos_api.py` | 36 | Reglas de negocio, aislamiento por dato (donante/voluntario), CSV seguro y auditado, confidencialidad |
| `test_executor.py` + `test_seguridad_y_config.py` | 70 | Inyección SQL imposible por construcción, traducción de errores sin filtrar detalles, Argon2, JWT, configuración |
| `test_scripts_y_seed.py` | 32 | La carga cumple PK/FK/CHECK/únicos del esquema; totales = CSV; idempotencia; producción sin cuentas demo |

**Pruebas de mutación manuales realizadas:** se rompió a propósito el filtro forzado por sesión (donante/voluntario) y el verificador de SQL con 5 clases de defecto: las pruebas fallaron como debían.

## Qué NO se verificó (léalo antes de entregar)
1. **Los procedimientos no se ejecutaron en SQL Server** (no había instancia). Se validó su sintaxis (sqlfluff), su coherencia interna y su contrato con Python, pero no su comportamiento en el motor. Riesgos residuales a mirar en la primera ejecución: opciones `SET` requeridas por índices filtrados (los scripts las activan), la cadena de propietarios con `DENY` (documentada en `09_permissions.sql`), `COLLATE` de la base.
2. Los `.ps1` se analizaron con el *parser* de PowerShell y se ejecutó la generación de secretos/`.env`, pero **no se corrieron en Windows**.
3. La interfaz se recorrió con Chromium *headless* contra un servidor de apoyo con los datos sembrados (no incluido en la entrega); no hay pruebas E2E automatizadas ni auditoría de accesibilidad con herramienta.

# API REST

Base: `/api/v1`. Documentación interactiva (solo fuera de producción): `/docs`. Generado desde el código; **74 operaciones**.

| Método | Ruta | Descripción | Permiso requerido |
|---|---|---|---|
| GET | `/api/v1/auditoria` | Bitácora de auditoría (solo lectura) | auditoria:leer |
| POST | `/api/v1/auth/cambiar-password` | Cambiar la contraseña propia | sesión válida |
| POST | `/api/v1/auth/login` | Iniciar sesión | público |
| POST | `/api/v1/auth/logout` | Registrar el cierre de sesión | sesión válida |
| GET | `/api/v1/auth/me` | Usuario de la sesión y sus permisos | sesión válida |
| GET | `/api/v1/beneficiarios` | Listar Beneficiarios | beneficiarios:leer |
| POST | `/api/v1/beneficiarios` | Crear Beneficiario | beneficiarios:escribir |
| GET | `/api/v1/beneficiarios/{id_beneficiario}` | Obtener Beneficiario | beneficiarios:leer |
| PUT | `/api/v1/beneficiarios/{id_beneficiario}` | Actualizar Beneficiario | beneficiarios:escribir |
| PATCH | `/api/v1/beneficiarios/{id_beneficiario}/estado` | Estado Beneficiario | beneficiarios:escribir |
| GET | `/api/v1/campanas` | Listar Campanas | campanas:leer |
| POST | `/api/v1/campanas` | Crear Campana | campanas:escribir |
| GET | `/api/v1/campanas/{id_campana}` | Obtener Campana | campanas:leer |
| PUT | `/api/v1/campanas/{id_campana}` | Actualizar Campana | campanas:escribir |
| GET | `/api/v1/campanas/{id_campana}/cierre` | Informe de cierre / rendición de cuentas | campanas:leer |
| POST | `/api/v1/campanas/{id_campana}/estado` | Activar, pausar, finalizar o cancelar | campanas:estado |
| GET | `/api/v1/categorias` | Listar Categorias | sesión válida |
| POST | `/api/v1/categorias` | Crear Categoria | sesión válida |
| PUT | `/api/v1/categorias/{id_categoria}` | Actualizar Categoria | sesión válida |
| PATCH | `/api/v1/categorias/{id_categoria}/estado` | Estado Categoria | sesión válida |
| GET | `/api/v1/dashboard/categorias` | Por Categoria | dashboard:leer |
| GET | `/api/v1/dashboard/kpis` | Indicadores por nivel: financiero, cobertura, operación, resultados | dashboard:leer |
| GET | `/api/v1/dashboard/sectores` | Por Sector | dashboard:leer |
| GET | `/api/v1/dashboard/series` | Series | dashboard:leer |
| GET | `/api/v1/donaciones` | Listar Donaciones | donaciones:leer |
| POST | `/api/v1/donaciones` | Crear Donacion | donaciones:registrar |
| GET | `/api/v1/donaciones/export` | Exportar donaciones a CSV (queda en la bitácora) | donaciones:exportar |
| GET | `/api/v1/donaciones/{id_donacion}` | Obtener Donacion | donaciones:leer |
| POST | `/api/v1/donaciones/{id_donacion}/estado` | Confirmar, rechazar o anular | donaciones:verificar |
| GET | `/api/v1/donantes` | Listar Donantes | donantes:leer |
| POST | `/api/v1/donantes` | Crear Donante | donantes:escribir |
| GET | `/api/v1/donantes/{id_donante}` | Obtener Donante | donantes:leer |
| PUT | `/api/v1/donantes/{id_donante}` | Actualizar Donante | donantes:escribir |
| PATCH | `/api/v1/donantes/{id_donante}/estado` | Estado Donante | donantes:escribir |
| GET | `/api/v1/entregas` | Listar Entregas | entregas:leer, entregas:propias |
| POST | `/api/v1/entregas` | Crear Entrega | entregas:registrar |
| GET | `/api/v1/entregas/export` | Exportar entregas a CSV (queda en la bitácora) | reportes:exportar |
| GET | `/api/v1/entregas/{id_entrega}` | Obtener Entrega | entregas:leer, entregas:propias |
| POST | `/api/v1/entregas/{id_entrega}/estado` | Entregada, no realizada o anulada | entregas:gestionar, entregas:propias |
| GET | `/api/v1/feedback` | Listar Feedback | feedback:leer |
| POST | `/api/v1/feedback` | Registrar retroalimentación, consulta o queja | feedback:registrar |
| POST | `/api/v1/feedback/{id_retroalimentacion}/gestionar` | Gestionar Feedback | feedback:gestionar |
| GET | `/api/v1/gastos` | Listar Gastos | gastos:leer |
| POST | `/api/v1/gastos` | Crear Gasto | gastos:registrar |
| POST | `/api/v1/gastos/{id_gasto}/estado` | Aprobar o anular (aprueba alguien distinto de quien registró) | gastos:aprobar |
| GET | `/api/v1/metodos-pago` | Listar Metodos Pago | sesión válida |
| GET | `/api/v1/mi/donaciones` | Mis donaciones (portal del donante) | portal:donante |
| GET | `/api/v1/mi/entregas` | Mis entregas asignadas (portal del voluntario) | portal:voluntario |
| GET | `/api/v1/necesidades` | Cola de atención (urgencia y antigüedad) | necesidades:leer |
| POST | `/api/v1/necesidades` | Crear Necesidad | necesidades:escribir |
| PUT | `/api/v1/necesidades/{id_necesidad}` | Actualizar Necesidad | necesidades:escribir |
| POST | `/api/v1/necesidades/{id_necesidad}/estado` | Estado Necesidad | necesidades:escribir |
| GET | `/api/v1/public/campanas` | Publico Campanas | público |
| GET | `/api/v1/public/resumen` | Publico Resumen | público |
| GET | `/api/v1/reportes/top-donantes` | Reporte interno con nombres de donantes | reportes:leer |
| GET | `/api/v1/roles` | Listar Roles | sesión válida |
| GET | `/api/v1/roles/matriz` | Matriz de permisos por rol | sesión válida |
| GET | `/api/v1/sectores` | Listar Sectores | sesión válida |
| POST | `/api/v1/sectores` | Crear Sector | sesión válida |
| PUT | `/api/v1/sectores/{id_sector}` | Actualizar Sector | sesión válida |
| PATCH | `/api/v1/sectores/{id_sector}/estado` | Estado Sector | sesión válida |
| GET | `/api/v1/usuarios` | Listar Usuarios | sesión válida |
| POST | `/api/v1/usuarios` | Crear Usuario | sesión válida |
| GET | `/api/v1/usuarios/{id_usuario}` | Obtener Usuario | sesión válida |
| PUT | `/api/v1/usuarios/{id_usuario}` | Actualizar Usuario | sesión válida |
| PATCH | `/api/v1/usuarios/{id_usuario}/estado` | Estado Usuario | sesión válida |
| POST | `/api/v1/usuarios/{id_usuario}/password` | Restablecer contraseña (cierra sus sesiones) | sesión válida |
| GET | `/api/v1/voluntarios` | Listar Voluntarios | voluntarios:leer |
| POST | `/api/v1/voluntarios` | Crear Voluntario | voluntarios:escribir |
| GET | `/api/v1/voluntarios/{id_voluntario}` | Obtener Voluntario | voluntarios:leer |
| PUT | `/api/v1/voluntarios/{id_voluntario}` | Actualizar Voluntario | voluntarios:escribir |
| PATCH | `/api/v1/voluntarios/{id_voluntario}/estado` | Estado Voluntario | voluntarios:escribir |
| GET | `/health` | Liveness: el proceso responde | público |
| GET | `/health/db` | Readiness: la base de datos responde | público |

## Convenciones

- **Autenticación:** `Authorization: Bearer <JWT>` (obtenido en `POST /auth/login`). El token se revalida contra la base de datos en cada petición (usuario activo y versión de token); cambiar la contraseña, cambiar el rol o desactivar la cuenta lo invalida al instante.
- **Listados:** `?pagina=1&tamano=25&q=texto&orden=…&desc=true` + filtros propios. Respuesta `{ items, total, pagina, tamano }`. `tamano` máximo 100. Los filtros desconocidos se **rechazan** (422) en lugar de ignorarse.
- **Errores:** siempre `{ "error": { "codigo", "mensaje", "detalles": [{campo, mensaje}] } }`.

| HTTP | `codigo` | Cuándo |
|---|---|---|
| 401 | `NO_AUTENTICADO`, `SESION_EXPIRADA`, `SESION_REVOCADA` | Sin token, token vencido o revocado |
| 403 | `PERMISO_INSUFICIENTE`, `CAMBIO_PASSWORD_REQUERIDO` | El rol no tiene el permiso; clave temporal pendiente |
| 404 | `NO_ENCONTRADO` | No existe (también cuando el dato no es del usuario: no se revela su existencia) |
| 409 | `CONFLICTO`, `CONCURRENCIA` | Duplicado exacto (correo, n.º de operación…) o dos usuarios a la vez |
| 409 | `REQUIERE_CONFIRMACION` | Posible duplicado: reenviar con `confirmar_duplicado` / `confirmar_repetida` = `true` |
| 422 | `VALIDACION`, `REGLA_DE_NEGOCIO` | Datos inválidos; regla incumplida (campaña inactiva, saldo insuficiente…) |
| 423 | `CUENTA_BLOQUEADA` | 5 intentos fallidos: bloqueo de 15 minutos |
| 503 | `BASE_DE_DATOS_NO_DISPONIBLE` | SQL Server no responde |

## Exportaciones
`GET /donaciones/export` y `GET /entregas/export` devuelven CSV UTF-8 con BOM, neutralizan la inyección de fórmulas (`=`, `+`, `-`, `@`) y **quedan registradas en la auditoría**.

# Revisión de Red Solidaria contra la rúbrica — Unidad 4, Semana 15

**Base de evaluación:** PDF de la consigna, páginas 1–3. Esta revisión diferencia evidencia visible en el código/documentación de pruebas que todavía necesitan ejecutarse en un entorno real.

## Dictamen ejecutivo

La estructura del proyecto es sólida y fácil de defender: Angular 22 → API FastAPI por capas → SQL Server mediante procedimientos almacenados. La principal brecha para el nivel Excelente no es reorganizar toda la aplicación; es completar y demostrar el ciclo de integración, pruebas de motor, gestión GitHub, CI y despliegue público.

| Criterio Excelente (4) | Evidencia encontrada | Estado de auditoría | Trabajo para cerrar |
|---|---|---|---|
| Frontend funcional, responsive, Bootstrap, validaciones y modularización | Angular 22 standalone; rutas diferidas; `core/`, `shared/`, `layout/`, `features/`; Bootstrap/Bootswatch; Signal Forms; servicios HTTP, guards, interceptors y pruebas documentadas | **Arquitectura: cumple. Ejecución actual: no verificada aquí.** | Ejecutar `npm ci`, `npm test -- --watch=false`, `npm run build`; probar login, formularios, roles, tablas y viewport móvil en navegador real. |
| Backend organizado, rutas, validaciones y lógica de negocio | FastAPI; `apis/v1`, `schemas`, `services`, `repositories`, `db`, `core`; Pydantic; autorización por permisos; reglas de negocio en servicios/procedimientos | **Cumple en estructura; falta repetir la suite en CI.** | Ejecutar `pytest`; demostrar al menos un GET, POST y PUT desde Swagger o frontend. No se identificó una API externa que sea necesaria para el flujo central; no inventar una integración externa solo para marcar la rúbrica. |
| BD relacional, 3FN, procedimientos/funciones | DDL con 18 tablas, 27 claves foráneas, 4 vistas y 53 procedimientos; catálogos y tablas puente; `CHECK`, `UNIQUE`, índices y bitácora; cuenta de aplicación con `GRANT EXECUTE` y `DENY SELECT/INSERT/UPDATE/DELETE` | **Diseño coherente con 3FN y procedimientos evidenciados; falta ejecución en SQL Server.** | Ejecutar `database.ps1 -Action all` y `check` en una instancia SQL Server compatible; validar consultas, transacciones, triggers y permisos reales. Documentar dependencias funcionales para justificar formalmente 3FN. |
| Integración, despliegue, ramas, commits, PR y GitHub Actions | Proxy de desarrollo `/api` → `localhost:8000`; API en `/api/v1`; `.gitignore`; no se entregó `.git`/historial, workflow, Dockerfile ni configuración de host | **No cumple todavía el componente CI/despliegue verificable.** | Crear repositorio, tres ramas/PR reales, workflow CI, publicar frontend+API+BD y comprobar URL HTTPS/health. |
| Sustentación técnica | `ARQUITECTURA.md`, `API.md`, `MODELO_DATOS.md`, `DECISIONES.md`, `PRUEBAS.md` | **Hay material; el dominio oral depende de practicar y ejecutar la demo.** | Preparar respuestas cortas, recorrer una operación completa y explicar límites de las pruebas sin exagerar resultados. |

## Qué se verificó en este análisis

- Se inspeccionaron los archivos del ZIP, el árbol de Angular/FastAPI, configuración CORS, autenticación, dependencias FastAPI, ejecutor SQL, repositorios, procedimientos, scripts SQL, documentación y CSV.
- `python -m compileall -q backend/app backend/scripts backend/tests` terminó correctamente: esto valida sintaxis Python, no ejecución de la aplicación.
- Se ejecutó `scripts.seed.sembrar()` contra el esquema SQLite de pruebas con los CSV sintéticos: importó las filas, respetó referencias/fechas, comprobó que los gastos aprobados no exceden los fondos y la segunda ejecución fue idempotente. Esto **no sustituye** la ejecución en SQL Server.
- El proyecto documenta 402 pruebas backend y 36 frontend, pero **no se deben presentar como repetidas en esta revisión**. `pytest --collect-only` no pudo completarse aquí porque faltaba `pwdlib`; no hubo acceso a paquetes de Internet para instalarlo.
- `npm ci` no pudo terminar en este entorno por falta de conectividad y la versión local de Node era inferior al mínimo de Angular 22 declarado por el proyecto. No se ejecutaron `ng test` ni `ng build` en esta revisión.
- No había instancia de SQL Server, Docker ni PowerShell en el entorno de auditoría. Por tanto, no se ejecutó T-SQL en el motor ni se comprobó el despliegue.

## Riesgos y observaciones técnicas

1. **CORS y URL de API:** los servicios Angular usan rutas absolutas relativas al mismo origen, como `/api/v1/campanas`. El proxy de `frontend/proxy.conf.json` solo resuelve desarrollo local. En producción se debe servir Angular y enrutar `/api/` y `/health` al backend mediante un proxy inverso, o introducir una configuración de URL base. La primera opción exige menos cambios.
2. **CORS actual:** `CORS_ORIGINS` por defecto es `http://localhost:4200`. Si frontend y backend se publican en orígenes distintos, hay que agregar el origen HTTPS exacto del frontend. Nunca usar `*` en producción. Si ambos quedan bajo el mismo origen, el navegador no necesita una política CORS para esa llamada.
3. **Certificado SQL:** `APP_ENV=production` rechaza `DB_TRUST_SERVER_CERTIFICATE=yes`. El servidor de base de datos debe presentar un certificado TLS confiable para el cliente ODBC; no se debe eludir esta validación para “hacer que conecte”.
4. **Datos y capturas:** el ZIP original incluía nombres y correos personales en CSV, además de capturas de un reporte interno con nombres. La copia preparada para publicación reemplaza nombres, correos, sectores, fechas y montos por fixtures demostrativos sintéticos, mantiene IDs/relaciones y excluye `docs/capturas/` de Git. Verifique igualmente que no se suban exportaciones reales ni archivos `.env`.
5. **No borrar registros operativos:** el sistema prioriza trazabilidad. Para campañas, donantes y catálogos se usan transiciones de estado o desactivación, no borrado físico. La aplicación tiene denegado el acceso SQL directo de `SELECT`, `INSERT`, `UPDATE` y `DELETE` y ejecuta procedimientos autorizados.
6. **3FN:** la separación de `categoria_ayuda`, `metodo_pago`, `sector`, `rol`, `permiso` y `rol_permiso`, y la relación separada entre campañas, donaciones, gastos y entregas, es consistente con un diseño en 3FN. Para defenderlo formalmente, explicar dependencias funcionales y mostrar que atributos no clave dependen de la clave, de toda la clave y de nada más que la clave; no afirmar una demostración matemática que no está documentada.

## Prioridad recomendada

### P0 — antes de subir a GitHub
- Mantener la copia con fixtures sintéticos; comprobar que `git status --ignored` no revela `.env`, capturas ni exportaciones reales.
- Crear el repositorio remoto vacío y confirmar que la rama principal será `main`.
- Añadir el workflow `.github/workflows/ci.yml` de esta entrega.

### P1 — antes de dar por Excelente
- Ejecutar en Windows los scripts reales: `setup.ps1`, `database.ps1 -Action all`, `database.ps1 -Action check` y `run.ps1 -Test`.
- Ejecutar la suite frontend y la compilación de producción con Node 22.22.3 o la versión compatible vigente indicada por Angular.
- Ejecutar las pruebas SQL en SQL Server real, especialmente permisos de `redsolidaria_app`, transacciones y bitácora.
- Abrir y fusionar los PR de backend/BD, frontend y CI/documentación, con revisiones reales.
- Desplegar y comprobar desde una red externa `/`, `/health` y `/api/v1` a través del mismo dominio HTTPS.

### P2 — mejora de calidad
- Automatizar E2E de login/roles y formularios; añadir revisión de accesibilidad y pruebas responsive.
- Añadir un diagrama visual de despliegue y una tabla de dependencias funcionales para 3FN.
- Configurar copias de seguridad, retención, logs y rotación de secretos en el host.

## Criterio de aceptación para el día de la sustentación

No declarar “todo funciona” hasta mostrar: (1) URL pública con HTTPS, (2) login y al menos dos roles, (3) una operación de lectura, alta y edición, (4) cambio de estado/desactivación, (5) resultado verde de GitHub Actions y (6) conexión real de la API con SQL Server. Mantener a mano `PRUEBAS.md` para explicar con transparencia qué comprobaciones son unitarias/estáticas y cuáles se hicieron contra el motor.

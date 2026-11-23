# Auditoría de la base de datos original

> **Alcance.** Esta auditoría describe la revisión del conjunto de datos de origen entregado y su esquema inicial. Para publicación, `database/datos/` se reemplazó por fixtures demostrativos sintéticos que conservan identificadores y relaciones; por tanto, las observaciones cuantitativas de la sección 3 describen el conjunto de origen auditado, no los valores sintéticos actuales. Las capturas con datos identificables se excluyen del repositorio.
>
> **Alcance original.** Se revisaron `01_esquema.sql`, `02_cargar_datos.sql`, `03_consultas_impacto.sql`, el diagrama lógico y los 7 CSV (≈ 500 filas). Las definiciones del esquema inicial se conservan en `database/legacy/`; los CSV de origen no se publican. La carpeta `database/datos/` contiene fixtures sintéticos que emulan la estructura y las relaciones del conjunto auditado; la versión corregida está en `database/01…10_*.sql`.
> **Qué sí y qué no se verificó.** El modelo y los 53 procedimientos nuevos se validaron con la gramática T-SQL de *sqlfluff* (148 lotes), un verificador propio (variables no declaradas, `EXEC` con expresiones, balance de bloques, columnas inexistentes) y pruebas que cargan los datos contra las restricciones del esquema (traducido a SQLite). **No se ejecutaron contra una instancia de SQL Server** (no había una disponible): ejecute `.\database.ps1 -Action init` y `check` en su equipo; ver [PRUEBAS.md](PRUEBAS.md) para los riesgos residuales.

## 1. Resumen ejecutivo

El modelo original es **correcto como ejercicio de normalización** (3FN, claves foráneas, `CHECK` básicos, datos limpios) pero **no es ejecutable en SQL Server**, **no es seguro de re-ejecutar** y le faltan las garantías que un profesor o un revisor de bases de datos buscan primero: autoincremento, índices en todas las FK, estados, trazabilidad y reglas entre tablas. Se encontraron **5 hallazgos de severidad alta, 6 media y 5 baja** en la estructura, y 6 observaciones sobre los datos.

## 2. Hallazgos de estructura

| # | Sev. | Hallazgo | Evidencia | Corrección en v2 |
|---|---|---|---|---|
| E1 | **Alta** | **No corre en SQL Server.** La cabecera dice «SQL estándar (PostgreSQL, MySQL, SQLite)», pero `02_cargar_datos.sql` usa `\copy` (meta-comando de `psql`, no SQL) y `03_consultas_impacto.sql` usa `LIMIT` (en T-SQL es `TOP` / `OFFSET … FETCH`). | `02`, `03` | Port completo a T-SQL; la carga la hace `scripts/seed.py` (conserva IDs con `IDENTITY_INSERT`). |
| E2 | **Alta** | **Script destructivo.** `01_esquema.sql` ejecuta `DROP TABLE IF EXISTS` de todas las tablas: re-ejecutarlo borra los datos. | `01` | Scripts idempotentes (`IF OBJECT_ID … IS NULL`, `CREATE OR ALTER`), tabla `schema_migracion`; una prueba **prohíbe** `DROP`/`TRUNCATE` en `database/`. |
| E3 | **Alta** | **Claves sin autoincremento.** Los `INT PRIMARY KEY` se asignan a mano: dos usuarios a la vez obtienen el mismo ID, y una aplicación web no puede insertar. | todas las tablas | `INT IDENTITY(1,1)`. |
| E4 | **Alta** | **`beneficiario.sector` es texto libre.** «Villa Norte», «villa norte » y «V. Norte» serían sectores distintos; viola el espíritu de la 3FN que el propio diagrama declara. | `beneficiario` | Catálogo `sector` + FK `id_sector`. |
| E5 | **Alta** | **FK sin índice: `entrega.id_voluntario`** (la única de 6). En SQL Server una FK *no* crea índice: filtrar por voluntario escanea toda la tabla y los `UPDATE/DELETE` del padre bloquean. | `entrega` | Índice por **cada** FK; la prueba `test_toda_clave_foranea_tiene_indice` lo exige (y detectó dos omisiones de mi propia v2: `gasto.aprobado_por`, `necesidad.id_usuario_registra`). |
| E6 | Media | **Sin integridad temporal entre tablas.** Nada impide una donación fuera del periodo de su campaña, una entrega a una campaña cerrada o a un hogar inactivo. | `donacion`, `entrega` | Reglas en los procedimientos (`THROW 50422`) + estados de campaña. |
| E7 | Media | **Regla implícita sin proteger.** Las 104 entregas son **104 pares (campaña, hogar) únicos**: el dato asume «un apoyo por hogar y campaña», pero nada lo garantiza. | CSV `entrega` | Índice único filtrado por día + advertencia con confirmación explícita (`REQUIERE_CONFIRMACION`) si el hogar ya recibió en esa campaña. |
| E8 | Media | **`campana.nombre UNIQUE` impide repetir una campaña anual** («Canasta Solidaria» 2027). | `campana` | `UNIQUE (nombre, anio)` con columna calculada persistida. |
| E9 | Media | **Sin ciclo de vida ni borrado lógico.** La campaña «activa/finalizada» solo se deduce de fechas; borrar una fila rompe el historial o la FK. | todas | `estado` con `CHECK` y transiciones válidas; `activo` en catálogos y personas; nada se borra (se anula con motivo). |
| E10 | Media | **Donación sin estado ni referencia.** «Tarjeta» no prueba que el dinero llegó; no se puede evitar registrar dos veces el mismo voucher. | `donacion` | `estado` (Pendiente → Confirmada/Rechazada/Anulada), `referencia` con índice único filtrado; **solo lo confirmado cuenta** en los totales. |
| E11 | Media | **Método de pago como `CHECK` de 3 literales:** agregar «Yape» exige alterar la restricción. | `donacion` | Catálogo `metodo_pago` (+ `requiere_referencia`). |
| E12 | Media | **Dinero sin moneda;** `DECIMAL(10,2)` limita a 99 999 999,99. | `donacion`, `campana` | `moneda` por campaña (no se mezclan monedas), `DECIMAL(12,2)`. |
| E13 | Baja | Correos sin validación de formato; `integrantes_hogar` y `cantidad` sin cota superior. | `donante`, `voluntario`, `beneficiario`, `entrega` | `CHECK` de formato; hogar 1–30; cantidad 1–1000; monto ≤ 1 000 000. |
| E14 | Baja | `VARCHAR` para nombres con tildes y ñ (depende de la página de códigos); búsquedas sensibles a tildes. | todas | `NVARCHAR` + collation de base `Latin1_General_100_CI_AI` (buscar «Hector» encuentra «Héctor»). |
| E15 | Baja | Sin columnas de trazabilidad (`creado_en`, `actualizado_en`) ni bitácora. | todas | Marcas UTC en cada tabla + `auditoria_evento` **de solo inserción** (trigger `INSTEAD OF UPDATE, DELETE`). |
| E16 | Baja | Acciones referenciales implícitas (`NO ACTION`) sin documentar. | FK | Se mantienen (la app no borra) y se documentan en [MODELO_DATOS.md](MODELO_DATOS.md). |
| E17 | Info | **No hay usuarios, roles ni permisos;** los datos personales de hogares no registran consentimiento (Ley 29733). | — | RBAC de 7 roles / 36 permisos; `consentimiento_datos` **sin presumirlo**; cuenta de aplicación con solo `EXECUTE`. |

### Sobre las consultas de `03_consultas_impacto.sql`
- **Consulta 2 (top 5 de donantes):** publica nombres de donantes. Se conserva como reporte *interno* (`reportes:leer`); el portal público solo muestra agregados.
- **Consulta 3 (alcance por sector):** suma `integrantes_hogar` y la rotula «personas»: es una *estimación*, no un conteo de personas únicas. La interfaz lo indica.
- **Consulta 4 (unidades por categoría):** suma magnitudes que no son comparables (Merienda: 8,6 raciones por entrega; Botiquín: 1,0 botiquín). `cantidad` es «unidades genéricas»; se agregó `detalle` y se documenta la ruta para un catálogo de artículos ([ALCANCE_FUNCIONAL.md](ALCANCE_FUNCIONAL.md)).
- Las consultas que unen donaciones con entregas multiplicarían filas; en v2 cada hecho se agrega en su propio `OUTER APPLY` (vistas `vw_*`).

## 3. Hallazgos en los datos (verificados con script)

| # | Observación | Detalle |
|---|---|---|
| D1 | **Entrega #96 anterior a los fondos de su campaña** | Campaña *Merienda Escolar*: entrega el 2026-09-12, primera donación el 2026-09-14; además es el valor máximo de `cantidad` (11) para un hogar de 3 integrantes. Se **conserva** (no se corrige sin la fuente) y se señala para revisión. |
| D2 | 10 entregas con `cantidad` > integrantes del hogar | Probable efecto de unidades heterogéneas (raciones). No es un error; es la evidencia de E-consulta 4. |
| D3 | Metas | *Abrigo* 126,9 % (sobrefinanciada: no hay política para excedentes), *Botiquín* exactamente 100,0 %, *Útiles* 99,8 %, *Higiene* 58,0 %, *Merienda* 40,0 %. |
| D4 | Cobertura desigual | Hogares atendidos por campaña: 24, 20, 22, 18, **12** (Higiene) y **8** de 30 (Merienda, en curso). Alimenta la «cola de atención». |
| D5 | Ventanas de fecha | **0** donaciones o entregas fuera del periodo de su campaña: los datos cumplen las reglas que v2 ahora *impone*. |
| D6 | Sin consentimiento | Ningún hogar tiene constancia de consentimiento: los 30 quedan «pendiente», visible en el panel (no se inventa). |

## 4. Qué se conservó (decisiones correctas del original)
Normalización a 3FN, nombres en `snake_case`, `CHECK` de dominio, índices por FK (5 de 6), unicidad de correos, y la separación `donante`/`voluntario`/`beneficiario`. Las 7 tablas, sus columnas y **todos sus identificadores** se mantienen; v2 las *extiende*.

## 5. Migración original → v2

| Original | v2 | Cambios |
|---|---|---|
| `categoria_ayuda` | igual | + `activo`, marcas de tiempo |
| `donante`, `voluntario` | igual | + `activo`; `NVARCHAR`; `CHECK` de correo |
| `beneficiario` | + `sector`, `id_sector` | `sector` texto → FK; + consentimiento; hogar 1–30 |
| `campana` | igual | + `estado`, `moneda`, metas social/física, descripción, responsable; único por (nombre, año) |
| `donacion` | + `metodo_pago` | `metodo_pago` texto → FK; + `estado`, `referencia`, confirmación |
| `entrega` | igual | + `estado`, `detalle`, `id_necesidad`, índice por voluntario |
| — | **nuevas** | `rol`, `permiso`, `rol_permiso`, `usuario`, `auditoria_evento`, `necesidad`, `gasto`, `retroalimentacion`, `schema_migracion` |

Los datos se cargan con `scripts/seed.py` **conservando IDs**. Las donaciones históricas entran como `Confirmada` (el sistema anterior no tenía estados) y su observación lo dice: *«Migrada del sistema anterior (se asume confirmada: verificar con el comprobante)»*. Verificación: los totales importados (120 donaciones = S/ 9 895,00; 104 entregas = 276 unidades) coinciden con los CSV (prueba automática).

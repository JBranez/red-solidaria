# Decisiones técnicas

| # | Decisión | Motivo / alternativa descartada |
|---|---|---|
| 1 | **Procedimientos almacenados** como única vía de acceso | Patrón del proyecto base. Permite que la cuenta de aplicación **no pueda leer tablas**. Descartado: ORM (exigiría permisos directos sobre tablas). |
| 2 | Cada procedimiento es la unidad transaccional; conexión con `autocommit=True` | Evita transacciones anidadas con el driver; cada `EXEC` es atómico. |
| 3 | `usp_*_listar` con `@id` opcional sirve también de «obtener» | Una sola lista de columnas por entidad (menos duplicación): 53 procedimientos en vez de ~80. |
| 4 | Códigos de error `THROW 50404/50409/50410/50422/50403` | Contrato simple entre SQL y Python; el mensaje es apto para el usuario. |
| 5 | Estados como `VARCHAR` + `CHECK` con valores **ASCII** (`Critica`, `En atencion`) | Sin problemas de codificación; la interfaz los traduce. Una prueba verifica que `CHECK` = `Literal` de Pydantic. |
| 6 | `COUNT(*) OVER()` como `total_filas` | Una sola consulta por página; el ejecutor lo separa. Página fuera de rango → sondeo para el total real. |
| 7 | **Duplicados: advertir, no bloquear** (`REQUIERE_CONFIRMACION`) | Dos hogares pueden llamarse igual. El humano decide; la duplicidad *exacta* sí se bloquea. |
| 8 | **Consentimiento: advertir, no bloquear entregas** | Negar ayuda a una familia por un trámite pendiente es peor que el riesgo. Queda visible en el panel. |
| 9 | Donaciones históricas importadas como `Confirmada` con nota | El sistema anterior no tenía estados. Se evita ocultar S/ 9 895 reales; se documenta el supuesto. |
| 10 | Un voluntario **no** crea entregas: confirma las asignadas | Mínimo privilegio: crear exigiría ver el padrón completo de hogares. |
| 11 | JWT en `sessionStorage`, revocable por `token_version` | Sin cookies (no hay CSRF). Riesgo conocido: legible por JS ante un XSS; se mitiga con Angular (escapado por defecto), expiración de 60 min y revocación. Alternativa para producción: cookie `HttpOnly` + CSRF. |
| 12 | Tema **Bootswatch Zephyr** (Bootstrap 5.3.8 precompilado) | Es un reemplazo 1:1 del CSS de Bootstrap (cumple «solo CSS»). Se le quita el `@import` a Google Fonts en `postinstall` y se autoaloja Inter: sin peticiones a terceros. En Zephyr `secondary` es **blanco**; se redefine como gris. |
| 13 | Gráficos propios en SVG/CSS, sin librería | Cero dependencias nuevas, accesibles (`role="img"`, `aria-label`), 0 kB extra. |
| 14 | Selectores de hogar/donante/voluntario cargan hasta 100 registros | Suficiente para la escala del proyecto; con miles se reemplaza por búsqueda incremental (el endpoint ya filtra por `q`). |
| 15 | `sqlfluff` y `httpx` como dependencias **solo de desarrollo** | `sqlfluff` valida la gramática T-SQL sin servidor; se omite si no está instalado. `httpx` → `starlette` sugiere `httpx2`; se deja `httpx` (funciona) y se silencia el aviso. |
| 16 | `constraints.txt` con las versiones exactas probadas | Reproducibilidad sin congelar rangos de `requirements.txt`. |
| 17 | `setup.ps1` **no guarda** la contraseña de `sa`; por defecto se usa autenticación de Windows | Una credencial administrativa en disco es un riesgo innecesario. |
| 18 | Datos de demostración claramente separados y desactivados en producción | `APP_ENV=production` no crea cuentas demo y fuerza el cambio de clave del administrador. |

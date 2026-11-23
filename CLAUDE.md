# Guía para asistentes de IA (Red Solidaria)

## Arquitectura (no romper)
- **Todo acceso a datos = procedimientos `dbo.usp_*`** ejecutados SOLO por `backend/app/db/executor.py`. Prohibido SQL embebido, ORM o SQL dinámico (rompe la cadena de propietarios: la cuenta de aplicación solo tiene `EXECUTE`).
- Capas: `apis` (HTTP) → `services` (reglas + autorización por dato) → `repositories` (1 método = 1 procedimiento, **argumentos nombrados explícitos**, sin `**kwargs`) → procedimiento.
- Errores de negocio: `THROW 50404/50409/50410/50422/50403` en SQL → excepciones de `core/errors.py`. En EXEC no se pasan expresiones (usar variable).
- Permisos: fuente de verdad `backend/app/core/permissions.py`; `database/10_reference_data.sql` debe coincidir (lo verifica `test_sql_estatico`).
- Frontend: standalone + Signals + Signal Forms (`[formField]`, `form()`, `enviar()` de `core/util/form-utils.ts`). Sin `maxlength` en elementos con `[formField]`: usar `maxLength()` en el esquema. Sin localStorage; token en sessionStorage. Sin JS de Bootstrap.
- Tema: Bootswatch Zephyr genera `src/theme/zephyr.css` (`postinstall`); `secondary` está redefinido a gris en `styles.scss` (en Zephyr es blanco).

## Comandos
```powershell
.\setup.ps1 ; .\run.ps1 ; .\run.ps1 -Test ; .\database.ps1 -Action all|init|seed|check
cd backend ; .\.venv\Scripts\python -m pytest -q        # 402 pruebas, sin SQL Server
cd frontend ; npm test -- --watch=false ; npx ng build  # 36 pruebas
```

## Al cambiar la base de datos
1. Editar `database/NN_*.sql` (idempotente: `CREATE OR ALTER`, `IF NOT EXISTS`; nunca `DROP`).
2. Actualizar repositorio + esquema Pydantic + modelo TS.
3. Correr `pytest`: el contrato SQL↔Python, la prueba de índices por FK y el verificador de procedimientos fallan si algo no cuadra.
4. Registrar la versión en `schema_migracion`.

## Reglas de negocio que no deben relajarse
Solo lo **confirmado** suma · quien registra un gasto no lo aprueba · nada se borra (se anula con motivo) · el portal público solo agrega (celdas < 3 suprimidas) · consentimiento y duplicados se advierten, no se bloquean · exportaciones auditadas.

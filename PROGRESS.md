# Progreso Red Solidaria

## Day 1 ? 2026-11-22
- PR #1 esquema relacional y procedimientos fusionado.
- PR #2 backend FastAPI por capas fusionado.

## Day 2 ? 2026-11-23
- Frontend Angular, Docker Compose, proxy TLS y documentacion de despliegue publicados en PR #3 (`87a792c`).
- Azure VM y red creadas; Docker Engine/Compose instalados en Ubuntu.
- Sitio desplegado en `https://redsolidaria-jbranez.chilecentral.cloudapp.azure.com`.
- Suite backend local: 402 pruebas pasaron. CI de PR #3 y correcciones posteriores paso.
- Correccion del permiso SQL de cuenta app publicada en PR #4 y PR #6 (`e2ecc2f`).

## Estado comprobado
- Angular/FastAPI healthy; SQL Server activo con volumen persistente.
- HTTPS, `/health/db`, login y puerto SQL no publico verificados.
- La contrasena admin fue generada en VM y entregada directamente al propietario; secretos residen solo en `.env` remoto.

## Day 3
- Documentacion de operacion y sustentacion revisada y completada en esta rama.
- Fecha del dia 3 no se marca como completada en el registro hasta su fecha planificada (2026-11-24).

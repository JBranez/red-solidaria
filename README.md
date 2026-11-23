# Red Solidaria

Plataforma web para gestionar **donaciones, campañas, hogares beneficiarios, voluntarios y entregas** de ayuda social: de quien dona a quien recibe, con trazabilidad y rendición de cuentas.

> **Datos de ejemplo:** los CSV incluidos son fixtures sintéticos para demostración y pruebas. No publiques exportaciones reales ni capturas con datos personales.

## Lo esencial
- **Base de datos auditada y mejorada** (SQL Server): 18 tablas, 53 procedimientos, 4 vistas. → [AUDITORIA_BD.md](docs/AUDITORIA_BD.md)
- **Backend** FastAPI + pyodbc: solo procedimientos almacenados, cuenta de aplicación con **mínimo privilegio**, JWT revocable, RBAC de 36 permisos.
- **Frontend** Angular 22 (Signals, **Signal Forms**), Bootstrap 5.3.8 con la piel *Zephyr*; gráficos SVG propios.
- **Portal público de transparencia** (solo agregados, sectores pequeños suprimidos) y portales de donante y voluntario.
- **402 + 36 pruebas** documentadas. → [PRUEBAS.md](docs/PRUEBAS.md) (incluye *lo que no se pudo verificar*).
- **GitHub Actions:** workflow de CI para backend, frontend y build en cada Pull Request a `main` (`.github/workflows/ci.yml`).

## Inicio rápido (Windows)
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1      # .env con secretos aleatorios, dependencias, base de datos y datos
.\run.ps1        # http://localhost:4200  ·  API/docs: http://localhost:8000/docs
```
Usuario `admin`; la contraseña está en `.env` (`SEED_ADMIN_PASSWORD`). Requisitos y solución de problemas: [INSTALACION.md](docs/INSTALACION.md).

## Estructura
```
database/   01…10_*.sql (esquema, índices, vistas, procedimientos, permisos, referencia) · datos/ (fixtures sintéticos CSV) · legacy/ (modelo inicial de referencia; no necesario para ejecutar la versión actual)
backend/    app/{apis,schemas,services,repositories,db,core} · scripts/ (init_db, seed, check_db) · tests/
frontend/   src/app/{core,shared,layout,features}
docs/       AUDITORIA_BD · MODELO_DATOS · ARQUITECTURA · API · DECISIONES · ALCANCE_FUNCIONAL · INSTALACION · PRUEBAS · CREDITOS
setup.ps1 · run.ps1 · database.ps1 · scripts/Publish-RedSolidaria.ps1 · scripts/Merge-RedSolidariaPhase.ps1 · scripts/Deploy-RedSolidaria.ps1 · .github/workflows/ci.yml · .github/workflows/deploy.yml
```

## Despliegue con Docker

La solución incluye `docker-compose.yml`: SQL Server 2022, inicialización automática, FastAPI, Angular/Nginx y Caddy con HTTPS. Para desplegar en un VPS público, sigue [DESPLIEGUE_DOCKER.md](docs/DESPLIEGUE_DOCKER.md) y ejecuta `scripts/Publish-RedSolidaria.ps1`, `scripts/Merge-RedSolidariaPhase.ps1` y `scripts/Deploy-RedSolidaria.ps1` desde PowerShell. No se publica el puerto SQL a Internet.

## Arquitectura y validación
- [Arquitectura](docs/ARQUITECTURA.md): responsabilidades de Angular, FastAPI y SQL Server.
- [Revisión de rúbrica](docs/REVISION_RUBRICA.md): evidencias, brechas y plan de cierre.
- [Despliegue](docs/DESPLIEGUE.md): topología y pasos de publicación.
- [Sustentación](docs/SUSTENTACION.md): respuestas para la defensa técnica.

## Qué mirar primero
1. [docs/AUDITORIA_BD.md](docs/AUDITORIA_BD.md): 17 hallazgos de estructura y 6 de datos, con su corrección.
2. [docs/MODELO_DATOS.md](docs/MODELO_DATOS.md): diagrama, reglas que impone el motor y ciclos de vida.
3. [docs/ALCANCE_FUNCIONAL.md](docs/ALCANCE_FUNCIONAL.md): qué se implementó del análisis funcional, indicadores y matriz de permisos.

## Límites honestos
Los procedimientos SQL se validaron por sintaxis, coherencia y contrato, **pero no se ejecutaron en una instancia de SQL Server** (ver [PRUEBAS.md](docs/PRUEBAS.md)); los scripts `.ps1` no se corrieron en Windows. Inventario/artículos, presupuesto por partidas, notificaciones por correo y MFA están en el *roadmap*, no implementados.

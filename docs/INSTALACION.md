# Instalación en Windows

## Requisitos
| Componente | Versión | Notas |
|---|---|---|
| Windows | 10 / 11 | PowerShell 5.1 o 7 |
| SQL Server | 2019 o superior (Developer o Express) | **TCP/IP habilitado en el puerto 1433** (Administrador de configuración de SQL Server → Protocolos) |
| ODBC Driver 18 for SQL Server | 18.x | https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server |
| Python | 3.12+ | Marcar «Add python.exe to PATH» |
| Node.js | 22.22.3+ (o 24.15+) | Requisito de Angular 22 |

## Pasos
```powershell
cd red-solidaria
Set-ExecutionPolicy -Scope Process Bypass      # solo para esta ventana
.\setup.ps1        # .env con secretos aleatorios, entorno virtual, npm, base de datos y datos
.\run.ps1          # API en :8000 y aplicación en :4200 (abre el navegador)
```
- `setup.ps1` usa **autenticación de Windows** para crear la base (su usuario debe ser `sysadmin`). Con SQL Server en modo mixto: `.\database.ps1 -Action init -SqlAuth` pide la contraseña de `sa` **sin guardarla**.
- `.\setup.ps1 -SkipDatabase` prepara todo salvo la base; después: `.\database.ps1 -Action all`.
- `.\setup.ps1 -NoDemo` importa solo los datos originales y el administrador.
- Credenciales: usuario `admin`; contraseña en `.env` → `SEED_ADMIN_PASSWORD`. Cuentas de demostración (misma clave `SEED_DEMO_PASSWORD`): `coordinacion`, `finanzas`, `trabajo.social`, `auditoria`, `voluntario`, `donante`.
- Comprobar la conexión y el mínimo privilegio: `.\database.ps1 -Action check`.
- Pruebas: `.\run.ps1 -Test`.

## Problemas frecuentes
| Síntoma | Causa probable |
|---|---|
| `No se pudo conectar a SQL Server…` | Servicio detenido, TCP/IP deshabilitado, o puerto distinto (ajuste `DB_PORT` en `.env`) |
| `Can't open lib 'ODBC Driver 18…'` | Falta el driver ODBC 18 |
| `certificate verify failed` | En desarrollo `DB_TRUST_SERVER_CERTIFICATE=yes`; en producción instale un certificado confiable |
| `Login failed for user 'redsolidaria_app'` | Se creó el login con otra contraseña: vuelva a ejecutar `.\database.ps1 -Action init` (la rota) |
| Pantalla de login sin cifras a la izquierda | La API no está levantada (el panel lateral lee `/public/resumen`) |
| `CORS` | `CORS_ORIGINS` debe incluir el origen exacto del frontend |

## Producción (lista mínima)
`APP_ENV=production` · certificado confiable y `DB_TRUST_SERVER_CERTIFICATE=no` · HTTPS delante (proxy inverso; `uvicorn --proxy-headers --forwarded-allow-ips=…`) · límite de peticiones por IP en el proxy (el bloqueo de cuenta ya existe) · copias de seguridad cifradas de la base · rotación de `JWT_SECRET_KEY` y `DB_APP_PASSWORD` · `ng build` y servir `frontend/dist` con cabeceras CSP/HSTS.

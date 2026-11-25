kRf74HDzQ3AyyTr14fSqwoftZrEJ6ZpcGBNXGP_NNfvs3_EtaA1!
JOTQr_1hcakxTKzEQiqLoNCFYJO7p7nFNR29w9tifqfOMM8iaA1!


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


## Despliegue Azure for Students

Consulta [docs/DESPLIEGUE_AZURE_FOR_STUDENTS.md](docs/DESPLIEGUE_AZURE_FOR_STUDENTS.md) para el procedimiento completo de PowerShell: iniciar sesión en Azure, obtener los identificadores propios de la suscripción, validar regiones/cuotas, aprovisionar Ubuntu x64, desplegar SQL Server 2022 en Docker y verificar la URL HTTPS.

`SubscriptionId` y `TenantId` son identificadores GUID de tu cuenta, no códigos universales. `scripts/Connect-RedSolidaria-Azure.ps1` selecciona la suscripción habilitada y guarda el registro local. `scripts/Test-RedSolidaria-Azure.ps1` es una comprobación de solo lectura; no crea recursos.

Si `.git/redsolidaria-publish-state.json` falta, `scripts/Repair-RedSolidariaPublishState.ps1` reconstruye el estado de Day1 solo después de comprobar que GitHub tiene PR #1 y #2 fusionadas. No repitas Day1.

## Produccion activa

- URL: https://redsolidaria-jbranez.chilecentral.cloudapp.azure.com
- VM `vm-redsolidaria`, region `chilecentral`, `Standard_B2as_v2` (2 vCPU/8 GiB), Ubuntu 22.04.
- Angular, FastAPI, SQL Server 2022 y Caddy estan activos en Docker Compose. HTTPS validado con TLS publico.
- Verificados desde fuera: frontend 200, `/health/db` 200, login 200 y TCP/1433 cerrado.
- Revisar [PROGRESS.md](../PROGRESS.md), [NEXT_STEPS.md](../NEXT_STEPS.md) y [DESPLIEGUE_AZURE_FOR_STUDENTS.md](DESPLIEGUE_AZURE_FOR_STUDENTS.md) para estado y operacion.

## Conectar desde otra PC a SQL Server por SSMS

En una computadora universitaria nueva, instala Windows OpenSSH Client, Azure CLI y SSMS. Inicia sesion en Azure con la cuenta que administra la VM y ejecuta desde PowerShell, dentro de una copia del repositorio:

```powershell
.\scripts\Connect-RedSolidaria-SSMS.ps1
```

El script:

1. Verifica Azure CLI y SSMS; si Azure CLI no tiene sesion, abre el inicio de sesion interactivo para completar MFA.
2. Obtiene la IP publica actual y limita a esa IP `/32` la regla SSH del NSG y UFW.
3. Crea en esa PC una llave SSH ed25519 local (si no existe) y registra solo la llave publica en Ubuntu mediante Azure Run Command.
4. Comprueba la huella SSH obtenida por Azure antes de aceptar el servidor.
5. Abre el tunel `127.0.0.1:14333` hacia el puerto SQL privado de la VM y lanza SSMS con `RedSolidaria` y `sa` preseleccionados. Escribe la contrasena SQL en SSMS; el script no la solicita ni la almacena.

No compartas ni subas la llave privada `$HOME\.ssh\redsolidaria_university` al repositorio. La llave pública de esa PC permanece autorizada en la VM para futuras conexiones desde esa computadora. Mantén abierto el túnel mientras uses SSMS. El script cambia el origen autorizado de SSH a la IP actual; SQL Server 1433 sigue cerrado al público.

### Inicio desde una computadora nueva (copiar y pegar en PowerShell)

Este bloque descarga el código fuente completo de `main` desde el GitHub público (ZIP, sin historial Git), comprueba las versiones de PowerShell, Azure CLI, Windows OpenSSH y SSMS, y ejecuta el conector. No instala software por su cuenta: si falta una dependencia, muestra el requisito y se detiene. Instálala desde Microsoft/Windows y vuelve a pegar el bloque. Azure CLI puede abrir el inicio de sesión interactivo y solicitar MFA.

```powershell
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw "Se requiere Windows PowerShell 5.1 o posterior."
}

$az = Get-Command az -ErrorAction SilentlyContinue
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$keygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
$ssmsCandidates = @(
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\SSMS.exe",
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 21\Release\Common7\IDE\SSMS.exe",
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
)
$ssms = $ssmsCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

$missing = @()
if (!$az) { $missing += 'Azure CLI (Microsoft Store/winget: Microsoft.AzureCLI)' }
if (!$ssh -or !$keygen) { $missing += 'Windows OpenSSH Client (Optional Features de Windows)' }
if (!$ssms) { $missing += 'SSMS 20 o posterior (instalador oficial de Microsoft)' }
if ($missing.Count) {
    Write-Host 'Faltan estos componentes:' -ForegroundColor Yellow
    $missing | ForEach-Object { Write-Host " - $_" }
    throw 'Instala los componentes indicados y vuelve a ejecutar este bloque.'
}

$azVersionData = (& $az.Source version -o json | ConvertFrom-Json)
$azVersion = [string]$azVersionData.'azure-cli'
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$sshVersion = (& $ssh.Source -V 2>&1 | Select-Object -First 1).ToString()
$ErrorActionPreference = $previousPreference
$ssmsVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($ssms).ProductVersion
Write-Host "PowerShell $($PSVersionTable.PSVersion); Azure CLI $azVersion; $sshVersion; SSMS $ssmsVersion"
if ([version]$azVersion -lt [version]'2.60.0') { throw 'Actualiza Azure CLI a 2.60.0 o posterior.' }
if ($sshVersion -notmatch 'OpenSSH_for_Windows_') { throw 'Se requiere Windows OpenSSH Client.' }
if ([version]($ssmsVersion -replace '[^0-9.].*$','') -lt [version]'20.0') { throw 'Actualiza SSMS a 20 o posterior.' }

$repoUrl = 'https://github.com/JBranez/red-solidaria/archive/refs/heads/main.zip'
$work = Join-Path $env:LOCALAPPDATA ('RedSolidaria-Connect-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$zip = Join-Path $env:TEMP ('red-solidaria-' + [guid]::NewGuid().ToString('N') + '.zip')
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    Invoke-WebRequest -Uri $repoUrl -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
} finally {
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}
$repo = Join-Path $work 'red-solidaria-main'
$connector = Join-Path $repo 'scripts\Connect-RedSolidaria-SSMS.ps1'
if (!(Test-Path -LiteralPath $connector)) { throw 'El ZIP descargado no contiene el conector esperado.' }
Unblock-File -LiteralPath $connector
Write-Host "Código extraído en: $repo"
$localPort = 14333
while (Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue) { $localPort++ }
Write-Host "Usaré el puerto local $localPort para el túnel SSH."
& $connector -LocalPort $localPort
```

El script crea la llave privada solo en el perfil de esa PC (`$HOME\.ssh\redsolidaria_university`), registra en la VM únicamente la parte pública, obtiene la llave de host mediante Azure Run Command, valida su formato y huella localmente, y autoriza SSH desde la IP pública actual `/32`. Mantén abierta la sesión de SSMS y no cierres el proceso del túnel. SSMS pedirá la contraseña SQL; escríbela directamente allí. No publiques la llave privada ni contraseñas.

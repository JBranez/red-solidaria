<#
.SYNOPSIS
    Prepara Red Solidaria en una máquina Windows: .env con secretos aleatorios, entorno virtual de Python,
    dependencias de npm y (opcionalmente) la base de datos.

.PARAMETER SkipDatabase
    No crea ni carga la base de datos (úselo si SQL Server aún no está listo).
.PARAMETER NoDemo
    Importa solo los datos originales y el administrador (sin cuentas ni datos de demostración).

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -SkipDatabase
#>
[CmdletBinding()]
param(
    [switch]$SkipDatabase,
    [switch]$NoDemo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root     = $PSScriptRoot
$Backend  = Join-Path $Root 'backend'
$Frontend = Join-Path $Root 'frontend'
$VenvPy   = Join-Path $Backend '.venv\Scripts\python.exe'

function Write-Paso([string]$Texto)  { Write-Host "`n==> $Texto" -ForegroundColor Cyan }
function Write-Ok([string]$Texto)    { Write-Host "    OK  $Texto" -ForegroundColor Green }
function Write-Aviso([string]$Texto) { Write-Host "    !!  $Texto" -ForegroundColor Yellow }

function New-Secreto([int]$Bytes) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buffer)
    $rng.Dispose()
    # Solo letras y números: sin caracteres que compliquen ODBC, T-SQL o el shell
    return (([Convert]::ToBase64String($buffer)) -replace '[^A-Za-z0-9]', '')
}

function New-Clave([int]$Largo) {
    # Garantiza mayúscula, minúscula y número (política de contraseñas de SQL Server y de la API)
    $cuerpo = New-Secreto ($Largo * 2)
    $cuerpo = $cuerpo.Substring(0, $Largo - 3)
    return "Rs$($cuerpo)7a"
}

function Get-Version([string]$Comando, [string[]]$Argumentos) {
    try { return (& $Comando @Argumentos 2>&1 | Select-Object -First 1).ToString().Trim() } catch { return $null }
}

# ----------------------------------------------------------------------------------------------
Write-Paso 'Comprobando requisitos'
$py = $null
foreach ($candidato in @(@('py', '-3.12'), @('py', '-3'), @('python'), @('python3'))) {
    $v = Get-Version $candidato[0] ($candidato[1..($candidato.Length)] + '--version')
    if ($v -match 'Python (\d+)\.(\d+)' -and ([int]$Matches[1] -gt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -ge 12))) { $py = $candidato; Write-Ok $v; break }
}
if (-not $py) { throw 'Se requiere Python 3.12 o superior (https://www.python.org/downloads/). Marque "Add python.exe to PATH".' }

$nodeV = Get-Version 'node' @('--version')
if (-not $nodeV -or $nodeV -notmatch 'v(\d+)\.(\d+)\.(\d+)') { throw 'Se requiere Node.js 22.22.3 o superior (https://nodejs.org/).' }
$mayor = [int]$Matches[1]; $menor = [int]$Matches[2]; $parche = [int]$Matches[3]
$nodeOk = ($mayor -gt 22) -or ($mayor -eq 22 -and ($menor -gt 22 -or ($menor -eq 22 -and $parche -ge 3)))
if (-not $nodeOk) { throw "Angular 22 requiere Node.js 22.22.3 o superior; se encontró $nodeV." }
Write-Ok "Node.js $nodeV"

$odbc = Get-OdbcDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'ODBC Driver 18 for SQL Server' }
if ($odbc) { Write-Ok 'ODBC Driver 18 for SQL Server' }
else { Write-Aviso 'No se encontró "ODBC Driver 18 for SQL Server". Instálelo: https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server' }

# ----------------------------------------------------------------------------------------------
Write-Paso 'Archivos de configuración (.env)'
$envRaiz = Join-Path $Root '.env'
if (Test-Path $envRaiz) {
    Write-Ok '.env ya existe: se conserva (no se sobrescriben sus secretos)'
} else {
    $contenido = (Get-Content (Join-Path $Root '.env.example') -Raw)
    $reemplazos = [ordered]@{
        'DB_APP_PASSWORD='      = (New-Clave 28)
        'JWT_SECRET_KEY='       = (New-Secreto 48)
        'SEED_ADMIN_PASSWORD='  = (New-Clave 16)
        'SEED_DEMO_PASSWORD='   = (New-Clave 16)
    }
    foreach ($clave in $reemplazos.Keys) {
        $contenido = [regex]::Replace($contenido, "(?m)^$([regex]::Escape($clave)).*$", { param($m) "$clave$($reemplazos[$clave])" }.GetNewClosure())
    }
    [System.IO.File]::WriteAllText($envRaiz, $contenido, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '.env creado con secretos aleatorios (no se sube al repositorio)'
}

# Lee el .env de la raíz
$cfg = @{}
foreach ($linea in Get-Content $envRaiz) {
    if ($linea -match '^\s*([A-Z0-9_]+)\s*=\s*([^#]*?)\s*(#.*)?$') { $cfg[$Matches[1]] = $Matches[2].Trim() }
}
foreach ($obligatoria in 'DB_APP_PASSWORD', 'JWT_SECRET_KEY', 'SEED_ADMIN_PASSWORD') {
    if (-not $cfg[$obligatoria]) { throw "Falta $obligatoria en .env. Bórrelo y ejecute setup.ps1 de nuevo, o complételo." }
}

# backend/.env: solo lo que necesita la API (sin credenciales administrativas ni de carga)
$claves = 'APP_ENV', 'DB_SERVER', 'DB_PORT', 'DB_NAME', 'DB_DRIVER', 'DB_TRUST_SERVER_CERTIFICATE', 'DB_APP_USER', 'DB_APP_PASSWORD', 'JWT_SECRET_KEY', 'ACCESS_TOKEN_EXPIRE_MINUTES', 'CORS_ORIGINS'
$lineas = foreach ($k in $claves) { if ($cfg.ContainsKey($k)) { "$k=$($cfg[$k])" } }
[System.IO.File]::WriteAllText((Join-Path $Backend '.env'), (($lineas -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Ok 'backend/.env generado'

# ----------------------------------------------------------------------------------------------
Write-Paso 'Backend: entorno virtual y dependencias'
if (-not (Test-Path $VenvPy)) {
    $args1 = @($py[1..($py.Length)] | Where-Object { $_ }) + @('-m', 'venv', (Join-Path $Backend '.venv'))
    & $py[0] @args1
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el entorno virtual.' }
}
& $VenvPy -m pip install --quiet --upgrade pip
Push-Location $Backend
try {
    & $VenvPy -m pip install --quiet -r requirements-dev.txt -c constraints.txt
    if ($LASTEXITCODE -ne 0) { throw 'Falló la instalación de dependencias de Python.' }
} finally { Pop-Location }
Write-Ok 'Dependencias de Python instaladas (versiones fijadas en constraints.txt)'

# ----------------------------------------------------------------------------------------------
Write-Paso 'Frontend: dependencias de npm'
Push-Location $Frontend
try {
    if (Test-Path 'package-lock.json') { npm ci --no-audit --no-fund } else { npm install --no-audit --no-fund }
    if ($LASTEXITCODE -ne 0) { throw 'Falló npm install.' }
} finally { Pop-Location }
Write-Ok 'Dependencias de npm instaladas'

# ----------------------------------------------------------------------------------------------
if ($SkipDatabase) {
    Write-Aviso 'Base de datos omitida (-SkipDatabase). Cuando SQL Server esté listo:  .\database.ps1 -Action init ; .\database.ps1 -Action seed'
} else {
    Write-Paso 'Base de datos'
    & (Join-Path $Root 'database.ps1') -Action init
    if ($LASTEXITCODE -ne 0) { throw 'Falló la creación de la base de datos.' }
    if ($NoDemo) { & (Join-Path $Root 'database.ps1') -Action seed -NoDemo } else { & (Join-Path $Root 'database.ps1') -Action seed }
    if ($LASTEXITCODE -ne 0) { throw 'Falló la carga de datos.' }
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host ' Listo. Para iniciar la aplicación:  .\run.ps1' -ForegroundColor Green
Write-Host '   Aplicación : http://localhost:4200'
Write-Host '   API / docs : http://localhost:8000/docs'
Write-Host "   Usuario    : $($cfg['SEED_ADMIN_USERNAME'])   (la contraseña está en .env -> SEED_ADMIN_PASSWORD)"
if (-not $NoDemo) { Write-Host '   Cuentas demo: coordinacion, finanzas, trabajo.social, auditoria, voluntario, donante  (clave: SEED_DEMO_PASSWORD)' }
Write-Host '============================================================' -ForegroundColor Green

<#
.SYNOPSIS
    Gestiona la base de datos de Red Solidaria. Nunca borra datos.

.PARAMETER Action
    init   Crea/actualiza la base, tablas, procedimientos y la cuenta de aplicación (idempotente).
    all    init + seed en un paso.
    seed   Importa los CSV originales, crea usuarios y (salvo -NoDemo) datos de demostración (idempotente).
    check  Verifica la conexión con la cuenta de aplicación y su mínimo privilegio.
.PARAMETER SqlAuth
    Pide la contraseña de la cuenta administrativa (sa). Sin esta opción se usa autenticación de Windows
    (su usuario debe ser sysadmin) salvo que MSSQL_SA_PASSWORD esté definido. La contraseña NO se guarda en disco.
.EXAMPLE
    .\database.ps1 -Action init
    .\database.ps1 -Action seed -NoDemo
    .\database.ps1 -Action init -SqlAuth
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('init', 'seed', 'all', 'check')][string]$Action,
    [switch]$SqlAuth,
    [switch]$NoDemo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Backend = Join-Path $PSScriptRoot 'backend'
$VenvPy  = Join-Path $Backend '.venv\Scripts\python.exe'
if (-not (Test-Path $VenvPy)) { throw 'No existe el entorno virtual. Ejecute primero .\setup.ps1' }
if (-not (Test-Path (Join-Path $PSScriptRoot '.env'))) { throw 'No existe .env. Ejecute primero .\setup.ps1' }

$salvado = $env:MSSQL_SA_PASSWORD
if ($SqlAuth -and $Action -ne 'check') {
    $segura = Read-Host 'Contraseña de la cuenta administrativa (sa). No se guarda' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura)
    try { $env:MSSQL_SA_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

Push-Location $Backend
try {
    switch ($Action) {
        'init'  { & $VenvPy -m scripts.init_db }
        'seed'  { if ($NoDemo) { & $VenvPy -m scripts.seed --sin-demo } else { & $VenvPy -m scripts.seed } }
        'all'   {
            & $VenvPy -m scripts.init_db
            if ($LASTEXITCODE -eq 0) { if ($NoDemo) { & $VenvPy -m scripts.seed --sin-demo } else { & $VenvPy -m scripts.seed } }
        }
        'check' { & $VenvPy -m scripts.check_db }
    }
    $codigo = $LASTEXITCODE
} finally {
    Pop-Location
    $env:MSSQL_SA_PASSWORD = $salvado   # no deja la contraseña en el entorno del proceso
}
if ($codigo -ne 0) { exit $codigo }

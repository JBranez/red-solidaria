<#
.SYNOPSIS
    Inicia Red Solidaria: API (FastAPI, puerto 8000) y aplicación web (Angular, puerto 4200).

.PARAMETER Only
    backend | frontend : inicia solo una parte.
.PARAMETER Test
    Ejecuta las pruebas del backend y del frontend en lugar de iniciar la aplicación.
.EXAMPLE
    .\run.ps1
    .\run.ps1 -Only backend
    .\run.ps1 -Test
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'backend', 'frontend')][string]$Only = 'all',
    [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot; $Backend = Join-Path $Root 'backend'; $Frontend = Join-Path $Root 'frontend'
$VenvPy = Join-Path $Backend '.venv\Scripts\python.exe'
if (-not (Test-Path $VenvPy)) { throw 'No existe el entorno virtual. Ejecute primero .\setup.ps1' }

if ($Test) {
    Push-Location $Backend
    try { & $VenvPy -m pytest -q; $b = $LASTEXITCODE } finally { Pop-Location }
    Push-Location $Frontend
    try { npm test -- --watch=false; $f = $LASTEXITCODE } finally { Pop-Location }
    if ($b -ne 0 -or $f -ne 0) { exit 1 } else { exit 0 }
}

if ($Only -in 'all', 'backend') {
    Write-Host 'Iniciando API en http://localhost:8000  (documentación: /docs)' -ForegroundColor Cyan
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Backend -ArgumentList @(
        '-NoExit', '-NoProfile', '-Command', "`$host.UI.RawUI.WindowTitle='Red Solidaria - API'; & '$VenvPy' -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000")
}
if ($Only -in 'all', 'frontend') {
    Write-Host 'Iniciando aplicación web en http://localhost:4200' -ForegroundColor Cyan
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Frontend -ArgumentList @(
        '-NoExit', '-NoProfile', '-Command', "`$host.UI.RawUI.WindowTitle='Red Solidaria - Web'; npm start")
}
if ($Only -eq 'all') {
    Start-Sleep -Seconds 6
    Start-Process 'http://localhost:4200'
}

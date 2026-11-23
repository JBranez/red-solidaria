#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Owner,
    [Parameter(Mandatory=$true)][string]$Repository,
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$gh = (Get-Command gh.exe -ErrorAction Stop).Source
function Get-GhJson([string[]]$Arguments) {
    $r = Invoke-RSNative -FilePath $script:gh -ArgumentList $Arguments
    if ($r.ExitCode -ne 0) { throw ('gh {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$r.StdErr) }
    return ($r.StdOut | ConvertFrom-Json)
}
if (-not (Test-Path (Join-Path $ProjectRoot '.git'))) { throw 'ProjectRoot no contiene .git. No se puede recuperar el estado local.' }
$slug = "$Owner/$Repository"
$authResult = Invoke-RSNative -FilePath $script:gh -ArgumentList @('auth','status')
if ($authResult.ExitCode -ne 0) { throw 'GitHub CLI no está autenticado. Ejecuta gh auth login.' }
$statePath = Join-Path (Join-Path $ProjectRoot '.git') 'redsolidaria-publish-state.json'
if (Test-Path $statePath) { throw "Ya existe $statePath. No se sobrescribirá; ejecuta Publish-RedSolidaria.ps1 -Phase Status." }
$pr1 = Get-GhJson @('api',"repos/$slug/pulls/1")
$pr2 = Get-GhJson @('api',"repos/$slug/pulls/2")
if (-not $pr1.merged -or -not $pr2.merged) {
    throw 'No se reconstruirá el estado: PR #1 y PR #2 no están ambas fusionadas en GitHub.'
}
$tz = [TimeZoneInfo]::FindSystemTimeZoneById('SA Pacific Standard Time')
$created = @([DateTimeOffset]::Parse($pr1.created_at),[DateTimeOffset]::Parse($pr2.created_at)) | Sort-Object
$day1 = [TimeZoneInfo]::ConvertTime($created[0],$tz).ToString('yyyy-MM-dd')
$state = [pscustomobject]@{
    Owner = $Owner
    Repository = $Repository
    Slug = $slug
    Day1Date = $day1
    Day2Date = $null
    Day3Date = $null
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
Write-Host 'Estado local reconstruido únicamente a partir de PR #1 y #2 fusionadas.' -ForegroundColor Green
$state | Format-List
Write-Host "Archivo: $statePath"

#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$OutputPath = (Join-Path $HOME 'Documents\RedSolidaria-Azure-Subscription.json')
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$az = (Get-Command az -ErrorAction Stop).Source
function Invoke-AzText {
    param([string[]]$Arguments)
    $r = Invoke-RSNative -FilePath $script:az -ArgumentList $Arguments
    if ($r.ExitCode -ne 0) { throw ('az {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$r.StdErr) }
    return $r.StdOut
}
function Invoke-AzJson { param([string[]]$Arguments); $s=Invoke-AzText $Arguments; if (!$s) { return $null }; return ($s | ConvertFrom-Json) }

Write-Host '=== RED SOLIDARIA | VINCULAR AZURE FOR STUDENTS ===' -ForegroundColor Cyan
$accounts = @(Invoke-AzJson @('account','list','--all','--output','json'))
$enabled = @($accounts | Where-Object { $_.state -eq 'Enabled' })
if ($enabled.Count -eq 0) {
    throw 'No hay suscripciones Azure habilitadas. Ejecuta primero: az login'
}
if (-not $SubscriptionId) {
    $student = @($enabled | Where-Object { $_.name -match 'student' })
    if ($student.Count -eq 1) {
        $chosen = $student[0]
    } elseif ($student.Count -gt 1) {
        $enabled | Select-Object name,id,tenantId,state | Format-Table -AutoSize
        $SubscriptionId = Read-Host 'Introduce el Subscription ID de la suscripción Azure for Students'
        $chosen = $enabled | Where-Object { $_.id -eq $SubscriptionId } | Select-Object -First 1
    } elseif ($enabled.Count -eq 1) {
        $chosen = $enabled[0]
        Write-Warning "La suscripción activa se llama '$($chosen.name)'. Verifica en el portal que realmente sea Azure for Students."
        $confirm = Read-Host 'Escribe STUDENT para continuar solo si el portal confirma Azure for Students'
        if ($confirm -cne 'STUDENT') { throw 'Selección cancelada.' }
    } else {
        $enabled | Select-Object name,id,tenantId,state | Format-Table -AutoSize
        $SubscriptionId = Read-Host 'Introduce el Subscription ID de Azure for Students'
        $chosen = $enabled | Where-Object { $_.id -eq $SubscriptionId } | Select-Object -First 1
    }
} else {
    $chosen = $enabled | Where-Object { $_.id -eq $SubscriptionId } | Select-Object -First 1
}
if (!$chosen) { throw 'El Subscription ID indicado no está entre las suscripciones habilitadas de esta cuenta.' }
if ($chosen.state -ne 'Enabled') { throw "La suscripción está en estado $($chosen.state), no Enabled." }
Invoke-AzText @('account','set','--subscription',[string]$chosen.id) | Out-Null
$current = Invoke-AzJson @('account','show','--output','json')
if ($current.id -ne $chosen.id) { throw 'Azure CLI no dejó activa la suscripción seleccionada.' }

$record = [pscustomobject]@{
    subscriptionId = [string]$current.id
    subscriptionName = [string]$current.name
    tenantId = [string]$current.tenantId
    state = [string]$current.state
    user = [string]$current.user.name
    capturedAt = (Get-Date).ToString('o')
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath -Parent) | Out-Null
$record | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host ''
Write-Host 'Suscripción seleccionada correctamente.' -ForegroundColor Green
$record | Format-List
Write-Host "Registro local no secreto: $OutputPath" -ForegroundColor Yellow
Write-Host 'El Subscription ID y Tenant ID son identificadores de tu cuenta; no son códigos universales ni claves secretas.' -ForegroundColor Cyan

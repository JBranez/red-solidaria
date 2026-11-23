#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'))
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$az = (Get-Command az -ErrorAction Stop).Source
function Invoke-AzSafe {
    param([string[]]$Arguments)
    $r = Invoke-RSNative -FilePath $script:az -ArgumentList $Arguments
    if ($r.ExitCode -ne 0) { throw ('az {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$r.StdErr) }
    return $r.StdOut
}
if (!(Test-Path $ConfigPath)) { throw "Falta $ConfigPath." }
. $ConfigPath
Invoke-AzSafe @('account','set','--subscription',$SubscriptionId) | Out-Null
Write-Warning 'Deallocate detiene el cobro de cómputo, pero el disco administrado y la IP pública estática pueden seguir generando consumo.'
$answer = Read-Host "Escribe DEALLOCATE para detener $AzureVmName"
if ($answer -cne 'DEALLOCATE') { throw 'Operación cancelada.' }
Invoke-AzSafe @('vm','deallocate','--resource-group',$AzureResourceGroup,'--name',$AzureVmName,'--only-show-errors') | Out-Null
Write-Host 'VM desasignada. Los datos del disco se conservan.' -ForegroundColor Green

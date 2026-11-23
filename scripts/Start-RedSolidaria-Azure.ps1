#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'))
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$az = (Get-Command az -ErrorAction Stop).Source

function Invoke-AzChecked {
    param([string[]]$Arguments)
    $result = Invoke-RSNative -FilePath $script:az -ArgumentList $Arguments -ShowOutput
    if ($result.ExitCode -ne 0) {
        throw ('az {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$result.ExitCode,$result.StdErr)
    }
    return $result.StdOut
}

if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Falta $ConfigPath. Ejecuta primero Provision-RedSolidaria-Azure.ps1." }
. $ConfigPath
if (!$SubscriptionId -or !$AzureResourceGroup -or !$AzureVmName) { throw 'Faltan datos Azure en el archivo de configuración.' }
Invoke-AzChecked @('account','set','--subscription',$SubscriptionId) | Out-Null
Invoke-AzChecked @('vm','start','--resource-group',$AzureResourceGroup,'--name',$AzureVmName,'--only-show-errors') | Out-Null
$ready = $false
for ($attempt = 1; $attempt -le 36; $attempt++) {
    $state = Invoke-AzChecked @('vm','get-instance-view','--resource-group',$AzureResourceGroup,'--name',$AzureVmName,'--query',"instanceView.statuses[?code=='PowerState/running'].displayStatus | [0]",'--output','tsv','--only-show-errors')
    if ($state.Trim() -eq 'VM running') { $ready = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $ready) { throw 'La VM no llegó al estado VM running en 3 minutos. Revisa az vm get-instance-view.' }
Write-Host "VM iniciada: $Domain ($ServerIp)" -ForegroundColor Green

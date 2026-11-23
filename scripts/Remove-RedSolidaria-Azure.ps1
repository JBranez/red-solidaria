#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'))
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
if (!(Test-Path $ConfigPath)) { throw "Falta $ConfigPath." }
. $ConfigPath
$az = (Get-Command az -ErrorAction Stop).Source
$r = Invoke-RSNative -FilePath $az -ArgumentList @('account','set','--subscription',$SubscriptionId)
if ($r.ExitCode -ne 0) { throw ('No se pudo seleccionar la suscripción: ' + $r.StdErr) }
Write-Warning 'ESTA OPERACIÓN ELIMINA LA VM, DISCO, IP, VNET, NSG Y LOS DATOS SQL DEL GRUPO DE RECURSOS.'
$answer = Read-Host "Escribe ELIMINAR $AzureResourceGroup para borrar todo el grupo"
if ($answer -cne "ELIMINAR $AzureResourceGroup") { throw 'Eliminación cancelada.' }
$r = Invoke-RSNative -FilePath $az -ArgumentList @('group','delete','--name',$AzureResourceGroup,'--yes','--no-wait')
if ($r.ExitCode -ne 0) { throw ('Azure rechazó la eliminación del grupo: ' + $r.StdErr) }
Write-Host 'Grupo enviado a eliminación. Comprueba el estado en Azure Portal.' -ForegroundColor Yellow

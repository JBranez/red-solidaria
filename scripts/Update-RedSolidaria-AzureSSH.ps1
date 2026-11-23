#requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'),[string]$NewSshSourceCidr)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
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
if (!$NewSshSourceCidr) { $ip=(Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).ToString().Trim(); $NewSshSourceCidr="$ip/32" }
if ($NewSshSourceCidr -notmatch '^(?<ip>\d{1,3}(?:\.\d{1,3}){3})/32$') { throw 'Usa una IPv4/32.' }
$parsed=$null
if (-not [Net.IPAddress]::TryParse($Matches.ip,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'La IPv4 no es válida.' }
Invoke-AzSafe @('account','set','--subscription',$SubscriptionId) | Out-Null
Invoke-AzSafe @('network','nsg','rule','update','--resource-group',$AzureResourceGroup,'--nsg-name','nsg-redsolidaria','--name','Allow-SSH-My-IP','--source-address-prefixes',$NewSshSourceCidr,'--only-show-errors') | Out-Null
$content = Get-Content $ConfigPath -Raw
if ($content -notmatch '(?m)^\$SshSourceCidr\s*=') { throw 'No se encontró SshSourceCidr en la configuración.' }
$content = $content -replace '(?m)^\$SshSourceCidr\s*=.*$',('$SshSourceCidr = ' + "'" + $NewSshSourceCidr + "'")
[IO.File]::WriteAllText($ConfigPath,$content,[Text.UTF8Encoding]::new($true))
Write-Host "SSH limitado a $NewSshSourceCidr" -ForegroundColor Green

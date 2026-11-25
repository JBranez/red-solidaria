# Abre un túnel SSH temporal y prepara SSMS para consultar la base de Azure.
# La clave privada se crea y conserva únicamente en este equipo. No imprimirla
# ni copiarla al repositorio. La contraseña SQL se escribe en el diálogo SSMS.
[CmdletBinding()]
param(
    [string]$SubscriptionId = '09054927-5863-4fae-acf8-558d72a271ac',
    [string]$TenantId = '966233e3-0b75-4c77-877a-d9b70a69ea01',
    [string]$ResourceGroup = 'rg-redsolidaria',
    [string]$VmName = 'vm-redsolidaria',
    [string]$NsgName = 'nsg-redsolidaria',
    [string]$NsgRuleName = 'Allow-SSH-My-IP',
    [string]$HostName = 'redsolidaria-jbranez.chilecentral.cloudapp.azure.com',
    [string]$SshUser = 'azureuser',
    [int]$LocalPort = 14333,
    [string]$Database = 'RedSolidaria',
    [string]$SqlUser = 'sa'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-AzChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI falló (exit $LASTEXITCODE): $($result -join [Environment]::NewLine)"
    }
    return ($result -join [Environment]::NewLine)
}

$az = Get-Command az -ErrorAction SilentlyContinue
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$keygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
if (!$az -or !$ssh -or !$keygen) {
    throw 'Instala Azure CLI y Windows OpenSSH Client antes de ejecutar este script.'
}
$azVersionData = (& az version -o json 2>$null | ConvertFrom-Json)
$azVersion = [string]$azVersionData.'azure-cli'
if ($LASTEXITCODE -ne 0 -or [version]$azVersion -lt [version]'2.60.0') {
    throw "Azure CLI 2.60.0 o posterior es requerido; detectado: $azVersion"
}
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$sshVersionText = (& $ssh.Source -V 2>&1 | Select-Object -First 1).ToString()
$ErrorActionPreference = $previousPreference
if ($sshVersionText -notmatch 'OpenSSH_for_Windows_(\d+\.\d+)') {
    throw "No pude validar la versión de Windows OpenSSH Client: $sshVersionText"
}
Write-Host "Azure CLI $azVersion; $sshVersionText"

$ssmsCandidates = @(
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\SSMS.exe",
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 21\Release\Common7\IDE\SSMS.exe",
    "$env:ProgramFiles\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
)
$ssms = $ssmsCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$ssms) { throw 'No encuentro SSMS instalado. Instala SSMS desde Microsoft y vuelve a ejecutar.' }
$ssmsVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($ssms).ProductVersion
if ([version]($ssmsVersion -replace '[^0-9.].*$','') -lt [version]'20.0') {
    throw "Se requiere SSMS 20 o posterior; detectado: $ssmsVersion"
}
Write-Host "SSMS $ssmsVersion"

$accountText = & az account show -o json 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Se abrirá Azure CLI para iniciar sesión; completa MFA si te lo solicita.' -ForegroundColor Yellow
    Invoke-AzChecked @('login','--tenant',$TenantId,'--output','none') | Out-Null
    $accountText = & az account show -o json
}
$account = $accountText | ConvertFrom-Json
if ($account.state -ne 'Enabled') { throw "La suscripción Azure está en estado $($account.state)." }
Invoke-AzChecked @('account','set','--subscription',$SubscriptionId) | Out-Null

$ip = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).Trim()
if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "No pude validar la IP pública: $ip" }
$cidr = "$ip/32"
$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyPath = Join-Path $sshDir 'redsolidaria_university'
if (!(Test-Path -LiteralPath $keyPath)) {
    & $keygen.Source -q -t ed25519 -N '""' -C "redsolidaria-$(Get-Date -Format yyyyMMdd)" -f $keyPath
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar la llave SSH local.' }
}
$publicKey = (Get-Content -LiteralPath "$keyPath.pub" -Raw).Trim()
if ($publicKey -notmatch '^ssh-ed25519\s+[A-Za-z0-9+/]+=*') { throw 'La llave pública SSH local no tiene formato ed25519.' }

Write-Host "Autorizando temporalmente SSH desde $cidr en el NSG..."
Invoke-AzChecked @('network','nsg','rule','update','--resource-group',$ResourceGroup,'--nsg-name',$NsgName,'--name',$NsgRuleName,'--source-address-prefixes',$cidr,'--output','none') | Out-Null

# Azure Run Command transporta solo la llave PÚBLICA y cambia UFW a la IP
# actual. La llave de host obtenida mediante Azure Resource Manager se valida
# localmente antes de escribirla en known_hosts.
$pub64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($publicKey))
$keyBlob = ($publicKey -split '\s+')[1]
$remoteScript = @(
    'set -eu',
    "install -d -m 700 -o $SshUser -g $SshUser /home/$SshUser/.ssh",
    "touch /home/$SshUser/.ssh/authorized_keys",
    "chmod 600 /home/$SshUser/.ssh/authorized_keys",
    "grep -Fv '$keyBlob' /home/$SshUser/.ssh/authorized_keys > /home/$SshUser/.ssh/authorized_keys.redsolidaria-tmp || true",
    "printf '%s' '$pub64' | base64 -d >> /home/$SshUser/.ssh/authorized_keys.redsolidaria-tmp",
    "printf '\n' >> /home/$SshUser/.ssh/authorized_keys.redsolidaria-tmp",
    "mv /home/$SshUser/.ssh/authorized_keys.redsolidaria-tmp /home/$SshUser/.ssh/authorized_keys",
    "chmod 600 /home/$SshUser/.ssh/authorized_keys",
    "chown ${SshUser}:${SshUser} /home/$SshUser/.ssh/authorized_keys",
    "ufw allow from $ip to any port 22 proto tcp",
    'ufw --force delete allow 22/tcp >/dev/null 2>&1 || true',
    'cat /etc/ssh/ssh_host_ed25519_key.pub'
) -join '; '
$runResult = Invoke-AzChecked @('vm','run-command','invoke','--resource-group',$ResourceGroup,'--name',$VmName,'--command-id','RunShellScript','--scripts',$remoteScript,'--output','json')
$runJson = $runResult | ConvertFrom-Json
$message = ($runJson.value | ForEach-Object message) -join "`n"
$hostKeyMatch = [regex]::Match($message,'(?m)^ssh-ed25519\s+[A-Za-z0-9+/]+={0,2}(?:\s+[^\r\n]*)?$')
if (!$hostKeyMatch.Success) { throw "Azure Run Command no devolvió una llave de host Ed25519 válida: $message" }
$hostKeyLine = $hostKeyMatch.Value.Trim()
$hostKeyFile = Join-Path $env:TEMP ("rs-hostkey-" + [guid]::NewGuid().ToString('N'))
try {
    $hostKeyLine | Set-Content -LiteralPath $hostKeyFile -Encoding ascii
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $fingerprintOutput = @(& $keygen.Source -lf $hostKeyFile 2>&1)
    $keygenExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($keygenExitCode -ne 0 -or $fingerprintOutput.Count -eq 0) {
        throw "La llave de host recibida de Azure no es válida (ssh-keygen exit $keygenExitCode): $($fingerprintOutput -join ' ')."
    }
    $fingerprintParts = ([string]$fingerprintOutput[0] -split '\s+')
    if ($fingerprintParts.Count -lt 2) { throw "ssh-keygen devolvió una respuesta inesperada: $($fingerprintOutput -join ' ')" }
    $trustedFingerprint = $fingerprintParts[1]
} finally { Remove-Item -LiteralPath $hostKeyFile -Force -ErrorAction SilentlyContinue }
if ([string]::IsNullOrWhiteSpace($trustedFingerprint) -or $trustedFingerprint -notmatch '^SHA256:') {
    throw "La huella SSH recibida de Azure no tiene el formato esperado: $trustedFingerprint"
}

$knownHosts = Join-Path $sshDir 'redsolidaria_known_hosts'
"$HostName $hostKeyLine" | Set-Content -LiteralPath $knownHosts -Encoding ascii
Write-Host "Huella del servidor obtenida por Azure: $trustedFingerprint"
$existing = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
if ($existing) { throw "El puerto local $LocalPort ya está ocupado. Cierra el túnel existente o elige otro puerto." }

Write-Host "Abriendo túnel 127.0.0.1:$LocalPort -> SQL privado de Azure..."
$sshArgs = @('-i',$keyPath,'-N','-L',"127.0.0.1:${LocalPort}:127.0.0.1:1433",'-o','ExitOnForwardFailure=yes','-o','StrictHostKeyChecking=yes','-o',"UserKnownHostsFile=$knownHosts",'-o','ServerAliveInterval=30',"$SshUser@$HostName")
$tunnel = Start-Process -FilePath $ssh.Source -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
$ready = $false
for ($i=0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) { $ready=$true; break }
    if ($tunnel.HasExited) { throw "SSH terminó antes de abrir el túnel (exit $($tunnel.ExitCode))." }
}
if (!$ready) { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue; throw 'No abrió el puerto local del túnel.' }

Write-Host "Túnel activo en 127.0.0.1:$LocalPort. Abriendo SSMS; escribe allí la contraseña SQL." -ForegroundColor Green
Start-Process -FilePath $ssms -ArgumentList @('-S',"127.0.0.1,$LocalPort",'-d',$Database,'-U',$SqlUser,'-C')
Write-Host 'No cierres el túnel SSH mientras uses SSMS. Finaliza el túnel con: Stop-Process -Id' $tunnel.Id

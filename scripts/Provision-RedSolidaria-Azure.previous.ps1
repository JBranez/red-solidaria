#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$Location = 'eastus2',
    [string]$VmSize = 'Standard_B2ms',
    [string]$ResourceGroup = 'rg-redsolidaria',
    [string]$VmName = 'vm-redsolidaria',
    [string]$ImageUrn = 'Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest',
    [string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'),
    [string]$SubscriptionRecordPath = (Join-Path $HOME 'Documents\RedSolidaria-Azure-Subscription.json'),
    [string]$SshSourceCidr,
    [switch]$Allow4GBFallback,
    [switch]$NoConfirm
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$script:Az = (Get-Command az -ErrorAction Stop).Source

function Invoke-AzRaw {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    return (Invoke-RSNative -FilePath $script:Az -ArgumentList $Arguments)
}
function Invoke-AzChecked {
    param([string[]]$Arguments)
    $r = Invoke-AzRaw -Arguments $Arguments
    if ($r.ExitCode -ne 0) { throw ('az {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$r.StdErr) }
    return $r.StdOut
}
function Invoke-AzJson { param([string[]]$Arguments); $s=Invoke-AzChecked $Arguments; if ([string]::IsNullOrWhiteSpace($s)) { return $null }; return ($s | ConvertFrom-Json) }
function Test-AzResource {
    param([string[]]$ShowArguments)
    $r=Invoke-AzRaw -Arguments $ShowArguments
    return ($r.ExitCode -eq 0)
}
function Ensure-NsgRule {
    param([string]$Name,[int]$Priority,[string]$Source,[string]$Port,[string]$Description)
    $check = Invoke-AzRaw -Arguments @('network','nsg','rule','show','--resource-group',$ResourceGroup,'--nsg-name',$nsgName,'--name',$Name,'--output','json')
    if ($check.ExitCode -eq 0) {
        Invoke-AzChecked @('network','nsg','rule','update','--resource-group',$ResourceGroup,'--nsg-name',$nsgName,'--name',$Name,'--source-address-prefixes',$Source,'--destination-port-ranges',$Port,'--description',$Description,'--output','none') | Out-Null
        return
    }
    Invoke-AzChecked @('network','nsg','rule','create','--resource-group',$ResourceGroup,'--nsg-name',$nsgName,'--name',$Name,'--priority',([string]$Priority),'--direction','Inbound','--access','Allow','--protocol','Tcp','--source-address-prefixes',$Source,'--source-port-ranges','*','--destination-address-prefixes','*','--destination-port-ranges',$Port,'--description',$Description,'--output','none') | Out-Null
}
function Get-SkuInfo {
    param([string]$Region,[string]$Size)
    $items = @(Invoke-AzJson @('vm','list-skus','--location',$Region,'--size',$Size,'--output','json'))
    $item = $items | Where-Object { $_.name -eq $Size } | Select-Object -First 1
    if (!$item) { return $null }
    $hardRestrictions = @($item.restrictions | Where-Object {
        $_.reasonCode -eq 'NotAvailableForSubscription' -or $_.type -eq 'Location'
    })
    if ($hardRestrictions.Count -gt 0) { return $null }
    $caps = @($item.capabilities)
    $vcpu = ($caps | Where-Object { $_.name -eq 'vCPUs' } | Select-Object -First 1).value
    $mem = ($caps | Where-Object { $_.name -eq 'MemoryGB' } | Select-Object -First 1).value
    $arch = ($caps | Where-Object { $_.name -eq 'CpuArchitectureType' } | Select-Object -First 1).value
    if (!$vcpu -or !$mem) { return $null }
    if ($arch -and $arch -notmatch 'x64|x86') { return $null }
    return [pscustomobject]@{ Name=$Size; Vcpus=[int]$vcpu; MemoryGB=[double]$mem; Family=[string]$item.family }
}

Write-Host '=== RED SOLIDARIA | APROVISIONAMIENTO AZURE FOR STUDENTS ===' -ForegroundColor Cyan
if (!(Get-Command ssh-keygen -ErrorAction SilentlyContinue)) { throw 'Falta OpenSSH Client. Instálalo desde Configuración > Características opcionales > OpenSSH Client.' }
if (!(Get-Command ssh -ErrorAction SilentlyContinue)) { throw 'Falta ssh.exe de OpenSSH Client.' }

if (!$SubscriptionId) {
    if (Test-Path $SubscriptionRecordPath) {
        $record = Get-Content $SubscriptionRecordPath -Raw | ConvertFrom-Json
        $SubscriptionId = [string]$record.subscriptionId
    } else { throw "Primero ejecuta .\scripts\Connect-RedSolidaria-Azure.ps1. No se encontró $SubscriptionRecordPath" }
}
if ($SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { throw 'SubscriptionId no tiene formato GUID.' }
Invoke-AzChecked @('account','set','--subscription',$SubscriptionId) | Out-Null
$account = Invoke-AzJson @('account','show','--output','json')
if ($account.id -ne $SubscriptionId -or $account.state -ne 'Enabled') { throw 'La suscripción seleccionada no está habilitada.' }
if ($account.name -notmatch 'student') {
    Write-Warning "El nombre activo de suscripción es '$($account.name)'. Verifica Azure Portal > Subscriptions que el offer sea Azure for Students y que tenga créditos antes de crear recursos."
    $confirmStudent = Read-Host 'Escribe STUDENT si confirmas que esta es tu suscripción Azure for Students'
    if ($confirmStudent -cne 'STUDENT') { throw 'Aprovisionamiento cancelado.' }
}
Write-Host "Suscripción: $($account.name)" -ForegroundColor Green
Write-Host "Subscription ID: $($account.id)"
Write-Host "Tenant ID: $($account.tenantId)"
Write-Host 'Créditos restantes: consulta https://www.microsoftazuresponsorships.com/Balance antes de continuar.' -ForegroundColor Yellow

# Evitar regiones y tamaños bloqueados por la suscripción. No se especifica zona de disponibilidad.
$sizeCandidates = @($VmSize,'Standard_D2as_v5','Standard_D2s_v5') | Select-Object -Unique
if ($Allow4GBFallback) { $sizeCandidates += 'Standard_B2s' }
$selectedSku = $null
foreach ($candidate in $sizeCandidates) {
    try { $candidateInfo = Get-SkuInfo -Region $Location -Size $candidate }
    catch { $candidateInfo = $null }
    if ($candidateInfo -and $candidateInfo.MemoryGB -ge 8) { $selectedSku = $candidateInfo; break }
}
if (!$selectedSku -and $Allow4GBFallback) {
    $candidateInfo = Get-SkuInfo -Region $Location -Size 'Standard_B2s'
    if ($candidateInfo -and $candidateInfo.MemoryGB -ge 4) { $selectedSku = $candidateInfo }
}
if (!$selectedSku) {
    Write-Host 'Tamaños comprobados y no disponibles con esta suscripción en esta región:' -ForegroundColor Yellow
    $sizeCandidates | ForEach-Object { Write-Host " - $_" }
    Write-Host 'Consulta regiones y cuotas con:' -ForegroundColor Yellow
    Write-Host "az vm list-skus --location $Location --size Standard_B2ms --output table"
    Write-Host "az vm list-usage --location $Location --output table"
    throw 'No se encontró una VM x64 de 8 GB habilitada. Prueba otra región permitida. Como último recurso, usa -Allow4GBFallback para Standard_B2s (4 GB, rendimiento más limitado).'
}
$VmSize = $selectedSku.Name
Write-Host ("SKU aprobado por Azure: {0} | {1} vCPU | {2} GB RAM | {3}" -f $VmSize,$selectedSku.Vcpus,$selectedSku.MemoryGB,$selectedSku.Family) -ForegroundColor Green

$usage = @(Invoke-AzJson @('vm','list-usage','--location',$Location,'--output','json'))
$total = $usage | Where-Object { $_.name.value -eq 'cores' -or $_.name.localizedValue -match 'Total Regional vCPUs' } | Select-Object -First 1
if ($total) {
    $remaining = [int]$total.limit - [int]$total.currentValue
    Write-Host ("Cuota regional de vCPU: {0}/{1} en uso; quedan {2}." -f $total.currentValue,$total.limit,$remaining)
    if ($remaining -lt $selectedSku.Vcpus) { throw "Cuota regional insuficiente en $Location. No se creará la VM. Solicita cuota en Azure Portal > Subscriptions > Usage + quotas o prueba otra región permitida." }
} else {
    Write-Warning 'Azure no devolvió Total Regional vCPUs en list-usage. La creación validará la cuota regional real.'
}
# Algunas familias tienen una cuota independiente además de la cuota regional.
if ($selectedSku.Family) {
    $familyQuota = $usage | Where-Object { $_.name.value -eq $selectedSku.Family } | Select-Object -First 1
    if ($familyQuota) {
        $familyRemaining = [int]$familyQuota.limit - [int]$familyQuota.currentValue
        Write-Host ("Cuota de familia {0}: {1}/{2} en uso; quedan {3}." -f $selectedSku.Family,$familyQuota.currentValue,$familyQuota.limit,$familyRemaining)
        if ($familyRemaining -lt $selectedSku.Vcpus) { throw "Cuota insuficiente para la familia $($selectedSku.Family) en $Location. No se creará la VM." }
    }
}

# Registrar proveedores necesarios, si aún no están registrados.
foreach ($provider in @('Microsoft.Compute','Microsoft.Network','Microsoft.Storage')) {
    $status = Invoke-AzChecked @('provider','show','--namespace',$provider,'--query','registrationState','--output','tsv')
    if ([string]$status -ne 'Registered') {
        Invoke-AzChecked @('provider','register','--namespace',$provider,'--output','none') | Out-Null
        for ($i=0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 5
            $status = Invoke-AzChecked @('provider','show','--namespace',$provider,'--query','registrationState','--output','tsv')
            if ([string]$status -eq 'Registered') { break }
        }
        if ([string]$status -ne 'Registered') { throw "El proveedor $provider no llegó a estado Registered." }
    }
}

if (!$SshSourceCidr) {
    try { $publicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).ToString().Trim() }
    catch { $publicIp = Read-Host 'No se detectó tu IP pública. Introduce tu IPv4 (sin /32)' }
    $SshSourceCidr = "$publicIp/32"
}
if ($SshSourceCidr -notmatch '^(?<ip>\d{1,3}(?:\.\d{1,3}){3})/32$') { throw 'SshSourceCidr debe ser una IPv4 con /32, por ejemplo 203.0.113.10/32.' }
$parsedSshIp = $null
if (-not [Net.IPAddress]::TryParse($Matches.ip, [ref]$parsedSshIp) -or $parsedSshIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'La IPv4 de origen SSH no es válida.' }

$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyPath = Join-Path $sshDir 'redsolidaria_azure_ed25519'
$pubPath = "$keyPath.pub"
if (!(Test-Path $keyPath)) {
    $sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
    $keyResult = Invoke-RSNative -FilePath $sshKeygen -ArgumentList @('-t','ed25519','-C','red-solidaria-azure','-N','','-f',$keyPath)
    if ($keyResult.ExitCode -ne 0) { throw ('No se pudo generar la llave SSH. {0}' -f $keyResult.StdErr) }
}
if (!(Test-Path $pubPath)) { throw 'Falta la llave pública SSH.' }
if (Get-Command icacls.exe -ErrorAction SilentlyContinue) {
    $aclExe = (Get-Command icacls.exe -ErrorAction Stop).Source
    $aclResult = Invoke-RSNative -FilePath $aclExe -ArgumentList @($keyPath,'/inheritance:r','/grant:r',"$($env:USERNAME):(R,W)")
    if ($aclResult.ExitCode -ne 0) { throw ('No se pudieron restringir los permisos de la llave privada SSH. ' + $aclResult.StdErr) }
}

# Nombres y DNS aleatorios para evitar colisiones globales de Azure DNS.
$dnsLabel = ('redsolidaria-' + ([guid]::NewGuid().ToString('N').Substring(0,8))).ToLowerInvariant()
$nsgName = 'nsg-redsolidaria'
$vnetName = 'vnet-redsolidaria'
$subnetName = 'subnet-app'
$publicIpName = 'pip-redsolidaria'

Write-Host ''
Write-Host 'Recursos que se crearán:' -ForegroundColor Cyan
[pscustomobject]@{ ResourceGroup=$ResourceGroup; Location=$Location; VM=$VmName; Size=$VmSize; RAM_GB=$selectedSku.MemoryGB; Disk_GB=64; SshSource=$SshSourceCidr; WebPorts='80,443'; SQLPublicPort='CERRADO'; DNSLabel=$dnsLabel } | Format-List
Write-Host 'Azure for Students incluye USD 100 de crédito por 12 meses; la VM, disco e IP consumen ese saldo. No se debe asumir coste cero.' -ForegroundColor Yellow
Write-Host 'El precio cambia por región y tamaño. Consulta Azure Pricing Calculator y el saldo de Azure for Students antes de confirmar.' -ForegroundColor Yellow
Write-Host 'https://azure.microsoft.com/pricing/calculator/' -ForegroundColor Yellow
if (-not $NoConfirm) {
    $confirm = Read-Host 'Escribe CREAR para crear/reutilizar el grupo de recursos y la VM con cargo a tus créditos'
    if ($confirm -cne 'CREAR') { throw 'Aprovisionamiento cancelado por el usuario.' }
} else {
    Write-Warning 'Se usó -NoConfirm: la creación se autoriza sin pregunta interactiva.'
}

# Resource group
if (!(Test-AzResource @('group','show','--name',$ResourceGroup,'--output','json'))) {
    Invoke-AzChecked @('group','create','--name',$ResourceGroup,'--location',$Location,'--tags','project=redsolidaria','environment=school','--output','none') | Out-Null
}
# NSG
$nsgName = 'nsg-redsolidaria'
if (!(Test-AzResource @('network','nsg','show','--resource-group',$ResourceGroup,'--name',$nsgName,'--output','json'))) {
    Invoke-AzChecked @('network','nsg','create','--resource-group',$ResourceGroup,'--name',$nsgName,'--location',$Location,'--output','none') | Out-Null
}
Ensure-NsgRule -Name 'Allow-SSH-My-IP' -Priority 100 -Source $SshSourceCidr -Port '22' -Description 'SSH only from the provisioning public IPv4'
Ensure-NsgRule -Name 'Allow-HTTP' -Priority 110 -Source 'Internet' -Port '80' -Description 'HTTP for ACME and redirect'
Ensure-NsgRule -Name 'Allow-HTTPS' -Priority 120 -Source 'Internet' -Port '443' -Description 'Public HTTPS application'
# No rule for TCP 1433: SQL Server is not publicly exposed.

# VNet / subnet
if (!(Test-AzResource @('network','vnet','show','--resource-group',$ResourceGroup,'--name',$vnetName,'--output','json'))) {
    Invoke-AzChecked @('network','vnet','create','--resource-group',$ResourceGroup,'--name',$vnetName,'--location',$Location,'--address-prefixes','10.41.0.0/16','--subnet-name',$subnetName,'--subnet-prefixes','10.41.1.0/24','--output','none') | Out-Null
}
# Crear IP Standard estática con DNS de Azure si aún no existe.
if (!(Test-AzResource @('network','public-ip','show','--resource-group',$ResourceGroup,'--name',$publicIpName,'--output','json'))) {
    Invoke-AzChecked @('network','public-ip','create','--resource-group',$ResourceGroup,'--name',$publicIpName,'--location',$Location,'--version','IPv4','--sku','Standard','--allocation-method','Static','--dns-name',$dnsLabel,'--output','none') | Out-Null
}
$publicIpDoc = Invoke-AzJson @('network','public-ip','show','--resource-group',$ResourceGroup,'--name',$publicIpName,'--output','json')
if ($publicIpDoc.dnsSettings.domainNameLabel) { $dnsLabel = [string]$publicIpDoc.dnsSettings.domainNameLabel }

# Existing VM: do not create a duplicate. Re-read its actual size for the memory caps.
$existingVm = Test-AzResource @('vm','show','--resource-group',$ResourceGroup,'--name',$VmName,'--output','json')
if ($existingVm) {
    $existingVmDoc = Invoke-AzJson @('vm','show','--resource-group',$ResourceGroup,'--name',$VmName,'--output','json')
    $actualSize = [string]$existingVmDoc.hardwareProfile.vmSize
    if ($actualSize) {
        $actualSku = Get-SkuInfo -Region $Location -Size $actualSize
        if (-not $actualSku) { throw "La VM existente usa $actualSize y no se pudo validar su arquitectura/capacidad. Revisa Azure Portal antes de continuar." }
        $selectedSku = $actualSku
        $VmSize = $actualSize
    }
} else {
    Invoke-AzChecked @('vm','create','--resource-group',$ResourceGroup,'--name',$VmName,'--location',$Location,'--size',$VmSize,'--image',$ImageUrn,'--admin-username','azureuser','--ssh-key-values',("@"+$pubPath),'--vnet-name',$vnetName,'--subnet',$subnetName,'--nsg',$nsgName,'--public-ip-address',$publicIpName,'--os-disk-size-gb','64','--storage-sku','StandardSSD_LRS','--security-type','Standard','--tags','project=redsolidaria','purpose=school-demo','--output','none') | Out-Null
}

$publicIpDoc = Invoke-AzJson @('network','public-ip','show','--resource-group',$ResourceGroup,'--name',$publicIpName,'--output','json')
$serverIp = [string]$publicIpDoc.ipAddress
$domain = [string]$publicIpDoc.dnsSettings.fqdn
$dnsLabel = [string]$publicIpDoc.dnsSettings.domainNameLabel
$ipDoc = Invoke-AzJson @('vm','list-ip-addresses','--resource-group',$ResourceGroup,'--name',$VmName,'--output','json')
$vmPublicIp = [string]$ipDoc[0].virtualMachine.network.publicIpAddresses[0].ipAddress
if (!$serverIp -or !$domain -or !$vmPublicIp) { throw 'Azure no devolvió IPv4/FQDN de la VM o la IP pública.' }
if ($vmPublicIp -ne $serverIp) { throw "La VM usa $vmPublicIp pero la IP DNS reservada es $serverIp. No continúes; revisa la IP pública asociada a la NIC en Azure Portal." }

# Save a reusable PowerShell profile outside the repository.
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configDir = Split-Path $ConfigPath -Parent
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
function Q([string]$Value) { return "'" + $Value.Replace("'","''") + "'" }
$config = @(
    ('$ProjectRoot = ' + (Q $projectRoot)),
    ('$Owner = ' + (Q 'JBranez')),
    ('$Repository = ' + (Q 'red-solidaria')),
    ('$RepoSlug = ' + (Q 'JBranez/red-solidaria')),
    ('$SubscriptionId = ' + (Q $account.id)),
    ('$TenantId = ' + (Q $account.tenantId)),
    ('$SubscriptionName = ' + (Q $account.name)),
    ('$AzureResourceGroup = ' + (Q $ResourceGroup)),
    ('$AzureVmName = ' + (Q $VmName)),
    ('$AzureLocation = ' + (Q $Location)),
    ('$AzureVmSize = ' + (Q $VmSize)),
    ('$AzureDnsLabel = ' + (Q $dnsLabel)),
    ('$ServerIp = ' + (Q $serverIp)),
    ('$SshUser = ' + (Q 'azureuser')),
    ('$SshPort = 22'),
    ('$InitialKeyPath = ' + (Q $keyPath)),
    ('$Domain = ' + (Q $domain)),
    ('$SshSourceCidr = ' + (Q $SshSourceCidr)),
    ('$MssqlMemoryLimitMB = ' + $(if ($selectedSku.MemoryGB -ge 8) { '3072' } else { '2048' })),
    ('$MssqlContainerMemoryLimit = ' + $(if ($selectedSku.MemoryGB -ge 8) { Q '4g' } else { Q '3g' }))
)
[IO.File]::WriteAllLines($ConfigPath,$config,[Text.UTF8Encoding]::new($true))
$summaryPath = Join-Path $configDir 'RedSolidaria-Azure-VM.json'
[pscustomobject]@{ provider='Azure for Students'; subscriptionId=$account.id; tenantId=$account.tenantId; subscriptionName=$account.name; resourceGroup=$ResourceGroup; vmName=$VmName; location=$Location; vmSize=$VmSize; memoryGB=$selectedSku.MemoryGB; ip=$serverIp; fqdn=$domain; sshUser='azureuser'; sshKeyPath=$keyPath; sshSourceCidr=$SshSourceCidr; createdAt=(Get-Date).ToString('o') } | ConvertTo-Json -Depth 5 | Set-Content $summaryPath -Encoding UTF8

Write-Host ''
Write-Host 'VPS AZURE CREADA/RECUPERADA.' -ForegroundColor Green
Write-Host "Subscription ID: $($account.id)"
Write-Host "Tenant ID: $($account.tenantId)"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "VM: $VmName ($VmSize, $($selectedSku.MemoryGB) GB RAM)"
Write-Host "Imagen: $ImageUrn"
Write-Host "IP: $serverIp"
Write-Host "Dominio: $domain"
Write-Host "SSH user: azureuser"
Write-Host "Llave privada: $keyPath"
Write-Host "Configuración: $ConfigPath"
Write-Host "Resumen: $summaryPath"
Write-Host 'SQL Server 1433 permanece cerrado en NSG.' -ForegroundColor Green
Write-Host 'Verifica la huella SSH al ejecutar el despliegue.' -ForegroundColor Yellow

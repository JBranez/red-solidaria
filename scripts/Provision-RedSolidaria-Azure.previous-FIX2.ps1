#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SubscriptionId = '09054927-5863-4fae-acf8-558d72a271ac',
    [string]$TenantId = '966233e3-0b75-4c77-877a-d9b70a69ea01',
    [string[]]$Regions = @('eastus2','eastus','centralus','southcentralus','westus2','westus3','northcentralus','canadacentral'),
    [string]$ResourceGroup = 'rg-redsolidaria',
    [string]$VmName = 'vm-redsolidaria',
    [string]$ConfigPath = (Join-Path $HOME 'Documents\RedSolidaria-config.ps1'),
    [string]$SshSourceCidr,
    [switch]$Allow4GBFallback
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$script:AzExe = (Get-Command az -ErrorAction Stop).Source

function Invoke-AzRaw {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    return (Invoke-RSNative -FilePath $script:AzExe -ArgumentList $Arguments)
}
function Invoke-AzChecked {
    param([Parameter(Mandatory=$true)][string[]]$Arguments,[switch]$ShowOutput)
    $r = Invoke-AzRaw -Arguments $Arguments
    if ($ShowOutput -and $r.StdOut) { Write-Host $r.StdOut }
    if ($r.ExitCode -ne 0) {
        $detail = if ($r.StdErr) { $r.StdErr } else { $r.StdOut }
        throw ('az {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$detail)
    }
    return [string]$r.StdOut
}
function Invoke-AzJson {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $text = Invoke-AzChecked -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}
function Normalize-Key {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.ToLowerInvariant()) -replace '[^a-z0-9]','')
}
function Get-CapabilityValue {
    param($Sku,[string]$CapabilityName)
    $cap = @($Sku.capabilities | Where-Object { [string]$_.name -eq $CapabilityName } | Select-Object -First 1)
    if ($cap.Count -eq 0) { return $null }
    return [string]$cap[0].value
}
function Get-QuotaRow {
    param($Usage,[string]$Family)
    $familyKey = Normalize-Key $Family
    foreach ($row in @($Usage)) {
        $localized = Normalize-Key ([string]$row.name.localizedValue)
        $code = Normalize-Key ([string]$row.name.value)
        if ($localized.StartsWith($familyKey) -or $code -eq $familyKey) { return $row }
    }
    return $null
}
function Get-QuotaRemaining {
    param($Row)
    if ($null -eq $Row) { return $null }
    return ([int]$Row.limit - [int]$Row.currentValue)
}
function Get-RegionCandidates {
    param([string]$Region,[switch]$FourGB)

    Write-Host "`n[$Region] Consultando SKU compatibles..." -ForegroundColor Cyan
    $prefix = if ($FourGB) { 'Standard_B2' } else { 'Standard_D2' }
    $skuArgs = @('vm','list-skus','--location',$Region,'--resource-type','virtualMachines','--size',$prefix,'--output','json','--only-show-errors')
    $skuText = Invoke-AzChecked -Arguments $skuArgs
    if ([string]::IsNullOrWhiteSpace($skuText)) { Write-Host '  Azure devolvió una lista vacía.' -ForegroundColor Yellow; return @() }
    $skus = @($skuText | ConvertFrom-Json)
    Write-Host ('  SKU devueltos por Azure: {0}' -f $skus.Count)
    if ($skus.Count -eq 0) { return @() }

    Write-Host "  Consultando cuota regional y familiar..." -ForegroundColor DarkCyan
    $usage = @(Invoke-AzJson @('vm','list-usage','--location',$Region,'--output','json'))
    $totalRow = $usage | Where-Object {
        (Normalize-Key ([string]$_.name.localizedValue)) -eq 'totalregionalvcpus'
    } | Select-Object -First 1
    $totalRemaining = Get-QuotaRemaining $totalRow
    if ($null -eq $totalRemaining) {
        Write-Warning "  No se encontró Total Regional vCPUs en $Region."
        return @()
    }
    Write-Host ('  Cuota regional libre: {0} vCPU' -f $totalRemaining)

    $found = New-Object System.Collections.Generic.List[object]
    foreach ($sku in $skus) {
        if ([string]$sku.resourceType -and [string]$sku.resourceType -ne 'virtualMachines') { continue }
        $name = [string]$sku.name
        if ($FourGB -and $name -notmatch '^Standard_B2') { continue }
        if (-not $FourGB -and $name -notmatch '^Standard_D2') { continue }

        $cpuText = Get-CapabilityValue -Sku $sku -CapabilityName 'vCPUs'
        $memoryText = Get-CapabilityValue -Sku $sku -CapabilityName 'MemoryGB'
        $archText = Get-CapabilityValue -Sku $sku -CapabilityName 'CpuArchitectureType'
        if (!$cpuText -or !$memoryText) { continue }
        $cpu = 0
        $memory = 0.0
        if (-not [int]::TryParse($cpuText,[ref]$cpu)) { continue }
        if (-not [double]::TryParse($memoryText,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$memory)) { continue }
        if ($cpu -ne 2) { continue }
        if ($FourGB) {
            if ($memory -lt 4.0) { continue }
        } else {
            if ($memory -lt 8.0) { continue }
        }
        if ($archText -and $archText -notmatch '(?i)x64|x86|amd64') { continue }

        $restrictions = @($sku.restrictions)
        $blocked = @($restrictions | Where-Object {
            [string]$_.type -eq 'Location' -or [string]$_.reasonCode -eq 'NotAvailableForSubscription'
        })
        if ($blocked.Count -gt 0) { continue }

        $family = [string]$sku.family
        if ([string]::IsNullOrWhiteSpace($family)) { continue }
        $familyQuota = Get-QuotaRow -Usage $usage -Family $family
        if ($null -eq $familyQuota) {
            Write-Host "  Omitido $name : no se pudo asociar cuota familiar ($family)." -ForegroundColor DarkYellow
            continue
        }
        $familyRemaining = Get-QuotaRemaining $familyQuota
        if ($totalRemaining -lt $cpu -or $familyRemaining -lt $cpu) { continue }

        $found.Add([pscustomobject]@{
            Name = $name
            Family = $family
            Vcpus = $cpu
            MemoryGB = $memory
            Region = $Region
            TotalVcpuRemaining = $totalRemaining
            FamilyVcpuRemaining = $familyRemaining
            Tier = if ($memory -ge 8.0) { '8GB' } else { '4GB' }
        })
    }
    return @($found.ToArray())
}
function Ensure-NsgRule {
    param([string]$RuleName,[int]$Priority,[string]$Source,[string]$Port,[string]$Description)
    $show = Invoke-AzRaw @('network','nsg','rule','show','--resource-group',$ResourceGroup,'--nsg-name','nsg-redsolidaria','--name',$RuleName,'--output','json')
    if ($show.ExitCode -eq 0) {
        Invoke-AzChecked @('network','nsg','rule','update','--resource-group',$ResourceGroup,'--nsg-name','nsg-redsolidaria','--name',$RuleName,'--source-address-prefixes',$Source,'--destination-port-ranges',$Port,'--description',$Description,'--output','none') | Out-Null
    } else {
        Invoke-AzChecked @('network','nsg','rule','create','--resource-group',$ResourceGroup,'--nsg-name','nsg-redsolidaria','--name',$RuleName,'--priority',([string]$Priority),'--direction','Inbound','--access','Allow','--protocol','Tcp','--source-address-prefixes',$Source,'--source-port-ranges','*','--destination-address-prefixes','*','--destination-port-ranges',$Port,'--description',$Description,'--output','none') | Out-Null
    }
}

Write-Host '=== RED SOLIDARIA | APROVISIONAMIENTO AUTOMÁTICO AZURE ===' -ForegroundColor Cyan
Write-Host "Proyecto: $ProjectRoot"
Write-Host "Suscripción: $SubscriptionId"
Write-Host ('Regiones a explorar: {0}' -f ($Regions -join ', '))

# Account and provider checks.
Invoke-AzChecked @('account','set','--subscription',$SubscriptionId) | Out-Null
$account = Invoke-AzJson @('account','show','--output','json')
if ($account.id -ne $SubscriptionId -or $account.state -ne 'Enabled') { throw 'La suscripción no coincide o no está Enabled.' }
if ($TenantId -and $account.tenantId -ne $TenantId) { throw 'El Tenant ID activo no coincide con Azure for Students.' }
if ($account.name -notmatch '(?i)student') { throw "La suscripción activa se llama '$($account.name)'. Verifica que sea Azure for Students antes de crear recursos." }

foreach ($provider in @('Microsoft.Compute','Microsoft.Network')) {
    $state = (Invoke-AzChecked @('provider','show','--namespace',$provider,'--query','registrationState','--output','tsv')).Trim()
    if ($state -ne 'Registered') { throw "El proveedor $provider no está registrado (estado: $state)." }
}

# SSH source restriction.
if (!$SshSourceCidr) {
    try { $publicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 15).ToString().Trim() }
    catch { $publicIp = Read-Host 'No se detectó tu IPv4 pública; introdúcela sin /32' }
    $SshSourceCidr = "$publicIp/32"
}
if ($SshSourceCidr -notmatch '^\d{1,3}(?:\.\d{1,3}){3}/32$') { throw 'SshSourceCidr debe ser una IPv4/32.' }
$sshIpText = $SshSourceCidr.Substring(0,$SshSourceCidr.Length - 3)
$sshIp = $null
if (-not [Net.IPAddress]::TryParse($sshIpText,[ref]$sshIp) -or $sshIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'La IPv4 usada para SSH no es válida.' }

# Automatic discovery: prefer 8 GB (D2), then try B2 8 GB; optional 4 GB fallback.
$selected = $null
$selectedRegion = $null
$scanErrors = New-Object System.Collections.Generic.List[string]
foreach ($region in $Regions) {
    try {
        $candidates = @(Get-RegionCandidates -Region $region)
        if ($candidates.Count -gt 0) {
            $preferredOrder = @('Standard_D2as_v4','Standard_D2s_v4','Standard_D2_v4','Standard_D2s_v3','Standard_D2_v3')
            $ranked = $candidates | Sort-Object @{Expression={ $idx = [Array]::IndexOf($preferredOrder,[string]$_.Name); if ($idx -lt 0) { 999 } else { $idx } }},Name
            $selected = $ranked | Select-Object -First 1
            $selectedRegion = $region
            break
        }
    } catch {
        $scanErrors.Add("$region (D2): $($_.Exception.Message)")
        Write-Warning "No se pudo consultar D2 en $region: $($_.Exception.Message)"
    }
}

# Query B2 family SKUs only if D2 scans returned none. First prefer 8 GB B2ms.
if (!$selected) {
    foreach ($region in $Regions) {
        try {
            Write-Host "`n[$region] Consultando familia B2..." -ForegroundColor Cyan
            $bText = Invoke-AzChecked @('vm','list-skus','--location',$region,'--resource-type','virtualMachines','--size','Standard_B2','--output','json','--only-show-errors')
            $bSkus = @($bText | ConvertFrom-Json)
            if ($bSkus.Count -eq 0) { continue }
            $usage = @(Invoke-AzJson @('vm','list-usage','--location',$region,'--output','json'))
            $totalRow = $usage | Where-Object { (Normalize-Key ([string]$_.name.localizedValue)) -eq 'totalregionalvcpus' } | Select-Object -First 1
            $totalRemaining = Get-QuotaRemaining $totalRow
            foreach ($sku in $bSkus) {
                if ([string]$sku.name -notmatch '^Standard_B2') { continue }
                $cpuText = Get-CapabilityValue $sku 'vCPUs'
                $memText = Get-CapabilityValue $sku 'MemoryGB'
                $archText = Get-CapabilityValue $sku 'CpuArchitectureType'
                $cpu = 0; $memory = 0.0
                if (!$cpuText -or !$memText -or -not [int]::TryParse($cpuText,[ref]$cpu) -or -not [double]::TryParse($memText,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$memory)) { continue }
                if ($cpu -ne 2 -or $memory -lt 8.0) { continue }
                if ($archText -and $archText -notmatch '(?i)x64|x86|amd64') { continue }
                if (@($sku.restrictions | Where-Object { $_.type -eq 'Location' -or $_.reasonCode -eq 'NotAvailableForSubscription' }).Count -gt 0) { continue }
                $familyQuota = Get-QuotaRow -Usage $usage -Family ([string]$sku.family)
                $familyRemaining = Get-QuotaRemaining $familyQuota
                if ($null -eq $totalRemaining -or $totalRemaining -lt 2 -or $null -eq $familyRemaining -or $familyRemaining -lt 2) { continue }
                $selected = [pscustomobject]@{ Name=[string]$sku.name; Family=[string]$sku.family; Vcpus=2; MemoryGB=$memory; Region=$region; TotalVcpuRemaining=$totalRemaining; FamilyVcpuRemaining=$familyRemaining; Tier='8GB' }
                $selectedRegion = $region
                break
            }
            if ($selected) { break }
        } catch {
            $scanErrors.Add("$region (B2): $($_.Exception.Message)")
            Write-Warning "No se pudo consultar B2 en $region: $($_.Exception.Message)"
        }
    }
}

# Last-resort 4-GB B2s only when explicitly allowed.
if (!$selected -and $Allow4GBFallback) {
    foreach ($region in $Regions) {
        try {
            Write-Host "`n[$region] Buscando B2 de 4 GB (contingencia)..." -ForegroundColor Yellow
            $bText = Invoke-AzChecked @('vm','list-skus','--location',$region,'--resource-type','virtualMachines','--size','Standard_B2','--output','json','--only-show-errors')
            $bSkus = @($bText | ConvertFrom-Json)
            $usage = @(Invoke-AzJson @('vm','list-usage','--location',$region,'--output','json'))
            $totalRow = $usage | Where-Object { (Normalize-Key ([string]$_.name.localizedValue)) -eq 'totalregionalvcpus' } | Select-Object -First 1
            $totalRemaining = Get-QuotaRemaining $totalRow
            foreach ($sku in $bSkus) {
                if ([string]$sku.name -ne 'Standard_B2s') { continue }
                $cpuText = Get-CapabilityValue $sku 'vCPUs'; $memText = Get-CapabilityValue $sku 'MemoryGB'
                $cpu = 0; $memory = 0.0
                if (!$cpuText -or !$memText -or -not [int]::TryParse($cpuText,[ref]$cpu) -or -not [double]::TryParse($memText,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$memory)) { continue }
                if ($cpu -ne 2 -or $memory -lt 4.0 -or $null -eq $totalRemaining -or $totalRemaining -lt 2) { continue }
                $familyQuota = Get-QuotaRow -Usage $usage -Family ([string]$sku.family)
                $familyRemaining = Get-QuotaRemaining $familyQuota
                if ($null -eq $familyRemaining -or $familyRemaining -lt 2) { continue }
                if (@($sku.restrictions | Where-Object { $_.type -eq 'Location' -or $_.reasonCode -eq 'NotAvailableForSubscription' }).Count -gt 0) { continue }
                $selected = [pscustomobject]@{ Name='Standard_B2s'; Family=[string]$sku.family; Vcpus=2; MemoryGB=$memory; Region=$region; TotalVcpuRemaining=$totalRemaining; FamilyVcpuRemaining=$familyRemaining; Tier='4GB' }
                $selectedRegion = $region
                break
            }
            if ($selected) { break }
        } catch {
            $scanErrors.Add("$region (B2s): $($_.Exception.Message)")
            Write-Warning "No se pudo consultar B2s en $region: $($_.Exception.Message)"
        }
    }
}

if (!$selected) {
    Write-Host 'No se encontró una VM candidata en las regiones consultadas.' -ForegroundColor Red
    if ($scanErrors.Count -gt 0) { $scanErrors | ForEach-Object { Write-Host $_ -ForegroundColor Yellow } }
    throw 'Azure no devolvió un SKU x64 compatible con las cuotas en ninguna región explorada. No se creó ningún recurso.'
}

$VmSize = [string]$selected.Name
$Location = [string]$selectedRegion
$is4GB = ([double]$selected.MemoryGB -lt 8.0)
$mssqlMemory = if ($is4GB) { 2048 } else { 3072 }
$mssqlContainer = if ($is4GB) { '3g' } else { '4g' }

Write-Host "`n=== SKU SELECCIONADO AUTOMÁTICAMENTE ===" -ForegroundColor Green
$selected | Format-List
Write-Host "MSSQL_MEMORY_LIMIT_MB: $mssqlMemory"
Write-Host "MSSQL_CONTAINER_MEMORY_LIMIT: $mssqlContainer"
Write-Host 'La VM usará Ubuntu 22.04 x64, disco SSD administrado de 64 GB.'
Write-Host 'Puertos públicos: SSH limitado a tu IPv4, 80 y 443. SQL 1433 permanecerá cerrado.'
Write-Host 'Los créditos Azure se consumirán mientras la VM y otros recursos facturables existan.' -ForegroundColor Yellow
Write-Host 'Comprueba tu saldo antes de autorizar: https://www.microsoftazuresponsorships.com/Balance' -ForegroundColor Yellow
if ($is4GB) {
    Write-Warning 'Solo se encontró una opción de 4 GB. Es una contingencia y tendrá menos margen para SQL Server y Angular.'
    $confirmation = Read-Host 'Escribe CREAR4GB para aceptar esta VM reducida'
    if ($confirmation -cne 'CREAR4GB') { throw 'Aprovisionamiento 4 GB cancelado.' }
} else {
    $confirmation = Read-Host 'Escribe CREAR para crear la VM usando tus créditos Azure for Students'
    if ($confirmation -cne 'CREAR') { throw 'Aprovisionamiento cancelado.' }
}

# Create SSH key.
foreach ($tool in @('ssh','ssh-keygen')) { if (!(Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Falta OpenSSH Client: $tool" } }
$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$keyPath = Join-Path $sshDir 'redsolidaria_azure_ed25519'
$pubPath = "$keyPath.pub"
if (!(Test-Path $keyPath)) {
    $keygen = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
    $k = Invoke-RSNative -FilePath $keygen -ArgumentList @('-t','ed25519','-C','red-solidaria-azure','-N','','-f',$keyPath)
    if ($k.ExitCode -ne 0) { throw ('No se pudo generar la llave SSH: ' + $k.StdErr) }
}
if (!(Test-Path $pubPath)) { throw 'No se encontró la llave SSH pública.' }
if (Get-Command icacls.exe -ErrorAction SilentlyContinue) {
    $acl = Invoke-RSNative -FilePath (Get-Command icacls.exe).Source -ArgumentList @($keyPath,'/inheritance:r','/grant:r',"$($env:USERNAME):(R,W)")
    if ($acl.ExitCode -ne 0) { throw ('No se pudieron proteger los permisos de la llave: ' + $acl.StdErr) }
}

# Create/reuse Azure infrastructure.
$groupExists = (Invoke-AzChecked @('group','exists','--name',$ResourceGroup,'--output','tsv')).Trim()
if ($groupExists -ne 'true') {
    Invoke-AzChecked @('group','create','--name',$ResourceGroup,'--location',$Location,'--tags','project=redsolidaria','environment=school','--output','none') | Out-Null
}
$nsgName='nsg-redsolidaria'; $vnetName='vnet-redsolidaria'; $subnetName='subnet-app'; $publicIpName='pip-redsolidaria'
$nsgShow=Invoke-AzRaw @('network','nsg','show','--resource-group',$ResourceGroup,'--name',$nsgName,'--output','json')
if ($nsgShow.ExitCode -ne 0) { Invoke-AzChecked @('network','nsg','create','--resource-group',$ResourceGroup,'--name',$nsgName,'--location',$Location,'--output','none') | Out-Null }
Ensure-NsgRule -RuleName 'Allow-SSH-My-IP' -Priority 100 -Source $SshSourceCidr -Port '22' -Description 'SSH only from provisioning IPv4'
Ensure-NsgRule -RuleName 'Allow-HTTP' -Priority 110 -Source 'Internet' -Port '80' -Description 'HTTP for HTTPS certificate validation'
Ensure-NsgRule -RuleName 'Allow-HTTPS' -Priority 120 -Source 'Internet' -Port '443' -Description 'Public HTTPS application'

$vnetShow=Invoke-AzRaw @('network','vnet','show','--resource-group',$ResourceGroup,'--name',$vnetName,'--output','json')
if ($vnetShow.ExitCode -ne 0) {
    Invoke-AzChecked @('network','vnet','create','--resource-group',$ResourceGroup,'--name',$vnetName,'--location',$Location,'--address-prefixes','10.41.0.0/16','--subnet-name',$subnetName,'--subnet-prefixes','10.41.1.0/24','--output','none') | Out-Null
}
$dnsLabel=('redsolidaria-' + [guid]::NewGuid().ToString('N').Substring(0,8)).ToLowerInvariant()
$ipShow=Invoke-AzRaw @('network','public-ip','show','--resource-group',$ResourceGroup,'--name',$publicIpName,'--output','json')
if ($ipShow.ExitCode -ne 0) {
    Invoke-AzChecked @('network','public-ip','create','--resource-group',$ResourceGroup,'--name',$publicIpName,'--location',$Location,'--version','IPv4','--sku','Standard','--allocation-method','Static','--dns-name',$dnsLabel,'--output','none') | Out-Null
}

$existingVm=Invoke-AzRaw @('vm','show','--resource-group',$ResourceGroup,'--name',$VmName,'--output','json')
if ($existingVm.ExitCode -eq 0) {
    $vmDoc=$existingVm.StdOut | ConvertFrom-Json
    $actualSize=[string]$vmDoc.hardwareProfile.vmSize
    if ($actualSize -ne $VmSize) { throw "Ya existe $VmName con tamaño $actualSize, pero la selección automática eligió $VmSize. No se modificará la VM existente." }
} else {
    Write-Host "`nCreando VM $VmName ($VmSize) en $Location..." -ForegroundColor Cyan
    Invoke-AzChecked @('vm','create','--resource-group',$ResourceGroup,'--name',$VmName,'--location',$Location,'--size',$VmSize,'--image','Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest','--admin-username','azureuser','--ssh-key-values',("@"+$pubPath),'--vnet-name',$vnetName,'--subnet',$subnetName,'--nsg',$nsgName,'--public-ip-address',$publicIpName,'--os-disk-size-gb','64','--storage-sku','StandardSSD_LRS','--security-type','Standard','--tags','project=redsolidaria','purpose=school-demo','--output','none') -ShowOutput | Out-Null
}

# Wait for provisioning to complete and retrieve public endpoint.
$vmReady=$false
for ($i=1; $i -le 30; $i++) {
    $state=Invoke-AzJson @('vm','get-instance-view','--resource-group',$ResourceGroup,'--name',$VmName,'--output','json')
    $statuses=@($state.instanceView.statuses)
    $provision=$statuses | Where-Object { $_.code -like 'ProvisioningState/*' } | Select-Object -First 1
    Write-Host "VM provisioning $i/30 : $($provision.displayStatus)"
    if ($provision.code -eq 'ProvisioningState/succeeded') { $vmReady=$true; break }
    if ($provision.code -eq 'ProvisioningState/failed') { throw 'Azure reportó ProvisioningState/failed. Consulta el Resource Group antes de reintentar.' }
    Start-Sleep -Seconds 10
}
if (!$vmReady) { throw "La VM sigue aprovisionándose. No la recrees. Consulta: az vm show -g $ResourceGroup -n $VmName -d -o table" }

$publicIpDoc=Invoke-AzJson @('network','public-ip','show','--resource-group',$ResourceGroup,'--name',$publicIpName,'--output','json')
$serverIp=[string]$publicIpDoc.ipAddress
$domain=[string]$publicIpDoc.dnsSettings.fqdn
if (!$serverIp -or !$domain) { throw 'La VM existe, pero Azure todavía no devuelve IP/FQDN. No vuelvas a crearla; vuelve a consultar public-ip show.' }

# Save reusable config outside the repository.
function Quote-PS([string]$Value) { return "'" + $Value.Replace("'","''") + "'" }
$configDir=Split-Path $ConfigPath -Parent
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
$cfg=@(
    ('$ProjectRoot = ' + (Quote-PS $ProjectRoot)),
    ('$Owner = ' + (Quote-PS 'JBranez')),
    ('$Repository = ' + (Quote-PS 'red-solidaria')),
    ('$RepoSlug = ' + (Quote-PS 'JBranez/red-solidaria')),
    ('$SubscriptionId = ' + (Quote-PS $account.id)),
    ('$TenantId = ' + (Quote-PS $account.tenantId)),
    ('$SubscriptionName = ' + (Quote-PS $account.name)),
    ('$AzureResourceGroup = ' + (Quote-PS $ResourceGroup)),
    ('$AzureVmName = ' + (Quote-PS $VmName)),
    ('$AzureLocation = ' + (Quote-PS $Location)),
    ('$AzureVmSize = ' + (Quote-PS $VmSize)),
    ('$ServerIp = ' + (Quote-PS $serverIp)),
    ('$SshUser = ' + (Quote-PS 'azureuser')),
    ('$SshPort = 22'),
    ('$InitialKeyPath = ' + (Quote-PS $keyPath)),
    ('$Domain = ' + (Quote-PS $domain)),
    ('$SshSourceCidr = ' + (Quote-PS $SshSourceCidr)),
    ('$MssqlMemoryLimitMB = ' + [string]$mssqlMemory),
    ('$MssqlContainerMemoryLimit = ' + (Quote-PS $mssqlContainer))
)
[IO.File]::WriteAllLines($ConfigPath,$cfg,[Text.UTF8Encoding]::new($true))
$summaryPath=Join-Path $configDir 'RedSolidaria-Azure-VM.json'
[pscustomobject]@{subscriptionId=$account.id;tenantId=$account.tenantId;subscriptionName=$account.name;resourceGroup=$ResourceGroup;vmName=$VmName;location=$Location;vmSize=$VmSize;memoryGB=$selected.MemoryGB;ip=$serverIp;fqdn=$domain;sshUser='azureuser';sshKeyPath=$keyPath;sshSourceCidr=$SshSourceCidr;createdAt=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "`n=== VM AZURE CREADA Y CONFIGURACIÓN GUARDADA ===" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroup"
Write-Host "VM: $VmName"
Write-Host "SKU: $VmSize ($($selected.MemoryGB) GB RAM, 2 vCPU)"
Write-Host "Región: $Location"
Write-Host "IP: $serverIp"
Write-Host "Dominio: $domain"
Write-Host 'Usuario SSH: azureuser'
Write-Host "Llave privada: $keyPath"
Write-Host "Configuración: $ConfigPath"
Write-Host "Resumen: $summaryPath"
Write-Host 'SQL Server 1433 NO está abierto en el NSG.' -ForegroundColor Green
Write-Host 'Siguiente: fusionar Day2 y Day3, esperar CI y ejecutar Deploy-RedSolidaria.ps1.' -ForegroundColor Yellow

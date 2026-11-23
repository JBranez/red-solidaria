#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Location = 'eastus2',
    [string]$OutputPath = (Join-Path $HOME 'Documents\RedSolidariaAzureReports\Preflight-eastus2.json'),
    [ValidateRange(15,300)][int]$TimeoutSeconds = 60,
    [string]$ExpectedSubscriptionId = '09054927-5863-4fae-acf8-558d72a271ac',
    [string]$ExpectedTenantId = '966233e3-0b75-4c77-877a-d9b70a69ea01'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-ObjectProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory=$true)][string]$PropertyName
    )
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Convert-JsonToArray {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$JsonText,
        [string]$Context = 'JSON'
    )
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return ,@() }
    try {
        $parsed = ConvertFrom-Json -InputObject $JsonText -ErrorAction Stop
    }
    catch {
        throw ("No se pudo interpretar la respuesta {0}: {1}" -f $Context,$_.Exception.Message)
    }
    if ($null -eq $parsed) { return ,@() }
    if ($parsed -is [System.Array]) { return ,$parsed }
    return ,@($parsed)
}

function Convert-ToNumberOrNull {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $number = 0.0
    $ok = [double]::TryParse(
        [string]$Value,
        [System.Globalization.NumberStyles]::Any,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$number
    )
    if ($ok) { return $number }
    return $null
}

function Invoke-AzJobWithTimeout {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Description,
        [ValidateRange(15,300)][int]$Timeout = 60
    )

    Write-Host ("  -> {0} (límite {1}s)" -f $Description,$Timeout) -ForegroundColor DarkCyan
    $job = Start-Job -ScriptBlock {
        param($ArgsForAz)
        $ErrorActionPreference = 'Continue'
        $output = @(& az @ArgsForAz 2>&1)
        $exitCode = $LASTEXITCODE
        $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        [pscustomobject]@{
            ExitCode = [int]$exitCode
            Text = [string]$text
        }
    } -ArgumentList (,$Arguments)

    try {
        $completed = Wait-Job -Job $job -Timeout $Timeout
        if ($null -eq $completed) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
            throw ("Tiempo agotado después de {0}s al ejecutar az {1}" -f $Timeout,($Arguments -join ' '))
        }

        $received = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        $result = $null
        foreach ($entry in $received) {
            if ($null -ne $entry -and $null -ne $entry.PSObject.Properties['ExitCode']) {
                $result = $entry
            }
        }
        if ($null -eq $result) {
            $reason = ''
            if ($job.ChildJobs.Count -gt 0 -and $null -ne $job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = [string]$job.ChildJobs[0].JobStateInfo.Reason
            }
            throw ("Azure CLI no devolvió un resultado para '{0}'. {1}" -f $Description,$reason)
        }
        if ([int]$result.ExitCode -ne 0) {
            throw ("Azure CLI devolvió código {0} para '{1}'. {2}" -f $result.ExitCode,$Description,$result.Text)
        }
        return [string]$result.Text
    }
    finally {
        if ($null -ne $job) {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host '=== RED SOLIDARIA | PREFLIGHT AZURE FIX2 ===' -ForegroundColor Cyan
Write-Host 'Solo lectura: no crea recursos ni consume crédito.' -ForegroundColor Green
Write-Host ("Región: {0}" -f $Location)
Write-Host ("Timeout por consulta: {0} segundos" -f $TimeoutSeconds)

# 1. Suscripción
Write-Host "`n[1/3] Comprobando suscripción..." -ForegroundColor Cyan
$accountText = Invoke-AzJobWithTimeout -Arguments @('account','show','--output','json','--only-show-errors') -Description 'consultar cuenta' -Timeout $TimeoutSeconds
$account = ConvertFrom-Json -InputObject $accountText -ErrorAction Stop
$accountId = [string](Get-ObjectProperty $account 'id')
$tenantId = [string](Get-ObjectProperty $account 'tenantId')
$accountState = [string](Get-ObjectProperty $account 'state')
$accountName = [string](Get-ObjectProperty $account 'name')

if ($accountState -ne 'Enabled') { throw ("La suscripción no está Enabled: {0}" -f $accountState) }
if ($ExpectedSubscriptionId -and $accountId -ne $ExpectedSubscriptionId) {
    throw ("La suscripción activa no es la esperada. Actual: {0}; esperada: {1}" -f $accountId,$ExpectedSubscriptionId)
}
if ($ExpectedTenantId -and $tenantId -ne $ExpectedTenantId) {
    throw ("El Tenant ID activo no coincide. Actual: {0}; esperado: {1}" -f $tenantId,$ExpectedTenantId)
}
Write-Host ("Suscripción: {0}" -f $accountName) -ForegroundColor Green
Write-Host ("Subscription ID: {0}" -f $accountId)
Write-Host ("Tenant ID: {0}" -f $tenantId)
Write-Host ("Estado: {0}" -f $accountState)

# 2. SKU
Write-Host "`n[2/3] Consultando tamaños de VM x64..." -ForegroundColor Cyan
$skuNames = @('Standard_B2ms','Standard_D2as_v5','Standard_D2s_v5','Standard_B2s')
$skuRows = New-Object System.Collections.Generic.List[object]
$skuIndex = 0
foreach ($size in $skuNames) {
    $skuIndex++
    Write-Host ("`n[{0}/{1}] SKU {2}" -f $skuIndex,$skuNames.Count,$size) -ForegroundColor Yellow
    try {
        $skuText = Invoke-AzJobWithTimeout -Arguments @('vm','list-skus','--location',$Location,'--resource-type','virtualMachines','--size',$size,'--all','--output','json','--only-show-errors') -Description ("consultar {0} en {1}" -f $size,$Location) -Timeout $TimeoutSeconds
        $items = Convert-JsonToArray -JsonText $skuText -Context ("SKU {0}" -f $size)
        $item = $null
        foreach ($candidate in $items) {
            $candidateName = [string](Get-ObjectProperty $candidate 'name')
            if ($candidateName -eq $size) { $item = $candidate; break }
        }

        if ($null -eq $item) {
            $skuRows.Add([pscustomobject]@{Size=$size;vCPU='';RAM_GB='';Family='';Status='No listado en la región';Restrictions=''})
            Write-Host 'No aparece en el resultado de Azure.' -ForegroundColor Yellow
            continue
        }

        $cpu = ''
        $ram = ''
        $capabilities = Get-ObjectProperty $item 'capabilities'
        foreach ($capability in @($capabilities)) {
            $capName = [string](Get-ObjectProperty $capability 'name')
            $capValue = [string](Get-ObjectProperty $capability 'value')
            if ($capName -eq 'vCPUs') { $cpu = $capValue }
            if ($capName -eq 'MemoryGB') { $ram = $capValue }
        }

        $family = [string](Get-ObjectProperty $item 'family')
        $restrictionParts = New-Object System.Collections.Generic.List[string]
        $restrictions = Get-ObjectProperty $item 'restrictions'
        foreach ($restriction in @($restrictions)) {
            if ($null -eq $restriction) { continue }
            $rtype = [string](Get-ObjectProperty $restriction 'type')
            $reason = [string](Get-ObjectProperty $restriction 'reasonCode')
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'ReasonNotProvided' }
            $restrictionParts.Add(("{0}:{1}" -f $rtype,$reason))
        }
        $restrictionText = 'Sin restricciones reportadas'
        if ($restrictionParts.Count -gt 0) { $restrictionText = $restrictionParts -join '; ' }

        $status = 'Listado'
        if ($restrictionParts.Count -gt 0) { $status = 'Listado con restricciones' }
        $skuRows.Add([pscustomobject]@{Size=$size;vCPU=$cpu;RAM_GB=$ram;Family=$family;Status=$status;Restrictions=$restrictionText})
        Write-Host ("Encontrado: {0} vCPU; {1} GB RAM; familia {2}" -f $cpu,$ram,$family) -ForegroundColor Green
        if ($restrictionParts.Count -gt 0) { Write-Host ("Restricciones: {0}" -f $restrictionText) -ForegroundColor Yellow }
    }
    catch {
        $message = $_.Exception.Message
        $skuRows.Add([pscustomobject]@{Size=$size;vCPU='';RAM_GB='';Family='';Status='Error/timeout';Restrictions=$message})
        Write-Host ("No se pudo consultar {0}: {1}" -f $size,$message) -ForegroundColor Red
    }
}

Write-Host "`nResumen de SKUs:" -ForegroundColor Cyan
foreach ($row in $skuRows) {
    Write-Host ("{0,-22} CPU={1,-3} RAM={2,-5} Familia={3,-22} Estado={4}" -f $row.Size,$row.vCPU,$row.RAM_GB,$row.Family,$row.Status)
    if ($row.Restrictions -ne 'Sin restricciones reportadas' -and $row.Restrictions -ne '') {
        Write-Host ("  {0}" -f $row.Restrictions) -ForegroundColor Yellow
    }
}

# 3. Cuotas: parser defensivo; nunca asumir que todo objeto tiene .name
Write-Host "`n[3/3] Consultando cuotas regionales..." -ForegroundColor Cyan
$quotaRows = New-Object System.Collections.Generic.List[object]
$quotaError = ''
try {
    $usageText = Invoke-AzJobWithTimeout -Arguments @('vm','list-usage','--location',$Location,'--output','json','--only-show-errors') -Description ("consultar cuotas de {0}" -f $Location) -Timeout $TimeoutSeconds
    $usageItems = Convert-JsonToArray -JsonText $usageText -Context 'cuotas regionales'

    foreach ($usageItem in $usageItems) {
        if ($null -eq $usageItem) { continue }
        $nameObject = Get-ObjectProperty $usageItem 'name'
        $code = ''
        $localized = ''
        if ($nameObject -is [string]) {
            $code = [string]$nameObject
        }
        else {
            $code = [string](Get-ObjectProperty $nameObject 'value')
            $localized = [string](Get-ObjectProperty $nameObject 'localizedValue')
        }
        if ([string]::IsNullOrWhiteSpace($localized)) {
            $localized = [string](Get-ObjectProperty $usageItem 'localizedValue')
        }
        $resourceType = [string](Get-ObjectProperty $usageItem 'resourceType')
        $unit = [string](Get-ObjectProperty $usageItem 'unit')
        $currentValue = Get-ObjectProperty $usageItem 'currentValue'
        $limitValue = Get-ObjectProperty $usageItem 'limit'

        $isRelevant = $false
        if ($code -match '(?i)cores|standard.*family|lowpriority') { $isRelevant = $true }
        if ($localized -match '(?i)cores|vCPU|family') { $isRelevant = $true }
        if ($isRelevant) {
            $currentNumber = Convert-ToNumberOrNull $currentValue
            $limitNumber = Convert-ToNumberOrNull $limitValue
            $available = ''
            if ($null -ne $currentNumber -and $null -ne $limitNumber) {
                $available = [Math]::Max(0,($limitNumber - $currentNumber))
            }
            $quotaRows.Add([pscustomobject]@{
                Quota = $localized
                Code = $code
                ResourceType = $resourceType
                Unit = $unit
                Current = $currentValue
                Limit = $limitValue
                Available = $available
            })
        }
    }

    Write-Host ("Objetos de cuota recibidos: {0}" -f $usageItems.Count) -ForegroundColor Green
    Write-Host ("Cuotas relevantes identificadas: {0}" -f $quotaRows.Count) -ForegroundColor Green
    if ($quotaRows.Count -gt 0) {
        foreach ($q in $quotaRows) {
            Write-Host ("{0} | código={1} | actual={2} | límite={3} | disponible={4}" -f $q.Quota,$q.Code,$q.Current,$q.Limit,$q.Available)
        }
    }
    else {
        Write-Host 'Azure respondió, pero no se identificaron cuotas con nombres reconocidos. Se conservará la respuesta sin bloquear el informe.' -ForegroundColor Yellow
    }
}
catch {
    $quotaError = $_.Exception.Message
    Write-Host ("No se pudo consultar la cuota: {0}" -f $quotaError) -ForegroundColor Yellow
}

# Informe JSON robusto
$parent = Split-Path -Parent $OutputPath
if (!(Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$report = [pscustomobject]@{
    SubscriptionName = $accountName
    SubscriptionId = $accountId
    TenantId = $tenantId
    State = $accountState
    Location = $Location
    CapturedAt = (Get-Date).ToString('o')
    SkuResults = @($skuRows.ToArray())
    Quotas = @($quotaRows.ToArray())
    QuotaQueryError = $quotaError
    CanProvision = $false
    Note = 'Este informe no autoriza por sí solo el aprovisionamiento. Confirmar cuota regional, cuota de familia, crédito y restricciones en Azure Portal.'
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host "`nInforme guardado: $OutputPath" -ForegroundColor Green
Write-Host 'PRE-FLIGHT TERMINADO. No se creó ninguna VM ni se consumió crédito.' -ForegroundColor Green
Write-Host 'El aprovisionamiento sigue bloqueado hasta revisar SKU, cuota y crédito.' -ForegroundColor Yellow

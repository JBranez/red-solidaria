#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Owner,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Repository,
    [Parameter(Mandatory = $true)][ValidateSet('Day2','Day3')][string]$Phase
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$script:RepoSlug = '{0}/{1}' -f $Owner, $Repository
$script:GhExe = (Get-Command gh.exe -ErrorAction Stop).Source

function Invoke-Gh {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $r = Invoke-RSNative -FilePath $script:GhExe -ArgumentList $Arguments
    if ($r.ExitCode -ne 0) {
        throw ('gh {0} falló (código {1}). {2}' -f ($Arguments -join ' '),$r.ExitCode,$r.StdErr)
    }
    return $r.StdOut
}

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $raw = Invoke-Gh -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-PhaseBranches {
    if ($Phase -eq 'Day2') {
        return @('feature/angular-frontend','feature/docker-platform','ops/vps-deployment')
    }
    return @('ci/github-actions','docs/technical-delivery')
}

function Get-PullRequestForBranch {
    param([Parameter(Mandatory = $true)][string]$Branch)
    $head = [uri]::EscapeDataString(($Owner + ':' + $Branch))
    $endpoint = 'repos/{0}/pulls?state=all&head={1}&base=main&per_page=100' -f $script:RepoSlug, $head
    $items = @(Invoke-GhJson -Arguments @('api', $endpoint))
    if ($items.Count -eq 0) {
        throw ('No se encontró una PR para la rama esperada {0}. Publica primero la fase {1}.' -f $Branch, $Phase)
    }
    $open = @($items | Where-Object { $_.state -eq 'open' } | Sort-Object updated_at -Descending)
    if ($open.Count -gt 0) { return $open[0] }
    $merged = @($items | Where-Object { $null -ne $_.merged_at } | Sort-Object merged_at -Descending)
    if ($merged.Count -gt 0) { return $merged[0] }
    throw ('La PR de {0} está cerrada sin fusionar. Revisa GitHub antes de continuar.' -f $Branch)
}

function Test-PullRequestChecks {
    param(
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][int]$Number
    )
    $checkEndpoint = 'repos/{0}/commits/{1}/check-runs?per_page=100' -f $script:RepoSlug, $HeadSha
    $statusEndpoint = 'repos/{0}/commits/{1}/status' -f $script:RepoSlug, $HeadSha
    $checkDoc = Invoke-GhJson -Arguments @('api', $checkEndpoint)
    $statusDoc = Invoke-GhJson -Arguments @('api', $statusEndpoint)
    $runs = @($checkDoc.check_runs)
    $statuses = @($statusDoc.statuses)

    $badRuns = @($runs | Where-Object {
        $_.status -ne 'completed' -or $_.conclusion -notin @('success','neutral','skipped')
    })
    $badStatuses = @($statuses | Where-Object { $_.state -ne 'success' })

    if ($runs.Count -eq 0 -and $statuses.Count -eq 0) {
        Write-Host ('PR #{0}: GitHub todavía no registra checks. Se requiere revisión visual manual; las reglas de rama de GitHub siguen activas.' -f $Number) -ForegroundColor Yellow
        return $true
    }
    if ($badRuns.Count -gt 0 -or $badStatuses.Count -gt 0) {
        Write-Host ('PR #{0}: hay checks fallidos o pendientes.' -f $Number) -ForegroundColor Red
        foreach ($run in $badRuns) {
            Write-Host ('  Check: {0} | status={1} | conclusion={2}' -f $run.name,$run.status,$run.conclusion) -ForegroundColor Red
        }
        foreach ($status in $badStatuses) {
            Write-Host ('  Status: {0} | state={1}' -f $status.context,$status.state) -ForegroundColor Red
        }
        return $false
    }
    Write-Host ('PR #{0}: todos los checks reportados son satisfactorios.' -f $Number) -ForegroundColor Green
    return $true
}

Write-Host ('Merge seguro Red Solidaria — {0} — {1}' -f $Phase,$script:RepoSlug) -ForegroundColor Magenta
$null = Invoke-Gh -Arguments @('auth','status')
$repo = Invoke-GhJson -Arguments @('api',('repos/{0}' -f $script:RepoSlug))
if (-not $repo.allow_merge_commit) {
    throw 'El repositorio no permite merge commits. En GitHub abre Settings > General > Pull Requests y activa Allow merge commits.'
}

$branches = @(Get-PhaseBranches)
foreach ($branch in $branches) {
    $pr = Get-PullRequestForBranch -Branch $branch
    $number = [int]$pr.number

    if ($null -ne $pr.merged_at) {
        Write-Host ('PR #{0} ({1}) ya está fusionada; se omite.' -f $number,$branch) -ForegroundColor Green
        continue
    }

    $detail = $null
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        $detail = Invoke-GhJson -Arguments @('api',('repos/{0}/pulls/{1}' -f $script:RepoSlug,$number))
        if ($null -ne $detail.mergeable) { break }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $detail.mergeable) {
        throw ('GitHub no calculó mergeability para PR #{0}. Espera unos segundos y vuelve a ejecutar.' -f $number)
    }
    if ($detail.mergeable -ne $true) {
        throw ('PR #{0} tiene conflictos o no puede fusionarse. mergeable_state={1}.' -f $number,$detail.mergeable_state)
    }

    Write-Host ''
    Write-Host ('PR #{0} — {1}' -f $number,$detail.title) -ForegroundColor Cyan
    Write-Host $detail.html_url
    Write-Host ('Rama: {0} -> main | Commit: {1}' -f $branch,$detail.head.sha)

    $checksOk = Test-PullRequestChecks -HeadSha ([string]$detail.head.sha) -Number $number
    if (-not $checksOk) {
        throw ('PR #{0} no se fusionó porque tiene checks fallidos o pendientes.' -f $number)
    }

    Start-Process $detail.html_url
    $answer = Read-Host ('Revisa los archivos y escribe SI para fusionar PR #{0} (merge commit, conserva commits)' -f $number)
    if ($answer -cne 'SI') {
        Write-Warning ('PR #{0} se deja abierta. No continúes con la fase siguiente.' -f $number)
        continue
    }

    $mergeEndpoint = 'repos/{0}/pulls/{1}/merge' -f $script:RepoSlug,$number
    $mergeResult = Invoke-GhJson -Arguments @('api','-X','PUT',$mergeEndpoint,'-f','merge_method=merge')
    if (-not $mergeResult.merged) {
        throw ('GitHub rechazó la fusión de PR #{0}: {1}' -f $number,$mergeResult.message)
    }
    $verify = Invoke-GhJson -Arguments @('api',('repos/{0}/pulls/{1}' -f $script:RepoSlug,$number))
    if ($null -eq $verify.merged_at) {
        throw ('La API no confirma PR #{0} como fusionada. Verifica GitHub antes de reintentar.' -f $number)
    }
    Write-Host ('PR #{0} fusionada correctamente.' -f $number) -ForegroundColor Green
}

$pending = @()
foreach ($branch in $branches) {
    $pr = Get-PullRequestForBranch -Branch $branch
    if ($null -eq $pr.merged_at) { $pending += $branch }
}
if ($pending.Count -gt 0) {
    Write-Warning ('Faltan PR por fusionar: {0}. No avances a otra fase.' -f ($pending -join ', '))
    exit 2
}
Write-Host ('Fase {0} completa: todas sus PR están fusionadas.' -f $Phase) -ForegroundColor Green
Write-Host 'La siguiente fase ya puede publicarse.' -ForegroundColor Green

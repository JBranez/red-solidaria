#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+$')]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]+$')]
    [string]$Repository
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:RedSolidariaMergeVersion = '3.0'
$script:RepoSlug = "$Owner/$Repository"

function Invoke-NativeCommand {
    <#
      Run a native executable without merging stderr into PowerShell's error
      stream. This is compatible with Windows PowerShell 5.1, where gh.exe
      stderr can otherwise become NativeCommandError and terminate a script
      when $ErrorActionPreference = 'Stop'.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$ShowStderr
    )

    $stderrFile = Join-Path $env:TEMP ("rs-native-{0}.stderr" -f [guid]::NewGuid().ToString('N'))
    try {
        $stdoutLines = @(& $FilePath @Arguments 2> $stderrFile)
        $exitCode = $LASTEXITCODE
        $stdoutText = ($stdoutLines | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        $stderrText = ''
        if (Test-Path -LiteralPath $stderrFile) {
            $stderrText = Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
        }

        if ($ShowStderr -and -not [string]::IsNullOrWhiteSpace($stderrText)) {
            Write-Host $stderrText.TrimEnd()
        }

        if ($exitCode -ne 0) {
            $detail = @($stdoutText, $stderrText.Trim()) -join [Environment]::NewLine
            throw ("Comando fallido: {0} {1}`nCódigo: {2}`n{3}" -f $FilePath, ($Arguments -join ' '), $exitCode, $detail.Trim())
        }

        return $stdoutText
    }
    finally {
        if (Test-Path -LiteralPath $stderrFile) {
            Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$ShowStderr
    )
    $result = Invoke-NativeCommand -FilePath 'gh' -Arguments $Arguments -ShowStderr:$ShowStderr
    return $result
}

function Get-OpenPrNumbers {
    $raw = Invoke-Gh -Arguments @(
        'pr', 'list', '--repo', $script:RepoSlug,
        '--state', 'open', '--json', 'number',
        '--jq', '.[].number', '--limit', '100'
    )

    $numbers = @(
        foreach ($line in ($raw -split "`r?`n")) {
            $number = 0
            if ([int]::TryParse($line.Trim(), [ref]$number) -and $number -gt 0) {
                $number
            }
        }
    )
    return @($numbers | Sort-Object -Unique)
}

function Test-PrChecks {
    param(
        [Parameter(Mandatory = $true)][string]$HeadSha,
        [Parameter(Mandatory = $true)][string]$PrNumber
    )

    # Consultamos las APIs REST directamente. No usamos `gh pr checks`, cuyo
    # código de salida es 1 cuando no hay checks y cuyo stderr rompía Windows
    # PowerShell 5.1 con ErrorActionPreference=Stop.
    $checkRunsJson = Invoke-Gh -Arguments @(
        'api', ("repos/{0}/commits/{1}/check-runs?per_page=100" -f $script:RepoSlug, $HeadSha),
        '-X', 'GET'
    )
    $statusesJson = Invoke-Gh -Arguments @(
        'api', ("repos/{0}/commits/{1}/statuses?per_page=100" -f $script:RepoSlug, $HeadSha),
        '-X', 'GET'
    )

    $checkRunsResponse = $checkRunsJson | ConvertFrom-Json
    $statusContexts = @($statusesJson | ConvertFrom-Json)
    $checkRuns = @($checkRunsResponse.check_runs)

    $badRuns = @(
        $checkRuns | Where-Object {
            ([string]$_.status -ne 'completed') -or
            ([string]$_.conclusion -notin @('success', 'neutral', 'skipped'))
        }
    )
    $badStatuses = @(
        $statusContexts | Where-Object { [string]$_.state -ne 'success' }
    )

    if (($checkRuns.Count -eq 0) -and ($statusContexts.Count -eq 0)) {
        Write-Host "PR #${PrNumber}: GitHub no registra checks ni commit statuses para esta rama." -ForegroundColor Yellow
        Write-Host 'Esto NO es un fallo de CI. Se requiere tu revisión manual; las reglas de protección de GitHub seguirán aplicándose.' -ForegroundColor Yellow
        return $true
    }

    if (($badRuns.Count -gt 0) -or ($badStatuses.Count -gt 0)) {
        Write-Host "PR #${PrNumber}: se detectaron checks fallidos o todavía pendientes:" -ForegroundColor Red
        foreach ($run in $badRuns) {
            Write-Host ("  Check: {0} | status={1} | conclusion={2}" -f $run.name, $run.status, $run.conclusion) -ForegroundColor Red
        }
        foreach ($status in $badStatuses) {
            Write-Host ("  Status: {0} | state={1} | description={2}" -f $status.context, $status.state, $status.description) -ForegroundColor Red
        }
        return $false
    }

    Write-Host ("PR #{0}: {1} check run(s) y {2} commit status(es), todos satisfactorios." -f $PrNumber, $checkRuns.Count, $statusContexts.Count) -ForegroundColor Green
    return $true
}

# --- Preflight ---
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'No se encontró GitHub CLI. Instálalo con: winget install --id GitHub.cli -e'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'No se encontró Git. Instálalo con: winget install --id Git.Git -e'
}
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    throw 'La variable de entorno TEMP no está definida; no se puede capturar stderr de forma segura.'
}

Write-Host ("Merge-RedSolidariaPhase v{0}" -f $script:RedSolidariaMergeVersion) -ForegroundColor Magenta
Write-Host ("Comprobando sesión GitHub para {0} ..." -f $script:RepoSlug) -ForegroundColor Cyan
$null = Invoke-Gh -Arguments @('auth', 'status') -ShowStderr

# --merge requiere que el repositorio permita merge commits. Verificamos la
# configuración antes de pedir confirmación para evitar un rechazo posterior.
$repoSettingsJson = Invoke-Gh -Arguments @('api', ("repos/{0}" -f $script:RepoSlug))
$repoSettings = $repoSettingsJson | ConvertFrom-Json
if (-not [bool]$repoSettings.allow_merge_commit) {
    throw 'El repositorio no permite merge commits. En GitHub abre Settings > General > Pull Requests y activa Allow merge commits. Después vuelve a ejecutar este script.'
}

$repoRootRaw = Invoke-NativeCommand -FilePath 'git' -Arguments @('rev-parse', '--show-toplevel')
$repoRoot = $repoRootRaw.Trim()
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'No se pudo detectar la raíz Git. Ejecuta el script desde dentro del repositorio.'
}

$gitDirRaw = Invoke-NativeCommand -FilePath 'git' -Arguments @('rev-parse', '--git-dir')
$gitDir = $gitDirRaw.Trim()
if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
    $gitDir = Join-Path $repoRoot $gitDir
}
$statePath = Join-Path $gitDir 'redsolidaria-publish-state.json'
if (-not (Test-Path -LiteralPath $statePath)) {
    throw "No existe el estado local de publicación: $statePath. Comprueba que estás en el repositorio creado por Publish-RedSolidaria.ps1. No ejecutes Day1 otra vez."
}

$publishState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($publishState.Owner -ne $Owner -or $publishState.Repository -ne $Repository) {
    throw ("El estado local pertenece a {0}/{1}, no a {2}." -f $publishState.Owner, $publishState.Repository, $script:RepoSlug)
}

$numbers = @(Get-OpenPrNumbers)
if ($numbers.Count -eq 0) {
    Write-Host 'No hay Pull Requests abiertas.' -ForegroundColor Yellow
    exit 0
}

Write-Host ("Se encontraron {0} PR abiertas. Se procesarán una por una, en orden ascendente." -f $numbers.Count) -ForegroundColor Cyan

foreach ($number in $numbers) {
    $numberText = [string]$number
    $detailJson = Invoke-Gh -Arguments @(
        'pr', 'view', $numberText, '--repo', $script:RepoSlug,
        '--json', 'number,title,url,mergeable,state,headRefOid'
    )
    $pr = $detailJson | ConvertFrom-Json

    if ([string]$pr.state -eq 'MERGED') {
        Write-Host "PR #$numberText ya está fusionada. Se omite." -ForegroundColor Green
        continue
    }
    if ([string]$pr.state -ne 'OPEN') {
        Write-Warning "PR #$numberText no está abierta (estado: $($pr.state)); se omite."
        continue
    }

    Write-Host "`nPR #$numberText — $($pr.title)" -ForegroundColor Cyan
    Write-Host $pr.url
    Write-Host "Mergeable: $($pr.mergeable)" -ForegroundColor DarkGray

    if ([string]$pr.mergeable -eq 'CONFLICTING') {
        throw "La PR #$numberText tiene conflictos. No se fusionó. Resuelve los conflictos en GitHub y vuelve a ejecutar el script."
    }
    if ([string]::IsNullOrWhiteSpace([string]$pr.headRefOid)) {
        throw "GitHub no devolvió headRefOid para la PR #$numberText; no se intentará fusionar."
    }

    $checksOk = Test-PrChecks -HeadSha ([string]$pr.headRefOid) -PrNumber $numberText
    if (-not $checksOk) {
        throw "La PR #$numberText tiene checks fallidos o pendientes. No se intentará fusionar."
    }

    $answer = Read-Host "Escribe SI para fusionar SOLO la PR #$numberText conservando sus commits; cualquier otra respuesta la deja abierta"
    if ($answer -cne 'SI') {
        Write-Host "Se deja abierta la PR #$numberText." -ForegroundColor Yellow
        continue
    }

    # Un único número de PR por llamada. --merge conserva los commits de la PR.
    try {
        $mergeOutput = Invoke-Gh -Arguments @(
            'pr', 'merge', $numberText, '--repo', $script:RepoSlug,
            '--merge', '--delete-branch'
        )
        if (-not [string]::IsNullOrWhiteSpace($mergeOutput)) {
            Write-Host $mergeOutput
        }
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        throw ("GitHub no fusionó la PR #{0}. Revisa si el repositorio permite merge commits, si hay reglas de rama o si cambió el estado de la PR. La siguiente PR NO se procesó." -f $numberText)
    }

    $verifyJson = Invoke-Gh -Arguments @('pr', 'view', $numberText, '--repo', $script:RepoSlug, '--json', 'state')
    $verify = $verifyJson | ConvertFrom-Json
    if ([string]$verify.state -ne 'MERGED') {
        throw "La orden de fusión terminó, pero la PR #$numberText no figura como MERGED. Comprueba GitHub antes de continuar."
    }
    Write-Host "PR #$numberText fusionada correctamente." -ForegroundColor Green
}

$remaining = @(Get-OpenPrNumbers)
if ($remaining.Count -gt 0) {
    Write-Warning ("Quedan PR abiertas: {0}. No avances a la siguiente fase todavía." -f ($remaining -join ', '))
    exit 2
}

Push-Location $repoRoot
try {
    $null = Invoke-NativeCommand -FilePath 'git' -Arguments @('fetch', 'origin')
    $null = Invoke-NativeCommand -FilePath 'git' -Arguments @('switch', 'main')
    $null = Invoke-NativeCommand -FilePath 'git' -Arguments @('pull', '--ff-only', 'origin', 'main')
}
finally {
    Pop-Location
}

Write-Host 'Todas las PR abiertas están fusionadas y la rama local main está actualizada.' -ForegroundColor Green

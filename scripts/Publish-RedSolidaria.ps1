[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Day1','Day2','Day3','Status')][string]$Phase,
    [string]$Owner,
    [string]$Repository,
    [ValidateSet('public','private')][string]$Visibility = 'public',
    [string]$Description = 'Red Solidaria - plataforma web para gestionar donaciones y ayuda social'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$StatePath = Join-Path (Join-Path $Root '.git') 'redsolidaria-publish-state.json'

function Invoke-Checked([string]$Exe, [string[]]$ArgumentList) {
    $r = Invoke-RSNative -FilePath (Get-Command ($Exe + '.exe') -ErrorAction Stop).Source -ArgumentList $ArgumentList -ShowOutput
    if ($r.ExitCode -ne 0) { throw ("Falló: {0} {1} (código {2}). {3}" -f $Exe,($ArgumentList -join ' '),$r.ExitCode,$r.StdErr) }
}
function Get-PeruNow {
    try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('SA Pacific Standard Time') }
    catch { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('America/Lima') }
    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Now, $tz).DateTime
}
function Assert-NoOpenPullRequests([string]$Slug) {
    $r = Invoke-RSNative -FilePath (Get-Command gh.exe -ErrorAction Stop).Source -ArgumentList @('pr','list','--repo',$Slug,'--state','open','--json','number','--jq','length')
    if ($r.ExitCode -ne 0) { throw ('No se pudo consultar el estado de las Pull Requests: ' + $r.StdErr) }
    $count = $r.StdOut.Trim()
    if ($count -ne '0') { throw "Hay $count Pull Requests abiertas. Revisa CI y fusiona todas las PR de la fase anterior antes de continuar." }
}
function Read-State {
    if (-not (Test-Path $StatePath)) { return $null }
    return (Get-Content $StatePath -Raw | ConvertFrom-Json)
}
function Save-State($State) { $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8 }
function Commit-Group([string]$Message, [string[]]$Paths) {
    $existing = @($Paths | Where-Object { Test-Path (Join-Path $Root $_) })
    if ($existing.Count -eq 0) { return }
    Invoke-Checked git (@('add','--') + $existing)
    $diff = Invoke-RSNative -FilePath (Get-Command git.exe -ErrorAction Stop).Source -ArgumentList @('diff','--cached','--quiet') -AllowedExitCodes @(0,1)
    if ($diff.ExitCode -eq 0) { return }
    if ($diff.ExitCode -ne 1) { throw ('git diff --cached --quiet falló con código {0}: {1}' -f $diff.ExitCode,$diff.StdErr) }
    Invoke-Checked git @('commit','-m',$Message)
}
function New-Feature([string]$Branch, [string]$Title, [string]$Body, [scriptblock]$Work, [string]$Slug) {
    Invoke-Checked git @('fetch','origin')
    Invoke-Checked git @('switch','main')
    Invoke-Checked git @('pull','--ff-only','origin','main')
    Invoke-Checked git @('switch','-c',$Branch)
    & $Work
    Invoke-Checked git @('push','-u','origin',$Branch)
    Invoke-Checked gh @('pr','create','--repo',$Slug,'--base','main','--head',$Branch,'--title',$Title,'--body',$Body)
    Invoke-Checked git @('switch','main')
}

Push-Location $Root
try {
    if ($Phase -eq 'Status') {
        $state = Read-State
        if (-not $state) { Write-Host 'No existe estado de publicación todavía.'; exit 0 }
        $state | Format-List
        exit 0
    }
    foreach ($tool in @('git','gh')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Instala $tool antes de continuar." } }
    Invoke-Checked gh @('auth','status')
    $gitExe = (Get-Command git.exe -ErrorAction Stop).Source
    $nameResult = Invoke-RSNative -FilePath $gitExe -ArgumentList @('config','user.name')
    $emailResult = Invoke-RSNative -FilePath $gitExe -ArgumentList @('config','user.email')
    $name = $nameResult.StdOut.Trim()
    $email = $emailResult.StdOut.Trim()
    if (-not $name -or -not $email) { throw "Configura tu identidad real con git config --global user.name y user.email." }

    if ($Phase -eq 'Day1') {
        if (Test-Path '.git') { throw 'Ya existe .git. No se sobrescribirá el historial.' }
        if (-not $Owner -or -not $Repository) { throw 'Day1 requiere -Owner y -Repository.' }
        Invoke-Checked git @('init')
        Invoke-Checked git @('branch','-M','main')
        Commit-Group 'chore: iniciar repositorio y reglas de exclusión' @('.gitignore','.dockerignore','.env.example','README.md','CLAUDE.md')
        $Slug = "$Owner/$Repository"
        Invoke-Checked gh @('repo','create',$Slug,("--$Visibility"),'--description',$Description)
        Invoke-Checked git @('remote','add','origin',"https://github.com/$Slug.git")
        Invoke-Checked git @('push','-u','origin','main')

        New-Feature 'feature/database-schema' 'feat(database): modelo relacional y procedimientos' 'Esquema SQL Server, constraints, vistas, procedimientos almacenados y datos de demostración.' {
            Commit-Group 'feat(database): definir esquema relacional y restricciones' @('database/01_create_database.sql','database/02_tables.sql','database/03_indexes.sql','database/legacy')
            Commit-Group 'feat(database): implementar vistas y procedimientos almacenados' @('database/04_views.sql','database/05_procedures_seguridad.sql','database/06_procedures_catalogos.sql','database/07_procedures_finanzas.sql','database/08_procedures_operacion.sql','database/08_procedures_reportes.sql','database/09_permissions.sql','database/10_reference_data.sql')
            Commit-Group 'test(database): añadir fixtures reproducibles y script de operación' @('database/datos','database.ps1')
        } $Slug
        New-Feature 'feature/backend-api' 'feat(backend): API FastAPI organizada por capas' 'Routers, esquemas, servicios, repositorios, seguridad JWT, acceso SQL por procedimientos y pruebas.' {
            Commit-Group 'feat(backend): definir endpoints y contratos de entrada/salida' @('backend/app/__init__.py','backend/app/apis','backend/app/schemas','backend/app/main.py')
            Commit-Group 'feat(backend): separar reglas de negocio y persistencia' @('backend/app/core','backend/app/db','backend/app/repositories','backend/app/services')
            Commit-Group 'test(backend): incorporar pruebas y scripts de inicialización' @('backend/.env.example','backend/requirements.txt','backend/requirements-dev.txt','backend/constraints.txt','backend/pytest.ini','backend/scripts')
            Commit-Group 'test(backend): cubrir autenticación, permisos y contratos SQL' @('backend/tests')
        } $Slug
        $state = [pscustomobject]@{ Owner=$Owner; Repository=$Repository; Slug=$Slug; Day1Date=(Get-PeruNow).ToString('yyyy-MM-dd'); Day2Date=$null; Day3Date=$null }
        Save-State $state
        Write-Host "Day1 publicado. PRs database-schema y backend-api creadas con fechas reales." -ForegroundColor Green
        exit 0
    }

    $state = Read-State
    if (-not $state) { throw 'Ejecuta Day1 primero.' }
    $Slug = $state.Slug
    if ($Owner -and $Owner -ne $state.Owner) { throw 'Owner no coincide con Day1.' }
    if ($Repository -and $Repository -ne $state.Repository) { throw 'Repository no coincide con Day1.' }
    $peruNow = Get-PeruNow
    $today = $peruNow.Date
    $day1 = [datetime]::ParseExact($state.Day1Date,'yyyy-MM-dd',$null).Date

    if ($Phase -eq 'Day2') {
        Assert-NoOpenPullRequests $Slug
        if ($state.Day2Date) { throw 'Day2 ya fue publicado.' }
        $expectedDay2 = ([datetime]::new(2026,11,23)).Date
        if ($today -ne $expectedDay2) { throw 'Day2 está programado para el lunes 23-11-2026 (hora de Lima).' }
        if ($today -le $day1) { throw 'Day2 debe ejecutarse después de Day1.' }
        New-Feature 'feature/angular-frontend' 'feat(frontend): interfaz Angular responsive' 'Frontend Angular modular, servicios HTTP, guards, formularios y Bootstrap.' {
            Commit-Group 'feat(frontend): incorporar núcleo, autenticación y servicios HTTP' @('frontend/src/app/core')
            Commit-Group 'feat(frontend): implementar módulos y funcionalidades de negocio' @('frontend/src/app/features')
            Commit-Group 'feat(frontend): añadir layout, componentes y configuración Angular' @('frontend/src/app/layout','frontend/src/app/shared','frontend/src/app/app.config.ts','frontend/src/app/app.routes.ts','frontend/src/app/app.ts','frontend/src/styles.scss','frontend/src/main.ts','frontend/src/index.html','frontend/public','frontend/angular.json','frontend/package.json','frontend/package-lock.json','frontend/tsconfig.json','frontend/tsconfig.app.json','frontend/tsconfig.spec.json','frontend/proxy.conf.json','frontend/scripts','frontend/.editorconfig','frontend/.gitignore','frontend/.prettierrc')
        } $Slug
        New-Feature 'feature/docker-platform' 'feat(deploy): empaquetar aplicación y SQL Server con Docker' 'Dockerfiles, Compose, TLS interno de SQL Server y proxy reverso Caddy.' {
            Commit-Group 'build(docker): crear imágenes de FastAPI y Angular' @('backend/Dockerfile','frontend/Dockerfile','backend/scripts/wait_for_sql.py')
            Commit-Group 'feat(docker): orquestar SQL Server, API, frontend y Caddy' @('docker-compose.yml','.env.example','.gitignore','deploy/Caddyfile','deploy/nginx.conf','deploy/sqlserver/mssql.conf')
        } $Slug
        New-Feature 'ops/vps-deployment' 'ops: automatizar aprovisionamiento y despliegue remoto' 'Bootstrap de Ubuntu, Docker Engine, firewall, certificados TLS internos y healthchecks.' {
            Commit-Group 'ops(vps): instalar Docker y preparar el host' @('deploy/bootstrap-vps.sh')
            Commit-Group 'ops(vps): actualizar servicios y verificar API, SQL y login' @('deploy/deploy-on-server.sh')
            Commit-Group 'fix(backend): alinear seed y pruebas con los fixtures de demostración' @('backend/scripts/seed.py','backend/tests/test_flujos_api.py')
            Commit-Group 'ops(azure): aprovisionar VM con Azure for Students' @('scripts/RedSolidaria.Native.psm1','scripts/Connect-RedSolidaria-Azure.ps1','scripts/Repair-RedSolidariaPublishState.ps1','scripts/Test-RedSolidaria-Azure.ps1','scripts/Provision-RedSolidaria-Azure.ps1','scripts/Start-RedSolidaria-Azure.ps1','scripts/Stop-RedSolidaria-Azure.ps1','scripts/Remove-RedSolidaria-Azure.ps1','scripts/Update-RedSolidaria-AzureSSH.ps1','docs/DESPLIEGUE_AZURE_FOR_STUDENTS.md','docs/OPERACION_AZURE.md')
        } $Slug
        $state.Day2Date = (Get-PeruNow).ToString('yyyy-MM-dd')
        Save-State $state
        Write-Host 'Day2 publicado. Se crearon PRs frontend, docker-platform y vps-deployment.' -ForegroundColor Green
        exit 0
    }

    if ($Phase -eq 'Day3') {
        Assert-NoOpenPullRequests $Slug
        if (-not $state.Day2Date) { throw 'Ejecuta Day2 antes de Day3.' }
        if ($state.Day3Date) { throw 'Day3 ya fue publicado.' }
        $day2 = [datetime]::ParseExact($state.Day2Date,'yyyy-MM-dd',$null).Date
        $expectedDay3 = ([datetime]::new(2026,11,24)).Date
        if ($today -ne $expectedDay3) { throw 'Day3 está programado para el martes 24-11-2026 (hora de Lima).' }
        if ($today -le $day2) { throw 'Day3 debe ejecutarse después de Day2.' }
        $deadline = [datetime]::new(2026,11,24,18,0,0)
        if ($peruNow -ge $deadline) { throw 'Se superó el límite del martes 24-11-2026 a las 18:00 (hora local del equipo).' }
        New-Feature 'ci/github-actions' 'ci: automatizar validación y despliegue' 'Workflow de CI en PRs y CD remoto tras CI exitoso en main.' {
            Commit-Group 'ci: validar backend y frontend en GitHub Actions' @('.github/workflows/ci.yml')
            Commit-Group 'ci: desplegar VPS automáticamente después de CI' @('.github/workflows/deploy.yml')
        } $Slug
        New-Feature 'docs/technical-delivery' 'docs: documentar arquitectura y despliegue' 'Guía de sistema, despliegue Docker, rúbrica y sustentación.' {
            Commit-Group 'docs: describir arquitectura, decisiones y modelo de datos' @('README.md','docs/ARQUITECTURA.md','docs/API.md','docs/MODELO_DATOS.md','docs/DECISIONES.md','docs/ALCANCE_FUNCIONAL.md','docs/AUDITORIA_BD.md')
            Commit-Group 'docs: documentar pruebas, instalación, despliegue y defensa' @('docs/INSTALACION.md','docs/PRUEBAS.md','docs/REVISION_RUBRICA.md','docs/SUSTENTACION.md','docs/DESPLIEGUE.md','docs/DESPLIEGUE_DOCKER.md','docs/CREDITOS.md','docs/OPERACION_AZURE.md','docs/capturas','setup.ps1','run.ps1','scripts/Publish-RedSolidaria.ps1','scripts/Merge-RedSolidariaPhase.ps1','scripts/Merge-RedSolidariaOpenPRs.ps1','scripts/Deploy-RedSolidaria.ps1')
        } $Slug
        $state.Day3Date = (Get-PeruNow).ToString('yyyy-MM-dd')
        Save-State $state
        Write-Host 'Day3 publicado. Verifica CI, fusiona todas las PR y después ejecuta Deploy-RedSolidaria.ps1.' -ForegroundColor Green
        exit 0
    }
}
finally { Pop-Location }

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Owner,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Repository,
    [Parameter(Mandatory)][string]$ServerIp,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$SshUser = 'ubuntu',
    [ValidateRange(1,65535)][int]$SshPort = 22,
    [string]$InitialKeyPath,
    [string]$Domain,
    [ValidateRange(1024,6144)][int]$MssqlMemoryLimitMB = 3072,
    [ValidateSet('3g','4g')][string]$MssqlContainerMemoryLimit = '4g',
    [switch]$ConfigureGitHubActions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoSlug = "$Owner/$Repository"
$RepoUrl = "https://github.com/$RepoSlug.git"
$Remote = "$SshUser@$ServerIp"
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Import-Module (Join-Path $PSScriptRoot 'RedSolidaria.Native.psm1') -Force
function Invoke-Checked([string]$Exe, [string[]]$ArgumentList) {
    $r = Invoke-RSNative -FilePath $Exe -ArgumentList $ArgumentList -ShowOutput
    if ($r.ExitCode -ne 0) { throw ("Falló: {0} {1} (código {2}). {3}" -f $Exe,($ArgumentList -join ' '),$r.ExitCode,$r.StdErr) }
    return $r.StdOut
}
function New-SecurePassword([int]$Length = 32) {
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbols = '!@_+-'
    $all = $upper + $lower + $digits + $symbols
    $bytes = [byte[]]::new($Length)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $chars = [System.Collections.Generic.List[char]]::new()
    $chars.Add($upper[[int]($bytes[0] % $upper.Length)])
    $chars.Add($lower[[int]($bytes[1] % $lower.Length)])
    $chars.Add($digits[[int]($bytes[2] % $digits.Length)])
    $chars.Add($symbols[[int]($bytes[3] % $symbols.Length)])
    for ($i = 4; $i -lt $Length; $i++) { $chars.Add($all[[int]($bytes[$i] % $all.Length)]) }
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = [int]($bytes[$i] % ($i + 1)); $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    return -join $chars
}
function Get-PeruNow {
    try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('SA Pacific Standard Time') }
    catch { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('America/Lima') }
    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::Now, $tz).DateTime
}

$parsedIp = $null
if (-not [Net.IPAddress]::TryParse($ServerIp, [ref]$parsedIp) -or $parsedIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'ServerIp debe ser una IPv4 pública del VPS.'
}
if ($SshUser -eq 'root') { throw 'Usa una cuenta normal con sudo (por ejemplo ubuntu), no root.' }

Push-Location $Root
$SecretsDir = Join-Path $env:USERPROFILE '.redsolidaria'
$SecretsPath = Join-Path $SecretsDir "$Owner-$Repository.env"
$KnownHostsPath = Join-Path $env:TEMP ("redsolidaria-known-hosts-" + [guid]::NewGuid().ToString('N'))
try {
    foreach ($tool in @('ssh','scp','ssh-keygen','ssh-keyscan','gh')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "No se encontró $tool. Instala OpenSSH Client y GitHub CLI." } }
    Invoke-Checked gh @('auth','status')
    if (-not (Test-Path '.git')) { throw 'Primero ejecuta Publish-RedSolidaria.ps1 y fusiona todas las PR en main.' }
    $publishStatePath = Join-Path (Join-Path $Root '.git') 'redsolidaria-publish-state.json'
    if (-not (Test-Path $publishStatePath)) { throw 'Falta el estado de publicación. Ejecuta las fases Day1, Day2 y Day3 con Publish-RedSolidaria.ps1.' }
    $publishState = Get-Content $publishStatePath -Raw | ConvertFrom-Json
    if (-not $publishState.Day3Date) { throw 'No se ha publicado la fase Day3 (CI/CD y documentación).' }
    $openPrResult = Invoke-RSNative -FilePath (Get-Command gh.exe).Source -ArgumentList @('pr','list','--repo',$RepoSlug,'--state','open','--json','number','--jq','length')
    if ($openPrResult.ExitCode -ne 0) { throw ('No se pudo consultar el estado de las Pull Requests: ' + $openPrResult.StdErr) }
    $openPrCount = $openPrResult.StdOut.Trim()
    if ($openPrCount -ne '0') { throw "Aún hay $openPrCount PR abiertas. Revisa CI y fusiona todas antes de desplegar." }
    $visibilityResult = Invoke-RSNative -FilePath (Get-Command gh.exe).Source -ArgumentList @('repo','view',$RepoSlug,'--json','visibility','--jq','.visibility')
    if ($visibilityResult.ExitCode -ne 0 -or $visibilityResult.StdOut.Trim() -ne 'PUBLIC') { throw 'El VPS clona el repositorio sin token. Publica el repositorio como público o adapta el acceso SSH de GitHub antes de desplegar.' }
    $visibility = $visibilityResult.StdOut.Trim()
    Invoke-Checked git @('fetch','origin')
    Invoke-Checked git @('switch','main')
    Invoke-Checked git @('pull','--ff-only','origin','main')
    $shaResult = Invoke-RSNative -FilePath (Get-Command git.exe).Source -ArgumentList @('rev-parse','origin/main')
    if ($shaResult.ExitCode -ne 0 -or -not $shaResult.StdOut.Trim()) { throw 'No se pudo identificar el commit actual de main.' }
    $mainSha = $shaResult.StdOut.Trim()
    $ciResult = Invoke-RSNative -FilePath (Get-Command gh.exe).Source -ArgumentList @('run','list','--repo',$RepoSlug,'--workflow','ci.yml','--branch','main','--limit','20','--json','databaseId,headSha,status,conclusion')
    if ($ciResult.ExitCode -ne 0) { throw ('No se pudo consultar GitHub Actions: ' + $ciResult.StdErr) }
    $ciRuns = @($ciResult.StdOut | ConvertFrom-Json)
    $ciRun = $ciRuns | Where-Object { $_.headSha -eq $mainSha } | Select-Object -First 1
    if ($null -eq $ciRun) { throw "No existe una ejecución CI para main ($mainSha). Consulta gh run list --repo $RepoSlug --workflow ci.yml --branch main." }
    if ($ciRun.status -ne 'completed' -or $ciRun.conclusion -ne 'success') {
        throw "CI no ha terminado con éxito para main ($mainSha). Consulta 'gh run list --repo $RepoSlug --workflow ci.yml --branch main' y espera a que finalice antes del despliegue."
    }
    if (-not (Test-Path 'docker-compose.yml') -or -not (Test-Path 'deploy/deploy-on-server.sh')) { throw 'La rama main todavía no contiene los archivos Docker de despliegue.' }

    if (-not $Domain) { $Domain = "red-solidaria.$ServerIp.nip.io" }
    if ($Domain -notmatch '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))+$') { throw 'DOMAIN debe ser un hostname DNS válido, no una URL ni una dirección con puerto.' }

    $sshDir = Join-Path $env:USERPROFILE '.ssh'
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    $deployKey = Join-Path $sshDir 'redsolidaria_actions_ed25519'
    if (-not (Test-Path $deployKey)) {
        Invoke-Checked ssh-keygen @('-t','ed25519','-C',"github-actions-$Repository",'-N','','-f',$deployKey)
    }
    if (-not (Test-Path "$deployKey.pub")) {
        $pubResult = Invoke-RSNative -FilePath (Get-Command ssh-keygen.exe).Source -ArgumentList @('-y','-f',$deployKey)
        if ($pubResult.ExitCode -ne 0 -or -not $pubResult.StdOut.Trim()) { throw ('No se pudo reconstruir la clave SSH pública: ' + $pubResult.StdErr) }
        $pub = $pubResult.StdOut.Trim()
        [IO.File]::WriteAllText("$deployKey.pub", $pub + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    }
    if (Get-Command icacls -ErrorAction SilentlyContinue) {
        $aclResult = Invoke-RSNative -FilePath (Get-Command icacls.exe).Source -ArgumentList @($deployKey,'/inheritance:r','/grant:r',"$($env:USERNAME):(R,W)")
        if ($aclResult.ExitCode -ne 0) { throw ('No se pudieron restringir los permisos de la clave privada SSH: ' + $aclResult.StdErr) }
    }

    # Verifica la identidad SSH del VPS antes de enviar claves o contraseñas.
    $scanResult = Invoke-RSNative -FilePath (Get-Command ssh-keyscan.exe).Source -ArgumentList @('-p',"$SshPort",$ServerIp)
    $knownHosts = $scanResult.StdOut.Trim()
    if ($scanResult.ExitCode -ne 0 -or -not $knownHosts) { throw ('No se pudo obtener la clave pública SSH del VPS: ' + $scanResult.StdErr) }
    [IO.File]::WriteAllText($KnownHostsPath, $knownHosts + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host "`nHuella SSH anunciada por el VPS (compárala con la consola del proveedor):" -ForegroundColor Yellow
    Invoke-Checked ssh-keygen @('-lf',$KnownHostsPath)
    $confirmHost = Read-Host '¿La huella coincide con la mostrada por el proveedor? Escribe SI'
    if ($confirmHost -ne 'SI') { throw 'Conexión cancelada: no se verificó la identidad del servidor.' }

    $pubKey = (Get-Content "$deployKey.pub" -Raw).Trim()
    $remoteInstallKey = "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$pubKey' ~/.ssh/authorized_keys || echo '$pubKey' >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
    $initialSshArgs = @('-p',"$SshPort",'-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes')
    if ($InitialKeyPath) {
        $initialResolvedKey = (Resolve-Path $InitialKeyPath).Path
        $initialSshArgs = @('-i',$initialResolvedKey) + $initialSshArgs
    }
    $initialCommandArgs = $initialSshArgs + @($Remote,$remoteInstallKey)
    $initialResult = Invoke-RSNative -FilePath (Get-Command ssh.exe).Source -ArgumentList $initialCommandArgs -ShowOutput
    if ($initialResult.ExitCode -ne 0) {
        # En una segunda ejecución, la clave de despliegue ya puede estar autorizada.
        $fallbackArgs = @('-i',$deployKey) + $initialSshArgs + @($Remote,$remoteInstallKey)
        Invoke-Checked (Get-Command ssh.exe).Source $fallbackArgs
    }

    # Conserva las credenciales entre despliegues: el seed no cambia contraseñas de usuarios ya creados.
    New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null
    if (Get-Command icacls -ErrorAction SilentlyContinue) {
        $aclResult = Invoke-RSNative -FilePath (Get-Command icacls.exe).Source -ArgumentList @($SecretsDir,'/inheritance:r','/grant:r',"$($env:USERNAME):(OI)(CI)(F)")
        if ($aclResult.ExitCode -ne 0) { throw ('No se pudieron restringir los permisos de la carpeta de secretos: ' + $aclResult.StdErr) }
    }
    $envMap = @{}
    if (Test-Path $SecretsPath) {
        foreach ($line in Get-Content $SecretsPath) {
            if ($line -match '^([^#=]+)=(.*)$') { $envMap[$matches[1]] = $matches[2] }
        }
        foreach ($required in @('MSSQL_SA_PASSWORD','DB_APP_PASSWORD','JWT_SECRET_KEY','SEED_ADMIN_PASSWORD','SEED_DEMO_PASSWORD')) {
            if (-not $envMap.ContainsKey($required) -or -not $envMap[$required]) { throw "El archivo de secretos existente no contiene ${required}: $SecretsPath" }
        }
        $envMap['DOMAIN'] = $Domain
        $envMap['CORS_ORIGINS'] = "https://$Domain"
        $envMap['MSSQL_PID'] = 'Express'
        if (-not $envMap.ContainsKey('MSSQL_MEMORY_LIMIT_MB')) { $envMap['MSSQL_MEMORY_LIMIT_MB'] = [string]$MssqlMemoryLimitMB }
        $envMap['MSSQL_CONTAINER_MEMORY_LIMIT'] = $MssqlContainerMemoryLimit
    }
    else {
        $sa = New-SecurePassword 40
        $db = New-SecurePassword 40
        $jwtBytes = [byte[]]::new(48); $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($jwtBytes) } finally { $rng.Dispose() }
        $jwt = [Convert]::ToBase64String($jwtBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
        $admin = New-SecurePassword 28
        $demo = New-SecurePassword 28
        $envMap = @{
            ACCEPT_EULA='Y'; MSSQL_PID='Express'; MSSQL_MEMORY_LIMIT_MB=[string]$MssqlMemoryLimitMB; MSSQL_CONTAINER_MEMORY_LIMIT=$MssqlContainerMemoryLimit; MSSQL_SA_PASSWORD=$sa; MSSQL_SA_USER='sa'
            APP_ENV='production'; DB_SERVER='sqlserver'; DB_PORT='1433'; DB_NAME='RedSolidaria'
            DB_DRIVER='ODBC Driver 18 for SQL Server'; DB_TRUST_SERVER_CERTIFICATE='no'
            DB_APP_USER='redsolidaria_app'; DB_APP_PASSWORD=$db; JWT_SECRET_KEY=$jwt
            ACCESS_TOKEN_EXPIRE_MINUTES='60'; CORS_ORIGINS="https://$Domain"
            SEED_ADMIN_USERNAME='admin'; SEED_ADMIN_PASSWORD=$admin; SEED_DEMO_PASSWORD=$demo; DOMAIN=$Domain
        }
    }
    $keys = @('ACCEPT_EULA','MSSQL_PID','MSSQL_MEMORY_LIMIT_MB','MSSQL_CONTAINER_MEMORY_LIMIT','MSSQL_SA_PASSWORD','MSSQL_SA_USER','APP_ENV','DB_SERVER','DB_PORT','DB_NAME','DB_DRIVER','DB_TRUST_SERVER_CERTIFICATE','DB_APP_USER','DB_APP_PASSWORD','JWT_SECRET_KEY','ACCESS_TOKEN_EXPIRE_MINUTES','CORS_ORIGINS','SEED_ADMIN_USERNAME','SEED_ADMIN_PASSWORD','SEED_DEMO_PASSWORD','DOMAIN')
    $lines = foreach ($key in $keys) { "$key=$($envMap[$key])" }
    [IO.File]::WriteAllLines($SecretsPath, $lines, [Text.UTF8Encoding]::new($false))
    if (Get-Command icacls -ErrorAction SilentlyContinue) {
        $aclResult = Invoke-RSNative -FilePath (Get-Command icacls.exe).Source -ArgumentList @($SecretsPath,'/inheritance:r','/grant:r',"$($env:USERNAME):(R,W)")
        if ($aclResult.ExitCode -ne 0) { throw ('No se pudieron restringir los permisos del archivo de secretos: ' + $aclResult.StdErr) }
    }
    $sa = $envMap['MSSQL_SA_PASSWORD']; $db = $envMap['DB_APP_PASSWORD']; $admin = $envMap['SEED_ADMIN_PASSWORD']; $demo = $envMap['SEED_DEMO_PASSWORD']

    $bootstrap = Join-Path $Root 'deploy/bootstrap-vps.sh'
    Invoke-Checked scp @('-i',$deployKey,'-P',"$SshPort",'-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes',$bootstrap,"${Remote}:/tmp/redsolidaria-bootstrap.sh")
    $quotedRepo = "'$RepoUrl'"
    $quotedPath = "'/opt/red-solidaria'"
    Invoke-Checked ssh @('-i',$deployKey,'-t','-p',"$SshPort",'-o','IdentitiesOnly=yes','-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes',$Remote,"chmod +x /tmp/redsolidaria-bootstrap.sh && sudo -E env SSH_PORT=$SshPort bash /tmp/redsolidaria-bootstrap.sh $quotedRepo $quotedPath")

    # El grupo docker se aplica en una sesión SSH nueva.
    Invoke-Checked ssh @('-i',$deployKey,'-p',"$SshPort",'-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes',$Remote,'umask 077; mkdir -p ~/.redsolidaria-upload; chmod 700 ~/.redsolidaria-upload')
    Invoke-Checked scp @('-i',$deployKey,'-P',"$SshPort",'-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes',$SecretsPath,"${Remote}:~/.redsolidaria-upload/production.env")
    Invoke-Checked ssh @('-i',$deployKey,'-p',"$SshPort",'-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o',"UserKnownHostsFile=$KnownHostsPath",'-o','StrictHostKeyChecking=yes',$Remote,'install -m 600 ~/.redsolidaria-upload/production.env /opt/red-solidaria/.env && rm -f ~/.redsolidaria-upload/production.env && rmdir ~/.redsolidaria-upload && chmod +x /opt/red-solidaria/deploy/deploy-on-server.sh && cd /opt/red-solidaria && bash deploy/deploy-on-server.sh')

    $url = "https://$Domain"
    $front = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing -TimeoutSec 30
    if ($front.StatusCode -ne 200) { throw 'La portada Angular no respondió HTTP 200.' }
    $health = Invoke-RestMethod -Uri "$url/health/db" -Method Get -TimeoutSec 30
    if ($health.estado -ne 'ok' -or $health.base_de_datos -ne 'disponible') { throw 'El healthcheck de SQL Server no confirmó disponibilidad.' }
    $loginBody = @{ username = 'admin'; password = $admin } | ConvertTo-Json -Compress
    $login = Invoke-RestMethod -Uri "$url/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body $loginBody -TimeoutSec 30
    if (-not $login.access_token) { throw 'La API no devolvió JWT al iniciar sesión como admin.' }

    Write-Host "`nDESPLIEGUE VALIDADO: $url" -ForegroundColor Green
    Write-Host 'Verificado desde este equipo: portada Angular HTTP 200, HTTPS, /health/db y login JWT.' -ForegroundColor Green
    Write-Host "Usuario administrador: admin" -ForegroundColor Yellow
    Write-Host "Contraseña inicial admin (guárdala ahora): $admin" -ForegroundColor Yellow
    Write-Host "Contraseña cuentas demo: $demo" -ForegroundColor Yellow
    Write-Host "SQL Server admin SA: $sa" -ForegroundColor DarkYellow
    Write-Host "Copia local protegida de secretos: $SecretsPath" -ForegroundColor DarkYellow
    Write-Host 'No compartas estas credenciales ni las subas a Git.' -ForegroundColor Red

    if ($ConfigureGitHubActions) {
        # Fija la clave del host SSH para que Actions no use StrictHostKeyChecking=accept-new.
        Invoke-Checked gh @('secret','set','VPS_HOST','--repo',$RepoSlug,'--body',$ServerIp)
        Invoke-Checked gh @('secret','set','VPS_USER','--repo',$RepoSlug,'--body',$SshUser)
        Invoke-Checked gh @('secret','set','VPS_PORT','--repo',$RepoSlug,'--body',"$SshPort")
        Invoke-Checked gh @('secret','set','VPS_KNOWN_HOSTS','--repo',$RepoSlug,'--body',$knownHosts)
        $privateKeyText = [IO.File]::ReadAllText($deployKey)
        $secretResult = Invoke-RSNative -FilePath (Get-Command gh.exe).Source -ArgumentList @('secret','set','VPS_SSH_PRIVATE_KEY','--repo',$RepoSlug) -StandardInputText $privateKeyText
        if ($secretResult.ExitCode -ne 0) { throw ('No se pudo registrar VPS_SSH_PRIVATE_KEY: ' + $secretResult.StdErr) }
        Invoke-Checked gh @('variable','set','DEPLOY_ENABLED','--repo',$RepoSlug,'--body','true')
        Write-Host 'Secretos y variable de GitHub Actions configurados. Los siguientes pushes a main ejecutarán CI y CD.' -ForegroundColor Green
    }
}
finally {
    if (Test-Path $KnownHostsPath) { Remove-Item -Force $KnownHostsPath }
    Pop-Location
}

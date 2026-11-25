#requires -Version 5.1
<#
.SYNOPSIS
  Abre SQL Server Management Studio hacia la base RedSolidaria a traves de SSH.
.DESCRIPTION
  Este archivo es AUTONOMO: no necesita conocer ni localizar la carpeta raiz del repositorio.
  SQL Server permanece privado en la VM; el script crea un tunel SSH local y abre SSMS.
  La contrasena SQL se introduce directamente en SSMS y nunca se guarda en este archivo.
#>
[CmdletBinding()]
param(
    [string]$SshHost = 'redsolidaria-jbranez.chilecentral.cloudapp.azure.com',
    [string]$SshUser = 'azureuser',
    [int]$SshPort = 22,
    [int]$LocalPort = 14333,
    [string]$KeyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-LocalTcpPort {
    param([string]$ComputerName = '127.0.0.1', [int]$Port, [int]$TimeoutMs = 500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
}

function Find-Ssms {
    $cmd = Get-Command Ssms.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @()
    if (${env:ProgramFiles(x86)}) {
        $roots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server Management Studio 22')
        $roots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server Management Studio 21')
        $roots += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server Management Studio 20')
    }
    if ($env:ProgramFiles) {
        $roots += (Join-Path $env:ProgramFiles 'Microsoft SQL Server Management Studio 22')
        $roots += (Join-Path $env:ProgramFiles 'Microsoft SQL Server Management Studio 21')
    }

    foreach ($root in $roots) {
        $candidate = Join-Path $root 'Common7\IDE\Ssms.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            $found = Get-ChildItem -LiteralPath $root -Filter Ssms.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return $null
}

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ' RED SOLIDARIA | DIAGRAMAS VISUALES DE SQL SERVER' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host 'Este script no necesita la carpeta raiz del repositorio.'
Write-Host "Servidor SSH: $SshUser@$SshHost`:$SshPort"
Write-Host "Destino local para SSMS: 127.0.0.1,$LocalPort"
Write-Host ''

# 1. Requerir OpenSSH en Windows.
$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $ssh) { $ssh = Get-Command ssh -ErrorAction SilentlyContinue }
if (-not $ssh) {
    throw 'No se encontro OpenSSH Client. En Windows instala Caracteristicas opcionales > OpenSSH Client y vuelve a abrir PowerShell.'
}
$sshExe = $ssh.Source

# 2. Encontrar la clave privada; admite los dos nombres usados anteriormente.
if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    $keyCandidates = @(
        (Join-Path $HOME '.ssh\redsolidaria_azure_ed25519'),
        (Join-Path $HOME '.ssh\redsolidaria_azure')
    )
    $KeyPath = $keyCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($KeyPath) -or -not (Test-Path -LiteralPath $KeyPath -PathType Leaf)) {
    $KeyPath = Read-Host 'Pega la ruta completa de la CLAVE PRIVADA SSH que ya esta autorizada en Azure'
}
if (-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)) { throw "No existe la clave indicada: $KeyPath" }
$KeyPath = (Resolve-Path -LiteralPath $KeyPath).Path
if ($KeyPath.EndsWith('.pub', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Elegiste la clave publica .pub. Debes indicar la clave PRIVADA original. Nunca la subas a GitHub.'
}

# 3. Comprobar acceso al puerto SSH. No se toca ni se abre el puerto 1433 publico.
Write-Host 'Comprobando acceso SSH...' -ForegroundColor Yellow
$sshTest = Test-NetConnection -ComputerName $SshHost -Port $SshPort -WarningAction SilentlyContinue
if (-not $sshTest.TcpTestSucceeded) {
    throw "No se alcanza $SshHost puerto $SshPort. La VM debe estar encendida y la IP publica de esta red debe estar autorizada en la regla SSH de Azure (TCP 22). No abras 1433 a Internet."
}
if (Test-LocalTcpPort -Port $LocalPort) {
    throw "El puerto local $LocalPort ya esta ocupado. Cierra la conexion anterior o ejecuta: .\Preparar-Diagrama-RedSolidaria.ps1 -LocalPort 14334"
}

# 4. Confirmar/registrar la clave del host SSH la primera vez.
Write-Host 'Validando la identidad SSH del servidor...' -ForegroundColor Yellow
Write-Host 'Si SSH muestra una huella que nunca habias visto, verifica su autenticidad antes de aceptar.' -ForegroundColor Yellow
& $sshExe -i $KeyPath -p $SshPort -o 'StrictHostKeyChecking=ask' -o 'ConnectTimeout=12' "$SshUser@$SshHost" 'exit'
if ($LASTEXITCODE -ne 0) { throw 'Fallo la autenticacion SSH. Revisa la huella del servidor, la clave privada y la regla de red.' }

# 5. Localizar o instalar SSMS 22.
$ssmsExe = Find-Ssms
if (-not $ssmsExe) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { $winget = Get-Command winget -ErrorAction SilentlyContinue }
    if (-not $winget) {
        throw 'No se encontro SSMS ni winget. Instala SSMS desde https://aka.ms/ssmsfullsetup y vuelve a ejecutar este script.'
    }
    $answer = Read-Host 'No se encontro SSMS. Instalar SQL Server Management Studio 22 con winget ahora? (S/N)'
    if ($answer -notin @('S','s','SI','Si','si')) {
        throw 'Instalacion cancelada. Instala SSMS 22 y vuelve a ejecutar este script.'
    }
    & $winget.Source install --id Microsoft.SQLServerManagementStudio.22 --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw 'La instalacion de SSMS no termino correctamente. Instala SSMS 22 y vuelve a ejecutar el script.' }
    $ssmsExe = Find-Ssms
    if (-not $ssmsExe) { throw 'SSMS se instalo, pero no se encontro Ssms.exe. Reinicia Windows y vuelve a ejecutar el script.' }
}

# 6. Levantar el tunel SSH en segundo plano.
$stdoutLog = Join-Path $env:TEMP 'redsolidaria-diagrama-ssh.out.log'
$stderrLog = Join-Path $env:TEMP 'redsolidaria-diagrama-ssh.err.log'
Remove-Item $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
$sshArguments = @(
    '-N',
    '-L', "$LocalPort`:127.0.0.1:1433",
    '-i', ('"' + $KeyPath + '"'),
    '-p', [string]$SshPort,
    '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'StrictHostKeyChecking=yes',
    "$SshUser@$SshHost"
)
$tunnel = $null
try {
    $tunnel = Start-Process -FilePath $sshExe -ArgumentList $sshArguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if ($tunnel.HasExited) {
            $details = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw } else { '' }
            throw "El tunel SSH se cerro antes de establecerse. $details"
        }
        if (Test-LocalTcpPort -Port $LocalPort) { $ready = $true; break }
    }
    if (-not $ready) { throw "No se pudo abrir 127.0.0.1:$LocalPort. Revisa SSH y el registro $stderrLog" }

    Write-Host ''
    Write-Host 'TUNEL SSH ACTIVO' -ForegroundColor Green
    Write-Host 'Abriendo SQL Server Management Studio...' -ForegroundColor Green
    Start-Process -FilePath $ssmsExe

    Write-Host ''
    Write-Host 'DATOS PARA CONECTAR EN SSMS' -ForegroundColor Cyan
    Write-Host "  Tipo de servidor : Motor de base de datos"
    Write-Host "  Nombre servidor  : 127.0.0.1,$LocalPort" -ForegroundColor Yellow
    Write-Host '  Autenticacion    : Autenticacion de SQL Server'
    Write-Host '  Usuario          : sa'
    Write-Host '  Base de datos    : RedSolidaria'
    Write-Host '  Seguridad        : activar Confiar en el certificado del servidor (el trafico va por SSH local)'
    Write-Host ''
    Write-Host 'Deja esta ventana abierta mientras uses SSMS.' -ForegroundColor Yellow
    Write-Host 'Cuando termines de guardar/consultar el diagrama, vuelve aqui y presiona ENTER para cerrar el tunel.' -ForegroundColor Yellow
    [void](Read-Host 'Presiona ENTER al terminar')
}
finally {
    if ($tunnel -and -not $tunnel.HasExited) {
        Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Tunel SSH cerrado.' -ForegroundColor DarkGray
}

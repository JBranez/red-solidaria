# RedSolidaria.Native.psm1
# Compatibilidad: Windows PowerShell 5.1 y Azure CLI az.cmd.
# Captura stdout/stderr en archivos temporales mientras ErrorActionPreference=Continue
# para impedir que NativeCommandError por warnings inofensivos detenga el flujo.
function Invoke-RSNative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [int[]]$AllowedExitCodes = @(0),
        [string]$StandardInputText,
        [switch]$ShowOutput
    )

    $id = [guid]::NewGuid().ToString('N')
    $stdoutFile = Join-Path $env:TEMP ("rs-native-$id.stdout")
    $stderrFile = Join-Path $env:TEMP ("rs-native-$id.stderr")
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 convierte stderr nativo en ErrorRecord.
        # Continue permite capturarlo en archivo sin abortar, y el ExitCode decide el éxito.
        $ErrorActionPreference = 'Continue'
        if ($PSBoundParameters.ContainsKey('StandardInputText')) {
            $inputValue = [string]$StandardInputText
            $outputLines = @($inputValue | & $FilePath @ArgumentList 1> $stdoutFile 2> $stderrFile)
        }
        else {
            $outputLines = @(& $FilePath @ArgumentList 1> $stdoutFile 2> $stderrFile)
        }
        $exitCode = $LASTEXITCODE
        $stdout = if (Test-Path -LiteralPath $stdoutFile) { [IO.File]::ReadAllText($stdoutFile) } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrFile) { [IO.File]::ReadAllText($stderrFile) } else { '' }

        if ($ShowOutput -and -not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            if ($exitCode -eq 0) { Write-Host $stderr.TrimEnd() -ForegroundColor DarkYellow }
            elseif ($ShowOutput) { Write-Host $stderr.TrimEnd() -ForegroundColor Red }
        }

        $result = [pscustomobject]@{
            ExitCode = [int]$exitCode
            StdOut = ([string]$stdout).TrimEnd()
            StdErr = ([string]$stderr).TrimEnd()
        }
        return $result
    }
    finally {
        $ErrorActionPreference = $previousPreference
        Remove-Item -LiteralPath $stdoutFile,$stderrFile -Force -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function Invoke-RSNative

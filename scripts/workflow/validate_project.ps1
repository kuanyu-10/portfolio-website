[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$started = [DateTime]::UtcNow
$status = 'BLOCKED'
$commandDescription = ''
$actualExitCode = 1
$summary = ''
$details = New-Object System.Collections.ArrayList
$logPath = ''

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config = Get-WorkflowConfig -ProjectRoot $root
    $customValidator = Join-Path $root 'scripts\project\validate.ps1'
    $workingDirectory = $root
    $mode = ''

    if ($config -and -not [string]::IsNullOrWhiteSpace([string]$config.validationCommand)) {
        $mode = 'command'
        $commandDescription = [string]$config.validationCommand
        if (-not [string]::IsNullOrWhiteSpace([string]$config.validationWorkingDirectory)) {
            $workingDirectory = [IO.Path]::GetFullPath((Join-Path $root ([string]$config.validationWorkingDirectory)))
        }
    }
    elseif (Test-Path -LiteralPath $customValidator -PathType Leaf) {
        $mode = 'script'
        $commandDescription = "powershell -File scripts/project/validate.ps1"
    }
    else {
        $status = 'NOT_CONFIGURED'
        $actualExitCode = 3
        $summary = 'No validationCommand or scripts/project/validate.ps1 is configured.'
    }

    if ($mode) {
        if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
            throw "Validation working directory does not exist: $workingDirectory"
        }
        $logPath = Join-Path ([IO.Path]::GetTempPath()) ("codex_validation_{0}.log" -f [Guid]::NewGuid().ToString('N'))
        $previousLocation = Get-Location
        try {
            Set-Location -LiteralPath $workingDirectory
            if ($mode -eq 'command') {
                $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $commandDescription 2>&1 | ForEach-Object { $_.ToString() })
            }
            else {
                $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $customValidator 2>&1 | ForEach-Object { $_.ToString() })
            }
            $actualExitCode = $LASTEXITCODE
        }
        finally {
            Set-Location -LiteralPath $previousLocation
        }
        [IO.File]::WriteAllLines($logPath, [string[]]$output, (New-Object Text.UTF8Encoding($false)))
        foreach ($line in $output) { [void]$details.Add([string]$line) }
        if ($actualExitCode -eq 0) {
            $status = 'PASS'
            $summary = 'Validation command completed successfully.'
        }
        else {
            $status = 'FAIL'
            $summary = "Validation command failed with exit code $actualExitCode."
        }
    }
}
catch {
    $status = 'BLOCKED'
    $actualExitCode = 1
    $summary = $_.Exception.Message
    [void]$details.Add($_.Exception.ToString())
}

$completed = [DateTime]::UtcNow
$result = [pscustomobject]@{
    status = $status
    startedAt = $started.ToString('yyyy-MM-ddTHH:mm:ssZ')
    completedAt = $completed.ToString('yyyy-MM-ddTHH:mm:ssZ')
    durationSeconds = [Math]::Round(($completed - $started).TotalSeconds, 3)
    command = $commandDescription
    exitCode = [int]$actualExitCode
    summary = $summary
    details = @($details)
    logPath = $logPath
}
Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
    "驗證狀態：$status（$(ConvertTo-WorkflowStatusZhTw $status)）",
    "結束代碼：$actualExitCode",
    "摘要：$summary",
    "紀錄檔：$logPath"
)
exit $actualExitCode

$ErrorActionPreference = 'Stop'
. .\scripts\workflow\common.ps1
$root = Resolve-WorkflowProjectRoot -ProjectPath (Get-Location).Path

Write-Host "Checking git status..."
$status = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('status', '--porcelain')
foreach ($line in ($status.Output -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $relative = $line.Substring(3).Trim()
    if ($relative.Contains(' -> ')) { $relative = $relative.Split(@(' -> '), [StringSplitOptions]::None)[-1] }
    $relative = $relative.Trim('"').Replace('\', '/')
    $fullPath = Join-Path $root ($relative.Replace('/', '\'))
    Write-Host "Checking relative path: '$relative'"
    try {
        [IO.Path]::GetFullPath($fullPath) | Out-Null
    } catch {
        Write-Host "Error in GetFullPath for $fullPath"
        Write-Host $_.Exception.Message
    }
}
Write-Host "Done checking git status."

Write-Host "Checking config..."
$config = Get-WorkflowConfig -ProjectRoot $root
Write-Host "Done checking config."

Write-Host "Running package script dry run..."
$packageScript = Join-Path '.\scripts\workflow' 'create_handoff_package.ps1'
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $packageScript -ProjectPath $root -Json -DryRun
} catch {
    Write-Host "Error in package script: $_"
}
Write-Host "Done."

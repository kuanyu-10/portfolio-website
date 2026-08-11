[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$requiredFiles = @(
    'AGENTS.md',
    'HANDOFF.md',
    'PROJECT_STATE.json',
    'CHANGELOG_AGENT.md',
    'index.html',
    'scripts\\workflow\\startup.ps1',
    'scripts\\workflow\\shutdown.ps1',
    'scripts\\workflow\\validate_project.ps1'
)

$missing = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path (Get-Location).Path $file) -PathType Leaf)) {
        $missing += $file
    }
}

if ($missing.Count -gt 0) {
    Write-Error ('Workflow validation failed. Missing required file(s): ' + ($missing -join ', '))
    exit 1
}

Write-Output 'Workflow validation passed. Required files are present.'
exit 0
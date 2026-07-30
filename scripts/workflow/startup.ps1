[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$ApplySafePull,
    [switch]$SkipFetch,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $requiredFiles = @('AGENTS.md', 'HANDOFF.md', 'PROJECT_STATE.json')
    foreach ($required in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            throw "Required startup file is missing: $required"
        }
    }

    $null = Get-Content -LiteralPath (Join-Path $root 'AGENTS.md') -Raw -Encoding UTF8
    $handoff = Get-Content -LiteralPath (Join-Path $root 'HANDOFF.md') -Raw -Encoding UTF8
    $state = Read-WorkflowJson -Path (Join-Path $root 'PROJECT_STATE.json')
    $config = Get-WorkflowConfig -ProjectRoot $root
    if (-not (Test-WorkflowGitRepository -ProjectRoot $root)) {
        throw "Project is not a valid Git working tree: $root"
    }

    $git = Get-WorkflowGitStatus -ProjectRoot $root -Fetch:(-not $SkipFetch) -SkipFetchErrors
    $warnings = New-Object System.Collections.ArrayList
    if ($git.FetchStatus -eq 'FAILED') {
        [void]$warnings.Add("Fetch failed; remote comparison may be stale: $($git.FetchMessage)")
    }
    if (-not $git.HasUpstream) { [void]$warnings.Add('Current branch has no upstream.') }
    if ($git.IsDirty) { [void]$warnings.Add('Working tree has uncommitted changes; pull is not allowed.') }
    if ($git.Diverged) { [void]$warnings.Add('Branch has diverged; manual review is required. No merge or rebase was performed.') }
    if ($state.lastComputer -and $state.lastComputer -ne (Get-WorkflowComputerName)) {
        [void]$warnings.Add("Last handoff was created on a different computer: $($state.lastComputer)")
    }
    if ($state.lastKnownCommit -and $git.Commit -and $state.lastKnownCommit -ne $git.Commit) {
        [void]$warnings.Add("PROJECT_STATE.json lastKnownCommit differs from HEAD.")
    }
    if ($handoff -notmatch [regex]::Escape([string]$state.validationStatus)) {
        [void]$warnings.Add('HANDOFF.md and PROJECT_STATE.json may disagree on validation status.')
    }

    $pulled = $false
    if ($ApplySafePull) {
        $safeToPull = (-not $git.IsDirty) -and $git.HasUpstream -and
            ($git.Ahead -eq 0) -and ($git.Behind -gt 0) -and (-not $git.Diverged)
        if ($safeToPull) {
            Invoke-WorkflowGit -ProjectRoot $root -Arguments @('pull', '--ff-only') | Out-Null
            $pulled = $true
            $git = Get-WorkflowGitStatus -ProjectRoot $root
        }
        else {
            [void]$warnings.Add('Safe pull conditions were not all satisfied; no pull was performed.')
        }
    }
    elseif ($git.Behind -gt 0) {
        [void]$warnings.Add('Remote commits are available. Re-run with -ApplySafePull after reviewing the safe-pull conditions.')
    }

    $recommendedTask = 'Review HANDOFF.md and choose the next task.'
    if ($state.nextTasks -and @($state.nextTasks).Count -gt 0) {
        $recommendedTask = [string]@($state.nextTasks)[0]
    }
    $result = [pscustomobject]@{
        status = 'READY'
        project = $(if ($state.project) { [string]$state.project } elseif ($config -and $config.projectName) { [string]$config.projectName } else { Split-Path $root -Leaf })
        projectPath = $root
        computer = Get-WorkflowComputerName
        branch = $git.Branch
        commit = $git.Commit
        workingTree = $(if ($git.IsDirty) { 'DIRTY' } else { 'CLEAN' })
        localAhead = $git.Ahead
        localBehind = $git.Behind
        diverged = $git.Diverged
        upstream = $git.Upstream
        hasUpstream = $git.HasUpstream
        fetched = $git.FetchStatus
        pulled = $pulled
        lastHandoff = [string]$state.updatedAt
        validationStatus = [string]$state.validationStatus
        pushStatus = [string]$state.pushStatus
        recommendedNextTask = $recommendedTask
        warnings = @($warnings)
    }
    $warningText = $(if ($warnings.Count -eq 0) { 'None' } else { $warnings -join ' | ' })
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "Project: $($result.project)",
        "Computer: $($result.computer)",
        "Branch: $($result.branch)",
        "Working Tree: $($result.workingTree)",
        "Local Ahead: $($result.localAhead)",
        "Local Behind: $($result.localBehind)",
        "Diverged: $($result.diverged)",
        "Last Handoff: $($result.lastHandoff)",
        "Validation Status: $($result.validationStatus)",
        "Push Status: $($result.pushStatus)",
        "Recommended Next Task: $($result.recommendedNextTask)",
        "Warnings: $warningText"
    )
    exit 0
}
catch {
    $failure = [pscustomobject]@{ status = 'BLOCKED'; error = $_.Exception.Message; projectPath = $ProjectPath }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @('Status: BLOCKED', "Error: $($_.Exception.Message)")
    exit 1
}

[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$NoCommit,
    [switch]$NoPush,
    [switch]$NoPackage,
    [switch]$AllowValidationFailure,
    [string]$CommitMessage,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Set-PropertyValue {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Write-ShutdownStateFiles {
    param(
        [string]$Root,
        $State,
        $Git,
        [string]$ValidationStatus,
        [string]$PushStatus,
        [string]$PackageStatus,
        [string[]]$Warnings,
        [switch]$DryRun
    )

    $now = Get-WorkflowUtcTimestamp
    $projectName = $(if ($State.project) { [string]$State.project } else { Split-Path $Root -Leaf })
    $stateStatus = 'IN_PROGRESS'
    if ($ValidationStatus -eq 'FAIL') { $stateStatus = 'VALIDATION_FAILED' }
    elseif ($ValidationStatus -eq 'BLOCKED') { $stateStatus = 'BLOCKED' }
    elseif ($ValidationStatus -eq 'PASS') { $stateStatus = 'HANDOFF_READY' }

    Set-PropertyValue -Object $State -Name 'status' -Value $stateStatus
    Set-PropertyValue -Object $State -Name 'workingBranch' -Value $Git.Branch
    Set-PropertyValue -Object $State -Name 'lastKnownCommit' -Value $Git.Commit
    Set-PropertyValue -Object $State -Name 'lastValidatedCommit' -Value $(if ($ValidationStatus -eq 'PASS') { $Git.Commit } else { [string]$State.lastValidatedCommit })
    Set-PropertyValue -Object $State -Name 'lastComputer' -Value (Get-WorkflowComputerName)
    Set-PropertyValue -Object $State -Name 'lastAgent' -Value 'Codex'
    Set-PropertyValue -Object $State -Name 'hasUncommittedChanges' -Value ([bool]$Git.IsDirty)
    Set-PropertyValue -Object $State -Name 'localAheadCount' -Value ([int]$Git.Ahead)
    Set-PropertyValue -Object $State -Name 'localBehindCount' -Value ([int]$Git.Behind)
    Set-PropertyValue -Object $State -Name 'branchDiverged' -Value ([bool]$Git.Diverged)
    Set-PropertyValue -Object $State -Name 'pushStatus' -Value $PushStatus
    Set-PropertyValue -Object $State -Name 'validationStatus' -Value $ValidationStatus
    Set-PropertyValue -Object $State -Name 'packageStatus' -Value $PackageStatus
    Set-PropertyValue -Object $State -Name 'updatedAt' -Value $now

    $nextTasks = @($State.nextTasks)
    if ($nextTasks.Count -eq 0) { $nextTasks = @('Review current changes and define the next highest-leverage task.') }
    $blockerText = $(if (@($State.blockers).Count -gt 0) { (@($State.blockers) -join '; ') } else { '無。' })
    $warningText = $(if ($Warnings.Count -gt 0) { ($Warnings -join '; ') } else { '無。' })
    $handoff = @"
# Project Handoff

## Project

$projectName

## Current Phase

$($State.phase)

## Current Status

$stateStatus

## Last Completed

已執行正式收工檢查；結果以本文件與 `PROJECT_STATE.json` 為準。

## Current Working State

Git working tree: $(if ($Git.IsDirty) { 'DIRTY' } else { 'CLEAN' })。警告：$warningText

## Next Highest-Leverage Tasks

$(($nextTasks | ForEach-Object { "- $_" }) -join [Environment]::NewLine)

## Blockers

$blockerText

## Do Not Touch

依 `AGENTS.md` 與 `workflow.config.json` 的 protectedPaths。

## Required Validation

$ValidationStatus

## Cross-Device Notes

只有 Push Status 為 PUSHED 時，另一台電腦才可把遠端視為最新正式狀態。

## Last Update

- Time: $now
- Agent: Codex
- Computer: $(Get-WorkflowComputerName)
- Branch: $($Git.Branch)
- Commit: $($Git.Commit)
- Push Status: $PushStatus
- Validation Status: $ValidationStatus
- Package Status: $PackageStatus
"@
    $changeLogEntry = @"

## $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm')) — $($State.phase) / $stateStatus

### Changed

- 更新正式交接狀態。

### Validation

- $ValidationStatus

### Decisions

- 依工作流安全規則處理 commit、push 與 package。

### Known Issues

- $warningText

### Git

- Branch: $($Git.Branch)
- Base commit: $($Git.Commit)
- Push status: $PushStatus

### Environment

- Computer: $(Get-WorkflowComputerName)
- Workflow version: $($State.workflowVersion)
"@
    if (-not $DryRun) {
        Write-WorkflowAtomicText -Path (Join-Path $Root 'HANDOFF.md') -Content ($handoff.TrimStart() + [Environment]::NewLine)
        Write-WorkflowJson -Path (Join-Path $Root 'PROJECT_STATE.json') -Value $State
        $changeLogPath = Join-Path $Root 'CHANGELOG_AGENT.md'
        $existing = Get-Content -LiteralPath $changeLogPath -Raw -Encoding UTF8
        Write-WorkflowAtomicText -Path $changeLogPath -Content ($existing.TrimEnd() + $changeLogEntry + [Environment]::NewLine)
    }
}

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    foreach ($required in @('AGENTS.md', 'HANDOFF.md', 'PROJECT_STATE.json', 'CHANGELOG_AGENT.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            throw "Required shutdown file is missing: $required"
        }
        $null = Get-Content -LiteralPath (Join-Path $root $required) -Raw -Encoding UTF8
    }
    $state = Read-WorkflowJson -Path (Join-Path $root 'PROJECT_STATE.json')
    $config = Get-WorkflowConfig -ProjectRoot $root
    if (-not (Test-WorkflowGitRepository -ProjectRoot $root)) {
        throw 'Shutdown requires a valid Git working tree. No repository was created automatically.'
    }

    $git = Get-WorkflowGitStatus -ProjectRoot $root
    if ($git.Diverged) {
        throw 'Branch is diverged. No commit, merge, rebase, reset, or push was attempted.'
    }

    $validationScript = Join-Path $PSScriptRoot 'validate_project.ps1'
    $validationRaw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validationScript -ProjectPath $root -Json 2>$null)
    $validationExitCode = $LASTEXITCODE
    try { $validation = (($validationRaw -join [Environment]::NewLine) | ConvertFrom-Json) }
    catch { throw "Could not parse validation output: $($validationRaw -join ' ')" }
    $validationStatus = [string]$validation.status

    $warnings = New-Object System.Collections.ArrayList
    $excludedFromAdd = New-Object System.Collections.ArrayList
    $safeFiles = New-Object System.Collections.ArrayList
    $maximumSize = 50
    if ($config -and $config.maximumAutoAddFileSizeMB -ne $null) {
        $maximumSize = [double]$config.maximumAutoAddFileSizeMB
    }
    $protectedPaths = @()
    if ($config -and $config.protectedPaths) { $protectedPaths = @($config.protectedPaths) }

    $status = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('status', '--porcelain')
    foreach ($line in ($status.Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
        $relative = $line.Substring(3).Trim()
        if ($relative.Contains(' -> ')) { $relative = $relative.Split(@(' -> '), [StringSplitOptions]::None)[-1] }
        $relative = $relative.Trim('"').Replace('\', '/')
        $fullPath = Join-Path $root ($relative.Replace('/', '\'))
        $reason = ''
        if (Test-WorkflowSensitivePath -RelativePath $relative) { $reason = 'sensitive or conflict file' }
        foreach ($protected in $protectedPaths) {
            if ($relative -like [string]$protected) { $reason = "protected path: $protected"; break }
        }
        if (-not $reason -and (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $size = Get-WorkflowFileSizeMB -Path $fullPath
            if ($size -gt $maximumSize) { $reason = "larger than automatic add limit ($maximumSize MB)" }
            elseif (-not (Test-WorkflowKnownSourceFile -Path $fullPath)) { $reason = 'unknown binary or file type' }
        }
        if ($reason) {
            [void]$excludedFromAdd.Add([pscustomobject]@{ path = $relative; reason = $reason })
            [void]$warnings.Add("Not staged: $relative ($reason)")
        }
        else {
            [void]$safeFiles.Add($relative)
        }
    }

    if ($validationStatus -eq 'FAIL' -or $validationStatus -eq 'BLOCKED') {
        [void]$warnings.Add("Validation status is $validationStatus (exit code $validationExitCode).")
    }
    elseif ($validationStatus -eq 'NOT_CONFIGURED') {
        [void]$warnings.Add('Validation is NOT_CONFIGURED; this is not PASS.')
    }

    $initialPushStatus = $(if ($NoPush -or $NoCommit) { 'NOT_REQUIRED' } else { 'NOT_PUSHED' })
    Write-ShutdownStateFiles -Root $root -State $state -Git $git -ValidationStatus $validationStatus `
        -PushStatus $initialPushStatus -PackageStatus 'NOT_CREATED' -Warnings @($warnings) -DryRun:$DryRun

    if ($DryRun) {
        $dryResult = [pscustomobject]@{
            status = 'DRY_RUN'
            validationStatus = $validationStatus
            validationExitCode = $validationExitCode
            commit = ''
            pushStatus = 'NOT_REQUIRED'
            packageStatus = 'NOT_CREATED'
            zipPath = ''
            zipSha256 = ''
            backupStatus = 'NOT_REQUIRED'
            excludedFromAdd = @($excludedFromAdd)
            warnings = @($warnings)
        }
        Write-WorkflowOutput -Value $dryResult -Json:$Json -TextLines @(
            'Shutdown Status: DRY_RUN',
            "Validation: $validationStatus",
            'Commit: NOT_CREATED',
            'Push: NOT_REQUIRED',
            'Package: NOT_CREATED'
        )
        exit 0
    }

    $validationBlocksCompletion = ($validationStatus -eq 'FAIL' -or $validationStatus -eq 'BLOCKED')
    if ($validationBlocksCompletion -and -not $AllowValidationFailure) {
        $blockedResult = [pscustomobject]@{
            status = 'VALIDATION_FAILED'
            validationStatus = $validationStatus
            validationExitCode = $validationExitCode
            commit = ''
            pushStatus = 'NOT_REQUIRED'
            packageStatus = 'NOT_CREATED'
            excludedFromAdd = @($excludedFromAdd)
            warnings = @($warnings)
        }
        Write-WorkflowOutput -Value $blockedResult -Json:$Json -TextLines @(
            'Shutdown Status: VALIDATION_FAILED',
            "Validation: $validationStatus",
            'No commit, push, or package was performed. Use -AllowValidationFailure only for an explicit diagnostic handoff.'
        )
        exit $validationExitCode
    }

    $commitSha = $git.Commit
    $commitCreated = $false
    if (-not $NoCommit) {
        foreach ($internalFile in @('HANDOFF.md', 'PROJECT_STATE.json', 'CHANGELOG_AGENT.md')) {
            if (-not $safeFiles.Contains($internalFile)) { [void]$safeFiles.Add($internalFile) }
        }
        foreach ($relative in @($safeFiles | Sort-Object -Unique)) {
            Invoke-WorkflowGit -ProjectRoot $root -Arguments @('add', '--', $relative) | Out-Null
        }
        $staged = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('diff', '--cached', '--quiet') -AllowFailure
        if ($staged.ExitCode -eq 1) {
            if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
                $prefix = $(if ($validationStatus -eq 'PASS') { 'chore' } else { 'WIP' })
                $CommitMessage = "${prefix}: update project handoff"
            }
            if ($validationStatus -ne 'PASS' -and $CommitMessage -notmatch '(?i)WIP|未通過驗證') {
                $CommitMessage = "WIP: $CommitMessage"
            }
            Invoke-WorkflowGit -ProjectRoot $root -Arguments @(
                'commit', '-m', $CommitMessage,
                '-m', "Validation: $validationStatus`nWorkflow-generated handoff metadata updated."
            ) | Out-Null
            $commitCreated = $true
            $commitSha = (Invoke-WorkflowGit -ProjectRoot $root -Arguments @('rev-parse', 'HEAD')).Output.Trim()
        }
    }

    $pushStatus = 'NOT_REQUIRED'
    $shouldPush = (-not $NoPush) -and (-not $NoCommit)
    if ($config -and $config.pushOnShutdown -eq $false) { $shouldPush = $false }
    if ($shouldPush) {
        $postCommitGit = Get-WorkflowGitStatus -ProjectRoot $root
        if (-not $postCommitGit.HasUpstream) {
            $pushStatus = 'FAILED'
            [void]$warnings.Add('Push was requested but the current branch has no upstream.')
        }
        else {
            $pushResult = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('push') -AllowFailure
            if ($pushResult.ExitCode -eq 0) {
                $remoteHead = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('ls-remote', 'origin', "refs/heads/$($postCommitGit.Branch)") -AllowFailure
                if ($remoteHead.ExitCode -eq 0 -and $remoteHead.Output -match "^$commitSha\s") {
                    $pushStatus = 'PUSHED'
                }
                else {
                    $pushStatus = 'FAILED'
                    [void]$warnings.Add('Push returned success but remote commit verification did not match.')
                }
            }
            else {
                $pushStatus = 'FAILED'
                [void]$warnings.Add("Push failed: $($pushResult.Output)")
            }
        }
    }

    $packageStatus = 'NOT_CREATED'
    $zipPath = ''
    $zipSha256 = ''
    $backupStatus = 'NOT_REQUIRED'
    $shouldPackage = -not $NoPackage
    if ($config -and $config.createPackageOnShutdown -eq $false) { $shouldPackage = $false }
    if ($shouldPackage) {
        $packageScript = Join-Path $PSScriptRoot 'create_handoff_package.ps1'
        $packageArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $packageScript, '-ProjectPath', $root, '-Json')
        if ($config -and $config.copyPackageToGoogleDrive -eq $false) { $packageArgs += '-NoBackupCopy' }
        $packageRaw = @(& powershell.exe @packageArgs 2>$null)
        $packageExit = $LASTEXITCODE
        try { $packageResult = (($packageRaw -join [Environment]::NewLine) | ConvertFrom-Json) }
        catch { throw "Could not parse package output: $($packageRaw -join ' ')" }
        $packageStatus = [string]$packageResult.status
        $zipPath = [string]$packageResult.zipPath
        $zipSha256 = [string]$packageResult.zipSha256
        $backupStatus = [string]$packageResult.backupStatus
        if ($packageExit -ne 0) {
            if ($packageStatus -ne 'CREATED') { $packageStatus = 'FAILED' }
            [void]$warnings.Add("Package or backup operation returned exit code $packageExit.")
        }
        elseif ($backupStatus -eq 'COPIED_TO_BACKUP') {
            $packageStatus = 'COPIED_TO_BACKUP'
        }
    }

    $finalGit = Get-WorkflowGitStatus -ProjectRoot $root
    Write-ShutdownStateFiles -Root $root -State $state -Git $finalGit -ValidationStatus $validationStatus `
        -PushStatus $pushStatus -PackageStatus $packageStatus -Warnings @($warnings)

    # Persist the final push/package facts without rewriting existing history.
    if (-not $NoCommit) {
        Invoke-WorkflowGit -ProjectRoot $root -Arguments @('add', '--', 'HANDOFF.md', 'PROJECT_STATE.json', 'CHANGELOG_AGENT.md') | Out-Null
        $metadataDiff = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('diff', '--cached', '--quiet') -AllowFailure
        if ($metadataDiff.ExitCode -eq 1) {
            Invoke-WorkflowGit -ProjectRoot $root -Arguments @(
                'commit', '-m', 'chore: record shutdown results',
                '-m', "Validation: $validationStatus`nPush: $pushStatus`nPackage: $packageStatus"
            ) | Out-Null
            $commitSha = (Invoke-WorkflowGit -ProjectRoot $root -Arguments @('rev-parse', 'HEAD')).Output.Trim()
            if ($shouldPush -and $pushStatus -eq 'PUSHED') {
                $metadataPush = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('push') -AllowFailure
                if ($metadataPush.ExitCode -ne 0) {
                    $pushStatus = 'FAILED'
                    [void]$warnings.Add("Final metadata push failed: $($metadataPush.Output)")
                }
            }
        }
    }

    $overallStatus = 'HANDOFF_READY'
    if ($validationStatus -eq 'FAIL') { $overallStatus = 'VALIDATION_FAILED' }
    elseif ($validationStatus -eq 'BLOCKED') { $overallStatus = 'BLOCKED' }
    elseif ($validationStatus -eq 'NOT_CONFIGURED') { $overallStatus = 'IN_PROGRESS' }
    if ($pushStatus -eq 'FAILED' -or $packageStatus -eq 'FAILED') { $overallStatus = 'BLOCKED' }

    $result = [pscustomobject]@{
        status = $overallStatus
        validationStatus = $validationStatus
        validationExitCode = $validationExitCode
        commit = $commitSha
        commitCreated = $commitCreated
        pushStatus = $pushStatus
        packageStatus = $packageStatus
        zipPath = $zipPath
        zipSha256 = $zipSha256
        backupStatus = $backupStatus
        excludedFromAdd = @($excludedFromAdd)
        warnings = @($warnings)
    }
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "Shutdown Status: $overallStatus",
        "Validation: $validationStatus",
        "Commit: $commitSha",
        "Push: $pushStatus",
        "Package: $packageStatus",
        "ZIP: $zipPath",
        "ZIP SHA256: $zipSha256",
        "Backup: $backupStatus",
        "Warnings: $($warnings -join ' | ')"
    )
    if ($overallStatus -eq 'BLOCKED') { exit 1 }
    if ($validationStatus -eq 'FAIL' -or $validationStatus -eq 'BLOCKED') { exit $validationExitCode }
    exit 0
}
catch {
    $failure = [pscustomobject]@{
        status = 'BLOCKED'
        error = $_.Exception.Message
        validationStatus = 'BLOCKED'
        pushStatus = 'FAILED'
        packageStatus = 'FAILED'
    }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @('Shutdown Status: BLOCKED', "Error: $($_.Exception.Message)")
    exit 1
}

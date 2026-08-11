[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [string]$DefaultBranch = 'main',
    [switch]$Force,
    [switch]$DryRun,
    [switch]$Json,
    [switch]$InitializeGit,
    [switch]$CreateLocalConfig,
    [string]$TemplateRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $target = [IO.Path]::GetFullPath($ProjectPath)
    if (-not (Test-Path -LiteralPath $target)) {
        if (-not $DryRun) { Ensure-WorkflowDirectory -Path $target | Out-Null }
    }
    elseif (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Target is not a directory: $target"
    }

    if ([string]::IsNullOrWhiteSpace($TemplateRoot)) {
        $TemplateRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\'))
    }
    else {
        $TemplateRoot = [IO.Path]::GetFullPath($TemplateRoot)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $TemplateRoot 'AGENTS.md') -PathType Leaf)) {
        throw "Template root is invalid: $TemplateRoot"
    }

    $protected = @('AGENTS.md', 'HANDOFF.md', 'PROJECT_STATE.json', 'CHANGELOG_AGENT.md')
    $copyFiles = @(
        'AGENTS.md',
        'HANDOFF.md',
        'PROJECT_STATE.json',
        'PROJECT_STATE.schema.json',
        'CHANGELOG_AGENT.md',
        'workflow.config.example.json'
    )
    $created = New-Object System.Collections.ArrayList
    $overwritten = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    $conflicts = New-Object System.Collections.ArrayList

    foreach ($relative in $copyFiles) {
        $source = Join-Path $TemplateRoot $relative
        $destination = Join-Path $target $relative
        if (Test-Path -LiteralPath $destination) {
            if (($protected -contains $relative) -and -not $Force) {
                [void]$conflicts.Add($relative)
                continue
            }
            if (-not $Force) {
                [void]$skipped.Add($relative)
                continue
            }
            if (-not $DryRun) { Copy-Item -LiteralPath $source -Destination $destination -Force }
            [void]$overwritten.Add($relative)
        }
        else {
            if (-not $DryRun) { Copy-Item -LiteralPath $source -Destination $destination }
            [void]$created.Add($relative)
        }
    }

    if ($conflicts.Count -gt 0) {
        throw "Protected project files already exist; nothing was overwritten: $($conflicts -join ', '). Use -Force only after review."
    }

    foreach ($folder in @('scripts\workflow', 'docs\workflow')) {
        $sourceFolder = Join-Path $TemplateRoot $folder
        $destinationFolder = Join-Path $target $folder
        if (-not $DryRun) { Ensure-WorkflowDirectory -Path $destinationFolder | Out-Null }
        Get-ChildItem -LiteralPath $sourceFolder -File | ForEach-Object {
            $destination = Join-Path $destinationFolder $_.Name
            $relative = ConvertTo-WorkflowRelativePath -Root $target -Path $destination
            if ((Test-Path -LiteralPath $destination) -and -not $Force) {
                [void]$skipped.Add($relative)
            }
            else {
                if (-not $DryRun) { Copy-Item -LiteralPath $_.FullName -Destination $destination -Force }
                if (Test-Path -LiteralPath $destination) { [void]$overwritten.Add($relative) } else { [void]$created.Add($relative) }
            }
        }
    }

    $ignoreChanged = Add-WorkflowGitIgnoreRules `
        -TargetPath (Join-Path $target '.gitignore') `
        -RulesPath (Join-Path $TemplateRoot '.gitignore.workflow') `
        -DryRun:$DryRun
    if ($ignoreChanged) { [void]$created.Add('.gitignore (workflow block)') }

    if ($CreateLocalConfig) {
        $configPath = Join-Path $target 'workflow.config.json'
        if ((Test-Path -LiteralPath $configPath) -and -not $Force) {
            [void]$skipped.Add('workflow.config.json')
        }
        elseif (-not $DryRun) {
            $config = Read-WorkflowJson -Path (Join-Path $TemplateRoot 'workflow.config.example.json')
            $config.projectName = $ProjectName
            $config.defaultBranch = $DefaultBranch
            Write-WorkflowJson -Path $configPath -Value $config
            [void]$created.Add('workflow.config.json (local, ignored)')
        }
    }

    if ($InitializeGit -and -not $DryRun -and -not (Test-WorkflowGitRepository -ProjectRoot $target)) {
        Invoke-WorkflowGit -ProjectRoot $target -Arguments @('init', '-b', $DefaultBranch) | Out-Null
    }

    if (-not $DryRun) {
        $statePath = Join-Path $target 'PROJECT_STATE.json'
        $state = Read-WorkflowJson -Path $statePath
        $state.project = $ProjectName
        $state.status = 'READY'
        $state.workingBranch = $DefaultBranch
        $state.updatedAt = Get-WorkflowUtcTimestamp
        Write-WorkflowJson -Path $statePath -Value $state
        foreach ($required in @('AGENTS.md', 'HANDOFF.md', 'PROJECT_STATE.json', 'CHANGELOG_AGENT.md', 'scripts\workflow\startup.ps1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $target $required) -PathType Leaf)) {
                throw "Initialization validation failed; missing: $required"
            }
        }
        Read-WorkflowJson -Path $statePath | Out-Null
    }

    $result = [pscustomobject]@{
        status = $(if ($DryRun) { 'DRY_RUN' } else { 'READY' })
        projectPath = $target
        projectName = $ProjectName
        defaultBranch = $DefaultBranch
        dryRun = [bool]$DryRun
        gitInitialized = $(if ($DryRun) { $false } else { Test-WorkflowGitRepository -ProjectRoot $target })
        created = @($created)
        overwritten = @($overwritten)
        skipped = @($skipped)
        nextSteps = @(
            'Review and customize AGENTS.md.',
            'Create workflow.config.json from the example when local settings are required.',
            'Configure validationCommand or scripts/project/validate.ps1.',
            'Initialize Git and create a private GitHub repository explicitly.'
        )
    }
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "狀態：$($result.status)（$(ConvertTo-WorkflowStatusZhTw $result.status)）",
        "專案：$($result.projectName)",
        "路徑：$($result.projectPath)",
        "已建立：$($result.created.Count)",
        "已略過：$($result.skipped.Count)",
        '下一步：檢查 AGENTS.md，並設定專案驗證。'
    )
    exit 0
}
catch {
    $failure = [pscustomobject]@{ status = 'FAILED'; error = $_.Exception.Message; projectPath = $ProjectPath }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @("狀態：FAILED（失敗）", "⚠ 目前限制：$($_.Exception.Message)")
    exit 1
}

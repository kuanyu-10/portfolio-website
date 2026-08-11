[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$ActiveHealthCheck,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Test-KnowledgeCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    try { return $null -ne (Get-Command -Name $Command -ErrorAction Stop) }
    catch { return $false }
}

function Resolve-KnowledgePath {
    param([string]$Path, [string]$BasePath)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config = Get-WorkflowConfig -ProjectRoot $root
    $warnings = New-Object System.Collections.ArrayList
    $knowledgeConfig = $null
    if ($config -and $config.PSObject.Properties['knowledgeIntegration']) {
        $knowledgeConfig = $config.knowledgeIntegration
    }

    $obsidian = [pscustomobject]@{
        enabled = $false
        status = 'NOT_CONFIGURED'
        command = ''
        commandAvailable = $false
        vaultConfigured = $false
        vaultAvailable = $false
        projectNoteConfigured = $false
        projectNoteAvailable = $false
        pitfallNoteConfigured = $false
        pitfallNoteAvailable = $false
    }
    $notebookLM = [pscustomobject]@{
        enabled = $false
        status = 'NOT_CONFIGURED'
        command = ''
        commandAvailable = $false
        activeHealthCheck = $false
        doctorStatus = 'NOT_RUN'
    }

    if ($knowledgeConfig -and $knowledgeConfig.PSObject.Properties['obsidian']) {
        $obsidianConfig = $knowledgeConfig.obsidian
        $obsidian.enabled = [bool]$obsidianConfig.enabled
        if ($obsidian.enabled) {
            $obsidian.command = $(if ($obsidianConfig.command) { [string]$obsidianConfig.command } else { 'mcpvault' })
            $obsidian.commandAvailable = Test-KnowledgeCommand -Command $obsidian.command
            $vaultPath = Resolve-KnowledgePath -Path ([string]$obsidianConfig.vaultPath) -BasePath $root
            $obsidian.vaultConfigured = [bool]$vaultPath
            $obsidian.vaultAvailable = [bool]($vaultPath -and (Test-Path -LiteralPath $vaultPath -PathType Container))
            $projectNotePath = ''
            $pitfallNotePath = ''
            if ($vaultPath) {
                $projectNotePath = Resolve-KnowledgePath -Path ([string]$obsidianConfig.projectNotePath) -BasePath $vaultPath
                $pitfallNotePath = Resolve-KnowledgePath -Path ([string]$obsidianConfig.pitfallNotePath) -BasePath $vaultPath
            }
            $obsidian.projectNoteConfigured = [bool]$projectNotePath
            $obsidian.projectNoteAvailable = [bool]($projectNotePath -and (Test-Path -LiteralPath $projectNotePath -PathType Leaf))
            $obsidian.pitfallNoteConfigured = [bool]$pitfallNotePath
            $obsidian.pitfallNoteAvailable = [bool]($pitfallNotePath -and (Test-Path -LiteralPath $pitfallNotePath -PathType Leaf))
            $obsidian.status = 'READY'
            if (-not $obsidian.commandAvailable) {
                $obsidian.status = 'BLOCKED'
                [void]$warnings.Add("Obsidian command is unavailable: $($obsidian.command)")
            }
            if (-not $obsidian.vaultAvailable) {
                $obsidian.status = 'BLOCKED'
                [void]$warnings.Add('Obsidian vault path is missing or unavailable.')
            }
            if ($obsidianConfig.readOnStartup -eq $true -and -not $obsidian.projectNoteAvailable) {
                $obsidian.status = 'BLOCKED'
                [void]$warnings.Add('Obsidian project note is unavailable for startup reading.')
            }
            if ($obsidianConfig.updateOnShutdown -eq $true -and -not $obsidian.pitfallNoteConfigured) {
                $obsidian.status = 'BLOCKED'
                [void]$warnings.Add('Obsidian pitfall note path is not configured.')
            }
        }
    }

    if ($knowledgeConfig -and $knowledgeConfig.PSObject.Properties['notebookLM']) {
        $notebookConfig = $knowledgeConfig.notebookLM
        $notebookLM.enabled = [bool]$notebookConfig.enabled
        if ($notebookLM.enabled) {
            $notebookLM.command = $(if ($notebookConfig.command) { [string]$notebookConfig.command } else { 'nlm' })
            $notebookLM.commandAvailable = Test-KnowledgeCommand -Command $notebookLM.command
            $notebookLM.activeHealthCheck = [bool]($ActiveHealthCheck -or ($notebookConfig.PSObject.Properties['activeHealthCheck'] -and $notebookConfig.activeHealthCheck -eq $true))
            $notebookLM.status = 'READY'
            if (-not $notebookLM.commandAvailable) {
                $notebookLM.status = 'BLOCKED'
                [void]$warnings.Add("NotebookLM command is unavailable: $($notebookLM.command)")
            }
            elseif ($notebookLM.activeHealthCheck) {
                $null = @(& $notebookLM.command doctor 2>&1 | ForEach-Object { $_.ToString() })
                $doctorExitCode = $LASTEXITCODE
                if ($doctorExitCode -eq 0) { $notebookLM.doctorStatus = 'PASS' }
                else {
                    $notebookLM.doctorStatus = 'FAIL'
                    $notebookLM.status = 'BLOCKED'
                    [void]$warnings.Add("NotebookLM health check failed with exit code $doctorExitCode; run nlm login or nlm doctor manually.")
                }
            }
        }
    }

    $enabledCount = @(@($obsidian.enabled, $notebookLM.enabled) | Where-Object { $_ }).Count
    $overallStatus = 'NOT_CONFIGURED'
    if ($enabledCount -gt 0) {
        $overallStatus = 'READY'
        if ($obsidian.status -eq 'BLOCKED' -or $notebookLM.status -eq 'BLOCKED') { $overallStatus = 'BLOCKED' }
    }
    $result = [pscustomobject]@{
        status = $overallStatus
        obsidian = $obsidian
        notebookLM = $notebookLM
        warnings = @($warnings)
    }
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "Knowledge Status: $overallStatus",
        "Obsidian: $($obsidian.status)",
        "NotebookLM: $($notebookLM.status)",
        "Warnings: $(@($warnings) -join ' | ')"
    )
    exit 0
}
catch {
    $failure = [pscustomobject]@{ status = 'BLOCKED'; error = $_.Exception.Message; warnings = @($_.Exception.Message) }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @('Knowledge Status: BLOCKED', "Error: $($_.Exception.Message)")
    exit 1
}

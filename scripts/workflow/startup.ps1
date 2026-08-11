[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$ApplySafePull,
    [switch]$SkipFetch,
    [switch]$CheckKnowledgeServices,
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
        [void]$warnings.Add("Git fetch 失敗，遠端比較可能不是最新：$($git.FetchMessage)")
    }
    if (-not $git.HasUpstream) { [void]$warnings.Add('目前分支沒有 upstream。') }
    if ($git.IsDirty) { [void]$warnings.Add('工作樹有未提交變更，因此不允許 pull。') }
    if ($git.Diverged) { [void]$warnings.Add('分支已分歧，必須人工檢查；未執行 merge 或 rebase。') }
    if ($state.lastComputer -and $state.lastComputer -ne (Get-WorkflowComputerName)) {
        [void]$warnings.Add("上次交接來自另一台電腦：$($state.lastComputer)")
    }
    if ($state.lastKnownCommit -and $git.Commit -and $state.lastKnownCommit -ne $git.Commit) {
        [void]$warnings.Add("PROJECT_STATE.json 的 lastKnownCommit 與 HEAD 不一致。")
    }
    if ($handoff -notmatch [regex]::Escape([string]$state.validationStatus)) {
        [void]$warnings.Add('HANDOFF.md 與 PROJECT_STATE.json 的驗證狀態可能不一致。')
    }

    $knowledgeStatus = 'NOT_CONFIGURED'
    $knowledge = $null
    $knowledgeConfigured = $config -and $config.PSObject.Properties['knowledgeIntegration']
    if ($knowledgeConfigured) {
        $knowledgeConfig = $config.knowledgeIntegration
        $checkOnStartup = -not ($knowledgeConfig.PSObject.Properties['checkOnStartup'] -and $knowledgeConfig.checkOnStartup -eq $false)
        if ($checkOnStartup) {
            $knowledgeScript = Join-Path $PSScriptRoot 'check_knowledge_tools.ps1'
            if (-not (Test-Path -LiteralPath $knowledgeScript -PathType Leaf)) {
                $knowledgeStatus = 'BLOCKED'
                [void]$warnings.Add("知識整合檢查腳本不存在：$knowledgeScript")
            }
            else {
                $knowledgeArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $knowledgeScript, '-ProjectPath', $root, '-Json')
                if ($CheckKnowledgeServices) { $knowledgeArguments += '-ActiveHealthCheck' }
                $previousErrorActionPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    $knowledgeRaw = @(& powershell.exe @knowledgeArguments 2>&1 | ForEach-Object { $_.ToString() })
                    $knowledgeExitCode = $LASTEXITCODE
                }
                finally {
                    $ErrorActionPreference = $previousErrorActionPreference
                }
                try { $knowledge = (($knowledgeRaw -join [Environment]::NewLine) | ConvertFrom-Json) }
                catch { $knowledge = $null }
                if ($knowledge -and $knowledge.PSObject.Properties['status']) {
                    $knowledgeStatus = [string]$knowledge.status
                    foreach ($knowledgeWarning in @($knowledge.warnings)) {
                        if ($knowledgeWarning) { [void]$warnings.Add("知識整合：$knowledgeWarning") }
                    }
                }
                else {
                    $knowledgeStatus = 'BLOCKED'
                    [void]$warnings.Add("知識整合檢查回傳無效輸出（exit code：$knowledgeExitCode）。")
                }
            }
        }
    }
    $vaultGitStatus = 'NOT_CONFIGURED'
    $vaultGit = $null
    if ($knowledgeConfigured -and $knowledgeConfig.PSObject.Properties['obsidian'] -and
        $knowledgeConfig.obsidian.PSObject.Properties['gitSync'] -and $knowledgeConfig.obsidian.gitSync.enabled -eq $true) {
        $vaultScript = Join-Path $PSScriptRoot 'sync_obsidian_vault_git.ps1'
        if (-not (Test-Path -LiteralPath $vaultScript -PathType Leaf)) {
            $vaultGitStatus = 'BLOCKED'
            [void]$warnings.Add("Vault Git 同步腳本不存在：$vaultScript")
        }
        else {
            $vaultArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$vaultScript,'-ProjectPath',$root,'-Mode','Startup','-Json')
            if (-not $ApplySafePull) { $vaultArgs += '-DryRun' }
            $previousErrorActionPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $vaultRaw = @(& powershell.exe @vaultArgs 2>&1 | ForEach-Object { $_.ToString() })
            }
            finally {
                $ErrorActionPreference = $previousErrorActionPreference
            }
            try { $vaultGit = (($vaultRaw -join [Environment]::NewLine) | ConvertFrom-Json) } catch { $vaultGit = $null }
            if ($vaultGit) {
                $vaultGitStatus = [string]$vaultGit.status
                if ($vaultGitStatus -in @('BLOCKED','DIRTY','AHEAD','PREVIEW')) {
                    foreach ($item in @($vaultGit.uncertainties)) { if ($item) { [void]$warnings.Add("Vault Git：$item") } }
                }
            }
            else { $vaultGitStatus = 'BLOCKED'; [void]$warnings.Add('Vault Git 開工同步輸出無法解析。') }
        }
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
            [void]$warnings.Add('安全 pull 條件未全部成立，因此沒有執行 pull。')
        }
    }
    elseif ($git.Behind -gt 0) {
        [void]$warnings.Add('遠端有新 commit；檢查安全條件後，可加上 -ApplySafePull 重新執行。')
    }

    $recommendedTask = '閱讀 HANDOFF.md，並選擇下一個任務。'
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
        knowledgeStatus = $knowledgeStatus
        knowledge = $knowledge
        vaultGitStatus = $vaultGitStatus
        vaultGit = $vaultGit
        recommendedNextTask = $recommendedTask
        warnings = @($warnings)
    }
    $warningText = $(if ($warnings.Count -eq 0) { '無。' } else { $warnings -join ' | ' })
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "專案：$($result.project)",
        "電腦：$($result.computer)",
        "分支：$($result.branch)",
        "工作樹：$($result.workingTree)",
        "本機領先：$($result.localAhead)",
        "本機落後：$($result.localBehind)",
        "是否分歧：$($result.diverged)",
        "上次交接：$($result.lastHandoff)",
        "驗證狀態：$($result.validationStatus)（$(ConvertTo-WorkflowStatusZhTw $result.validationStatus)）",
        "推送狀態：$($result.pushStatus)（$(ConvertTo-WorkflowStatusZhTw $result.pushStatus)）",
        "知識整合：$($result.knowledgeStatus)（$(ConvertTo-WorkflowStatusZhTw $result.knowledgeStatus)）",
        "Vault Git：$($result.vaultGitStatus)（$(ConvertTo-WorkflowStatusZhTw $result.vaultGitStatus)）",
        "建議下一步：$($result.recommendedNextTask)",
        "⚠ 注意事項：$warningText"
    )
    exit 0
}
catch {
    $failure = [pscustomobject]@{ status = 'BLOCKED'; error = $_.Exception.Message; projectPath = $ProjectPath }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @('狀態：BLOCKED（受阻）', "⚠ 目前限制：$($_.Exception.Message)")
    exit 1
}

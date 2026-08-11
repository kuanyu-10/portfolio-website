[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [ValidateSet('Startup','Shutdown')][string]$Mode,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function New-VaultGitResult {
    param([string]$Status, [int]$ChangedFileCount = 0, [string]$Commit = '', [object[]]$Uncertainties = @())
    [pscustomobject]@{ status = $Status; mode = $Mode; changedFileCount = $ChangedFileCount; commit = $Commit; uncertainties = @($Uncertainties) }
}

function Write-VaultGitResult {
    param($Value)
    Write-WorkflowOutput -Value $Value -Json:$Json -TextLines @(
        "Obsidian Vault Git：$($Value.status)（$(ConvertTo-WorkflowStatusZhTw $Value.status)）",
        "變更檔案：$($Value.changedFileCount)",
        "Commit：$($Value.commit)",
        "⚠ 注意事項：$(if (@($Value.uncertainties).Count -eq 0) { '無。' } else { @($Value.uncertainties) -join '；' })"
    )
}

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config = Get-WorkflowConfig -ProjectRoot $root
    $obsidian = $(if ($config -and $config.PSObject.Properties['knowledgeIntegration']) { $config.knowledgeIntegration.obsidian } else { $null })
    $gitSync = $(if ($obsidian -and $obsidian.PSObject.Properties['gitSync']) { $obsidian.gitSync } else { $null })
    if (-not $gitSync -or $gitSync.enabled -ne $true) {
        $result = New-VaultGitResult -Status 'NOT_CONFIGURED' -Uncertainties @('Obsidian Vault Git 同步尚未啟用。')
        Write-VaultGitResult $result
        exit 0
    }
    $vault = [IO.Path]::GetFullPath([string]$obsidian.vaultPath)
    if (-not (Test-Path -LiteralPath $vault -PathType Container) -or -not (Test-WorkflowGitRepository -ProjectRoot $vault)) {
        throw '設定的 Obsidian Vault 不是可用的 Git repository。'
    }
    $git = Get-WorkflowGitStatus -ProjectRoot $vault -Fetch -SkipFetchErrors
    if ($git.FetchStatus -eq 'FAILED') { throw "Vault Git fetch 失敗：$($git.FetchMessage)" }
    if (-not $git.HasUpstream) { throw 'Vault Git 分支沒有 upstream。' }
    if ($git.Diverged) { throw 'Vault Git 已分歧；未自動 merge、rebase、reset 或 push。' }

    if ($Mode -eq 'Startup') {
        if ($git.IsDirty) {
            $result = New-VaultGitResult -Status 'DIRTY' -Uncertainties @('Vault 有未提交變更，因此未執行 pull。請先在原裝置收工。')
            Write-VaultGitResult $result
            exit 0
        }
        if ($git.Ahead -gt 0) {
            $result = New-VaultGitResult -Status 'AHEAD' -Commit $git.Commit -Uncertainties @('Vault 本機有尚未推送的 commit，因此未執行 pull。')
            Write-VaultGitResult $result
            exit 0
        }
        if ($git.Behind -gt 0) {
            if ($DryRun) {
                $result = New-VaultGitResult -Status 'PREVIEW' -Uncertainties @("Vault 落後 $($git.Behind) 個 commit；正式開工時可安全 ff-only pull。")
            }
            else {
                Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('pull', '--ff-only') | Out-Null
                $git = Get-WorkflowGitStatus -ProjectRoot $vault
                $result = New-VaultGitResult -Status 'PULLED' -Commit $git.Commit
            }
            Write-VaultGitResult $result
            exit 0
        }
        $result = New-VaultGitResult -Status 'READY' -Commit $git.Commit
        Write-VaultGitResult $result
        exit 0
    }

    if ($git.Behind -gt 0) { throw 'Vault 遠端有新 commit；請先執行開工同步，不可在收工時直接覆蓋。' }
    $changed = New-Object System.Collections.ArrayList
    foreach ($args in @(@('-c','core.quotepath=false','diff','--name-only','HEAD'), @('-c','core.quotepath=false','diff','--cached','--name-only'), @('-c','core.quotepath=false','ls-files','--others','--exclude-standard'))) {
        $out = Invoke-WorkflowGit -ProjectRoot $vault -Arguments $args
        foreach ($path in @($out.Output -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($path) -and -not $changed.Contains($path)) { [void]$changed.Add($path) }
        }
    }
    if ($changed.Count -eq 0) {
        $result = New-VaultGitResult -Status 'NO_CHANGES' -Commit $git.Commit
        Write-VaultGitResult $result
        exit 0
    }
    $maximumMB = $(if ($gitSync.PSObject.Properties['maximumAutoAddFileSizeMB']) { [double]$gitSync.maximumAutoAddFileSizeMB } else { 10.0 })
    $blocked = New-Object System.Collections.ArrayList
    $secretPatterns = @(
        '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----', 'gh[pousr]_[A-Za-z0-9_]{20,}',
        'github_pat_[A-Za-z0-9_]{20,}', 'sk-[A-Za-z0-9_-]{20,}',
        '(?i)(password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*[^\s]{6,}'
    )
    foreach ($relative in @($changed)) {
        if ($relative -match '(?i)(^|/)(\.env($|\.)|.*(credential|secret|token|cookie|session).*)' -or $relative -match '(?i)\.(pem|key|pfx|p12)$') {
            [void]$blocked.Add("敏感檔名：$relative")
            continue
        }
        $full = Join-Path $vault ($relative.Replace('/', '\'))
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            if ((Get-WorkflowFileSizeMB -Path $full) -gt $maximumMB) { [void]$blocked.Add("超過 $maximumMB MB：$relative"); continue }
            if ((Get-Item -LiteralPath $full).Length -le 5MB) {
                $hits = Select-String -LiteralPath $full -Pattern $secretPatterns -ErrorAction SilentlyContinue
                if ($hits) { [void]$blocked.Add("疑似敏感內容：$relative") }
            }
        }
    }
    if ($blocked.Count -gt 0) { throw ('安全掃描阻擋自動提交：' + ($blocked -join '；')) }
    if ($DryRun) {
        $result = New-VaultGitResult -Status 'PREVIEW' -ChangedFileCount $changed.Count -Commit $git.Commit
        Write-VaultGitResult $result
        exit 0
    }
    foreach ($relative in @($changed | Sort-Object -Unique)) {
        Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('add', '--', $relative) | Out-Null
    }
    $staged = Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('diff','--cached','--quiet') -AllowFailure
    if ($staged.ExitCode -eq 1) {
        $message = 'docs: sync Obsidian vault ' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
        Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('commit','-m',$message) | Out-Null
    }
    $commit = (Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('rev-parse','HEAD')).Output.Trim()
    $push = Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('push') -AllowFailure
    if ($push.ExitCode -ne 0) { throw "Vault push 失敗：$($push.Output)" }
    $remote = Invoke-WorkflowGit -ProjectRoot $vault -Arguments @('ls-remote','origin',"refs/heads/$($git.Branch)") -AllowFailure
    if ($remote.ExitCode -ne 0 -or $remote.Output -notmatch "^$commit\s") { throw 'Vault push 後遠端 SHA 驗證不一致。' }
    $result = New-VaultGitResult -Status 'PUSHED' -ChangedFileCount $changed.Count -Commit $commit
    Write-VaultGitResult $result
    exit 0
}
catch {
    $result = New-VaultGitResult -Status 'BLOCKED' -Uncertainties @($_.Exception.Message)
    Write-VaultGitResult $result
    exit 1
}

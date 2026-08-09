Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-WorkflowUtcTimestamp {
    return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-WorkflowFileTimestamp {
    return [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')
}

function Get-WorkflowComputerName {
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        return $env:COMPUTERNAME
    }
    return [Environment]::MachineName
}

function Get-WorkflowVersion {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $localVersion = Join-Path $ProjectRoot 'VERSION'
    if (Test-Path -LiteralPath $localVersion -PathType Leaf) {
        return (Get-Content -LiteralPath $localVersion -Raw -Encoding UTF8).Trim()
    }
    $statePath = Join-Path $ProjectRoot 'PROJECT_STATE.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Read-WorkflowJson -Path $statePath
        if ($state.workflowVersion) { return [string]$state.workflowVersion }
    }
    return '0.3.0'
}
function ConvertTo-WorkflowStatusZhTw {
    param([AllowEmptyString()][string]$Status)

    $labels = @{
        'READY' = '就緒'; 'PASS' = '通過'; 'FAIL' = '失敗'; 'FAILED' = '失敗'
        'BLOCKED' = '受阻'; 'NOT_CONFIGURED' = '尚未設定'; 'NOT_AVAILABLE' = '不可用'
        'NOT_TESTED' = '尚未測試'; 'NOT_REQUIRED' = '不需要'; 'NOT_CREATED' = '未建立'
        'NOT_PUSHED' = '未推送'; 'PUSHED' = '已推送'; 'CREATED' = '已建立'
        'COPIED_TO_BACKUP' = '已複製至備份'; 'IN_PROGRESS' = '進行中'; 'HANDOFF_READY' = '可交接'
        'VALIDATION_FAILED' = '驗證失敗'; 'NO_SOURCES' = '沒有來源'; 'DRAFT_CREATED' = '草稿已建立'
        'AUTO_REVIEWED' = '低風險已自動審核'; 'REVIEW_REQUIRED' = '需要快速審核'; 'APPROVED' = '已通過審核'
        'SKIPPED' = '已略過'; 'UNKNOWN' = '未知'; 'DRY_RUN' = '模擬執行'; 'UNINITIALIZED' = '尚未初始化'; 'PREVIEW' = '預覽'; 'NO_CHANGES' = '沒有變更'; 'CONFIGURED' = '已設定'; 'SOURCE_UPDATED' = '來源已更新'; 'REGISTERED' = '已登錄'; 'PARTIAL' = '部分完成'
    }
    if ($labels.ContainsKey($Status)) { return [string]$labels[$Status] }
    if ([string]::IsNullOrWhiteSpace($Status)) { return '未提供' }
    return '未定義狀態'
}

function Resolve-WorkflowProjectRoot {
    param([string]$ProjectPath = (Get-Location).Path)

    $resolved = [IO.Path]::GetFullPath($ProjectPath)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Project path does not exist: $resolved"
    }
    $gitResult = Invoke-WorkflowGit -ProjectRoot $resolved -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if ($gitResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitResult.Output)) {
        return [IO.Path]::GetFullPath($gitResult.Output.Trim())
    }
    return $resolved
}

function Read-WorkflowJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file not found: $Path"
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        throw "Invalid JSON in '$Path': $($_.Exception.Message)"
    }
}

function Write-WorkflowAtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    Ensure-WorkflowDirectory -Path $parent | Out-Null
    $temporaryPath = Join-Path $parent ('.' + [IO.Path]::GetFileName($fullPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, $Content, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $backupPath = $fullPath + '.' + [Guid]::NewGuid().ToString('N') + '.bak'
            try {
                [IO.File]::Replace($temporaryPath, $fullPath, $backupPath, $true)
            }
            finally {
                if (Test-Path -LiteralPath $backupPath) {
                    Remove-Item -LiteralPath $backupPath -Force
                }
            }
        }
        else {
            [IO.File]::Move($temporaryPath, $fullPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Write-WorkflowJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 20
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-WorkflowAtomicText -Path $Path -Content ($json + [Environment]::NewLine)
}

function Ensure-WorkflowDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw "A file exists where a directory is required: $fullPath"
        }
        return $fullPath
    }
    return (New-Item -ItemType Directory -Path $fullPath -Force).FullName
}

function Invoke-WorkflowGit {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $previousLocation = Get-Location
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git executable was not found on PATH.'
        }
        Set-Location -LiteralPath $ProjectRoot
        $ErrorActionPreference = 'Continue'
        $outputLines = @(& git @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        $output = ($outputLines -join [Environment]::NewLine).TrimEnd()
    }
    catch {
        $exitCode = 127
        $output = $_.Exception.Message
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Set-Location -LiteralPath $previousLocation
    }
    $result = [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = [string]$output
        Arguments = @($Arguments)
    }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command failed ($($result.ExitCode)): git $($Arguments -join ' ')`n$($result.Output)"
    }
    return $result
}

function Test-WorkflowGitRepository {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $result = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', '--is-inside-work-tree') -AllowFailure
    return ($result.ExitCode -eq 0 -and $result.Output.Trim() -eq 'true')
}

function Get-WorkflowGitStatus {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [switch]$Fetch,
        [switch]$SkipFetchErrors
    )

    if (-not (Test-WorkflowGitRepository -ProjectRoot $ProjectRoot)) {
        return [pscustomobject]@{
            IsRepository = $false
            Branch = ''
            Commit = ''
            Remote = ''
            Upstream = ''
            HasUpstream = $false
            IsDirty = $false
            StatusShort = ''
            Ahead = 0
            Behind = 0
            Diverged = $false
            FetchStatus = 'NOT_APPLICABLE'
            FetchMessage = ''
        }
    }

    $fetchStatus = 'SKIPPED'
    $fetchMessage = ''
    if ($Fetch) {
        $fetchResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('fetch', '--prune') -AllowFailure
        if ($fetchResult.ExitCode -eq 0) {
            $fetchStatus = 'SUCCESS'
        }
        else {
            $fetchStatus = 'FAILED'
            $fetchMessage = $fetchResult.Output
            if (-not $SkipFetchErrors) {
                throw "Git fetch failed: $fetchMessage"
            }
        }
    }

    $branchResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('branch', '--show-current') -AllowFailure
    $commitResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', 'HEAD') -AllowFailure
    $remoteResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('remote', 'get-url', 'origin') -AllowFailure
    $upstreamResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -AllowFailure
    $statusResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('-c', 'core.quotePath=false', 'status', '--short', '--branch') -AllowFailure
    $porcelainResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('-c', 'core.quotePath=false', 'status', '--porcelain') -AllowFailure

    $hasUpstream = ($upstreamResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($upstreamResult.Output))
    $ahead = 0
    $behind = 0
    if ($hasUpstream) {
        $countsResult = Invoke-WorkflowGit -ProjectRoot $ProjectRoot -Arguments @('rev-list', '--left-right', '--count', 'HEAD...@{u}') -AllowFailure
        if ($countsResult.ExitCode -eq 0 -and $countsResult.Output -match '^\s*(\d+)\s+(\d+)\s*$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
        }
    }

    return [pscustomobject]@{
        IsRepository = $true
        Branch = $branchResult.Output.Trim()
        Commit = $(if ($commitResult.ExitCode -eq 0) { $commitResult.Output.Trim() } else { '' })
        Remote = $(if ($remoteResult.ExitCode -eq 0) { $remoteResult.Output.Trim() } else { '' })
        Upstream = $(if ($hasUpstream) { $upstreamResult.Output.Trim() } else { '' })
        HasUpstream = $hasUpstream
        IsDirty = (-not [string]::IsNullOrWhiteSpace($porcelainResult.Output))
        StatusShort = $statusResult.Output
        Ahead = $ahead
        Behind = $behind
        Diverged = ($ahead -gt 0 -and $behind -gt 0)
        FetchStatus = $fetchStatus
        FetchMessage = $fetchMessage
    }
}

function Test-WorkflowSensitivePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('\', '/')
    $name = [IO.Path]::GetFileName($normalized)
    $patterns = @(
        '^\.env($|\.)',
        '\.(key|pem|p12|pfx)$',
        '(^|[._-])(credential|credentials|secret|secrets|token|tokens)([._-]|$)',
        'conflicted copy',
        '衝突的副本'
    )
    foreach ($pattern in $patterns) {
        if ($name -match $pattern -or $normalized -match $pattern) { return $true }
    }
    return $false
}

function Test-WorkflowKnownSourceFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $known = @(
        '', '.txt', '.md', '.json', '.jsonc', '.xml', '.yml', '.yaml', '.toml', '.ini',
        '.cfg', '.conf', '.csv', '.tsv', '.ps1', '.psm1', '.bat', '.cmd', '.sh',
        '.py', '.js', '.jsx', '.ts', '.tsx', '.cs', '.cpp', '.c', '.h', '.hpp',
        '.java', '.kt', '.rs', '.go', '.rb', '.php', '.html', '.css', '.scss',
        '.sql', '.gd', '.tscn', '.tres', '.svg', '.gitignore', '.gitattributes'
    )
    return ($known -contains $extension)
}

function Get-WorkflowFileSizeMB {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [Math]::Round(((Get-Item -LiteralPath $Path).Length / 1MB), 3)
}

function Get-WorkflowSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-WorkflowRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside root: $pathFull"
    }
    return $pathFull.Substring($rootFull.Length).Replace('\', '/')
}

function Write-WorkflowOutput {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [switch]$Json,
        [string[]]$TextLines
    )

    if ($Json) {
        $Value | ConvertTo-Json -Depth 20 -Compress
    }
    elseif ($TextLines) {
        $TextLines | ForEach-Object { Write-Output $_ }
    }
    else {
        $Value | Format-List | Out-String | Write-Output
    }
}

function Get-WorkflowConfig {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $path = Join-Path $ProjectRoot 'workflow.config.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return Read-WorkflowJson -Path $path
    }
    return $null
}

function Add-WorkflowGitIgnoreRules {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$RulesPath,
        [switch]$DryRun
    )

    $markerStart = '# BEGIN CODEX CROSS-DEVICE WORKFLOW'
    $markerEnd = '# END CODEX CROSS-DEVICE WORKFLOW'
    $rules = (Get-Content -LiteralPath $RulesPath -Raw -Encoding UTF8).Trim()
    $existing = ''
    if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
        $existing = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8
    }
    if ($existing.Contains($markerStart)) { return $false }
    $separator = ''
    if (-not [string]::IsNullOrEmpty($existing) -and -not $existing.EndsWith("`n")) {
        $separator = [Environment]::NewLine
    }
    $content = $existing + $separator + $markerStart + [Environment]::NewLine +
        $rules + [Environment]::NewLine + $markerEnd + [Environment]::NewLine
    if (-not $DryRun) {
        Write-WorkflowAtomicText -Path $TargetPath -Content $content
    }
    return $true
}

function Get-WorkflowKnowledgeProfile {
    param([string]$ProjectRoot,$Config=$null)
    if(-not $Config){$Config=Get-WorkflowConfig -ProjectRoot $ProjectRoot}
    $allowed=@('game','website','web-application','tool','general')
    $type=''
    if($Config-and$Config.PSObject.Properties['knowledgeProfile']-and$Config.knowledgeProfile.PSObject.Properties['projectType']){
        $type=([string]$Config.knowledgeProfile.projectType).Trim().ToLowerInvariant()
    }
    if([string]::IsNullOrWhiteSpace($type)){
        return [pscustomobject]@{status='BLOCKED';projectType='';sections=@();forbiddenSections=@();message='尚未設定 knowledgeProfile.projectType；為避免跨專案內容混入，本次停止整理。'}
    }
    if($allowed-notcontains$type){
        return [pscustomobject]@{status='BLOCKED';projectType=$type;sections=@();forbiddenSections=@();message="不支援的專案類型：$type。允許值：$($allowed -join ', ')。"}
    }
    $sections=switch($type){
        'game' {@('專案介紹','故事與世界觀','角色與 NPC','魔物','招式與戰鬥','城鎮與場景','系統與玩法','物品裝備','目前進度','優化與建議')}
        'website' {@('專案介紹','網站目標','頁面與內容','使用流程','介面與導覽','部署與維護','目前進度','優化與建議')}
        'web-application' {@('專案介紹','產品功能','帳號與權限','資料流程','外部整合','操作方式','部署與維護','目前進度','優化與建議')}
        'tool' {@('專案介紹','工具用途','安裝與設定','指令與流程','安全界線','外部整合','維護與疑難排解','目前進度','優化與建議')}
        default {@('專案介紹','主要內容','目前進度','優化與建議','待處理事項')}
    }
    $forbidden=$(if($type-eq'game'){@()}else{@('故事與世界觀','角色與 NPC','魔物','招式與戰鬥','城鎮與場景','物品裝備')})
    [pscustomobject]@{status='READY';projectType=$type;sections=@($sections);forbiddenSections=@($forbidden);message=''}
}
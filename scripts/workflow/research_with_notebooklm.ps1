[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$DraftPath = '',
    [switch]$Preview,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function New-ResearchResult {
    param([string]$Status, [string]$DraftRelativePath = '', [string]$NotebookUrl = '', [object[]]$Uncertainties = @())
    [pscustomobject]@{ status = $Status; draftRelativePath = $DraftRelativePath; notebookUrl = $NotebookUrl; uncertainties = @($Uncertainties) }
}

function Get-JsonAnswer {
    param($Value)
    foreach ($name in @('answer', 'text', 'content', 'response')) {
        if ($Value -and $Value.PSObject.Properties[$name] -and -not [string]::IsNullOrWhiteSpace([string]$Value.$name)) {
            return [string]$Value.$name
        }
    }
    return ($Value | ConvertTo-Json -Depth 20)
}

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config = Get-WorkflowConfig -ProjectRoot $root
    $knowledge = $(if ($config -and $config.PSObject.Properties['knowledgeIntegration']) { $config.knowledgeIntegration } else { $null })
    $nlm = $(if ($knowledge -and $knowledge.PSObject.Properties['notebookLM']) { $knowledge.notebookLM } else { $null })
    $digest = $(if ($knowledge -and $knowledge.PSObject.Properties['digest']) { $knowledge.digest } else { $null })
    if (-not $nlm -or $nlm.enabled -ne $true -or $nlm.useForResearch -ne $true) {
        $result = New-ResearchResult -Status 'NOT_CONFIGURED' -Uncertainties @('NotebookLM 研究尚未啟用。')
        Write-WorkflowOutput -Value $result -Json:$Json -TextLines @('NotebookLM 研究：NOT_CONFIGURED（尚未設定）', '⚠ 目前限制：NotebookLM 研究尚未啟用。')
        exit 0
    }
    $notebookId = [string]$nlm.notebookId
    if ([string]::IsNullOrWhiteSpace($notebookId)) { throw '尚未設定 NotebookLM notebookId。' }
    $command = [string]$nlm.command
    if ([string]::IsNullOrWhiteSpace($command) -or -not (Get-Command $command -ErrorAction SilentlyContinue)) { throw '找不到 NotebookLM CLI 命令。' }
    $vaultPath = [IO.Path]::GetFullPath([string]$knowledge.obsidian.vaultPath).TrimEnd('\')
    $draftDirectory = [IO.Path]::GetFullPath((Join-Path $vaultPath ([string]$digest.draftDirectoryPath)))
    if ([string]::IsNullOrWhiteSpace($DraftPath)) {
        $candidate = @(Get-ChildItem -LiteralPath $draftDirectory -File -Filter '*.md' -ErrorAction SilentlyContinue | Where-Object {
            $raw = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
            $raw -match '(?m)^status:\s*draft\s*$' -and $raw -notmatch '(?m)^notebookLMResearchAt:'
        } | Sort-Object LastWriteTimeUtc | Select-Object -First 1)
        if ($candidate.Count -eq 0) {
            $result = New-ResearchResult -Status 'NO_SOURCES' -NotebookUrl ("https://notebooklm.google.com/notebook/$notebookId") -Uncertainties @('沒有等待 NotebookLM 研究的草稿。')
            Write-WorkflowOutput -Value $result -Json:$Json -TextLines @('NotebookLM 研究：NO_SOURCES（沒有來源）', '⚠ 注意事項：沒有等待 NotebookLM 研究的草稿。')
            exit 0
        }
        $draftFull = $candidate[0].FullName
    }
    else {
        $draftFull = $(if ([IO.Path]::IsPathRooted($DraftPath)) { [IO.Path]::GetFullPath($DraftPath) } else { [IO.Path]::GetFullPath((Join-Path $vaultPath $DraftPath)) })
    }
    if (-not ($draftFull.StartsWith(($draftDirectory.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase))) { throw '研究草稿必須位於設定的待確認摘要目錄。' }
    if (-not (Test-Path -LiteralPath $draftFull -PathType Leaf)) { throw '找不到研究草稿。' }
    $relative = ConvertTo-WorkflowRelativePath -Root $vaultPath -Path $draftFull
    $notebookUrl = "https://notebooklm.google.com/notebook/$notebookId"
    if ($Preview) {
        $result = New-ResearchResult -Status 'PREVIEW' -DraftRelativePath $relative -NotebookUrl $notebookUrl
        Write-WorkflowOutput -Value $result -Json:$Json -TextLines @('NotebookLM 研究：PREVIEW（預覽）', "草稿：$relative", "Notebook：$notebookUrl", '⚠ 注意事項：無；預覽未上傳來源或修改草稿。')
        exit 0
    }
    $addText = & $command source add $notebookId --file $draftFull --title ([IO.Path]::GetFileNameWithoutExtension($draftFull)) --wait --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "NotebookLM 上傳來源失敗：$($addText.Trim())" }
    $addResult = $addText | ConvertFrom-Json
    $sourceId = [string]$(if ($addResult.PSObject.Properties['source_id']) { $addResult.source_id } elseif ($addResult.PSObject.Properties['id']) { $addResult.id } else { '' })
    $prompt = '請只根據提供的來源，以繁體中文整理：1. 已確認事實；2. 推論與依據；3. 來源間矛盾；4. 待確認事項；5. 可重用知識。每一項都要標示引用依據；不可把推論寫成事實。'
    if ($nlm.PSObject.Properties['researchPrompt'] -and -not [string]::IsNullOrWhiteSpace([string]$nlm.researchPrompt)) { $prompt = [string]$nlm.researchPrompt }
    $queryArgs = @('notebook', 'query', $notebookId, $prompt, '--json')
    if (-not [string]::IsNullOrWhiteSpace($sourceId)) { $queryArgs += @('--source-ids', $sourceId) }
    $queryText = & $command @queryArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "NotebookLM 研究失敗：$($queryText.Trim())" }
    $queryResult = $queryText | ConvertFrom-Json
    $answer = Get-JsonAnswer -Value $queryResult
    $raw = Get-Content -LiteralPath $draftFull -Raw -Encoding UTF8
    $stamp = Get-WorkflowUtcTimestamp
    $raw = $raw -replace '(?m)^reviewedAt:.*\r?\n?', ''
    $raw = $raw -replace '(?m)^reviewedBy:.*\r?\n?', ''
    $raw = $raw -replace '(?m)^status:\s*(draft|reviewed)\s*$', "status: draft`r`nnotebookLMResearchAt: $stamp"
    $raw = $raw -replace '(?m)^riskLevel:\s*\S+\s*$', 'riskLevel: high'
    $raw = $raw -replace '(?m)^reviewMode:\s*\S+\s*$', 'reviewMode: manual-required'
    $append = "`r`n`r`n## NotebookLM 研究結果`r`n`r`n> ⚠ 這是來源式 AI 研究結果，仍須人工核對引用；核對完成後才能把 status 改為 reviewed。`r`n`r`n$answer`r`n"
    Write-WorkflowAtomicText -Path $draftFull -Content ($raw.TrimEnd() + $append)
    $result = New-ResearchResult -Status 'RESEARCHED' -DraftRelativePath $relative -NotebookUrl $notebookUrl
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @('NotebookLM 研究：RESEARCHED（研究結果已寫入草稿）', "草稿：$relative", "Notebook：$notebookUrl", '⚠ 需要你確認：研究結果仍須人工核對，尚未成為正式知識。')
    exit 0
}
catch {
    $result = New-ResearchResult -Status 'BLOCKED' -Uncertainties @($_.Exception.Message)
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @('NotebookLM 研究：BLOCKED（受阻）', "⚠ 目前限制：$($_.Exception.Message)")
    exit 1
}

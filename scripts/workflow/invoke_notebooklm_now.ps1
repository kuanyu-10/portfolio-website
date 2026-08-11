[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$steps = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList

function Invoke-JsonWorkflowScript([string]$Name,[string]$ScriptPath,[string[]]$Arguments) {
    $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments -Json 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $value = $null
    try { $value = ($raw -join [Environment]::NewLine) | ConvertFrom-Json }
    catch { [void]$warnings.Add("$Name 的輸出無法解析。") }
    [void]$steps.Add([pscustomobject]@{ name=$Name; exitCode=$exitCode; result=$value })
    if ($exitCode -ne 0) { throw "$Name 執行失敗（exit code $exitCode）：$($raw -join ' ')" }
    return $value
}

try {
    $root = [IO.Path]::GetFullPath($ProjectPath)
    $configPath = Join-Path $root 'workflow.config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw '找不到 workflow.config.json；請先執行「導入專案.cmd」。' }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $notebook = $config.knowledgeIntegration.notebookLM
    if (-not $notebook -or $notebook.enabled -ne $true) { throw 'NotebookLM 尚未啟用；請重新執行「導入專案.cmd」並在 NotebookLM 選擇 y。' }
    if ([string]::IsNullOrWhiteSpace([string]$notebook.notebookId)) { throw '尚未建立專案 Notebook；請重新執行導入流程完成 NotebookLM 設定。' }

    $nlmCommand = [string]$notebook.command
    if ([string]::IsNullOrWhiteSpace($nlmCommand) -or -not (Test-Path -LiteralPath $nlmCommand -PathType Leaf)) {
        $nlmExecutable = Get-Command nlm.exe -ErrorAction SilentlyContinue
        if ($nlmExecutable) { $nlmCommand = $nlmExecutable.Source }
    }
    if ([string]::IsNullOrWhiteSpace($nlmCommand)) { throw '找不到 nlm；請先執行「導入專案.cmd」補齊外部工具。' }

    $doctorRaw = @(& $nlmCommand doctor 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) {
        Write-Output 'NotebookLM 憑證需要更新，現在開啟登入流程。請在瀏覽器完成 Google 授權。'
        & $nlmCommand login
        if ($LASTEXITCODE -ne 0) { throw 'NotebookLM 登入未完成。' }
        & $nlmCommand doctor | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'NotebookLM 登入後健康檢查仍未通過。' }
    }
    [void]$steps.Add([pscustomobject]@{ name='NotebookLM 登入'; exitCode=0; result=[pscustomobject]@{status='READY'} })

    $sourceSync = Invoke-JsonWorkflowScript -Name '白話摘要來源同步' -ScriptPath (Join-Path $root 'scripts\workflow\sync_knowledge_notebooklm.ps1') -Arguments @('-ProjectPath',$root)

    $hub = $config.knowledgeHubSync
    if ($hub -and $hub.enabled -eq $true -and $hub.notebookLMQueueEnabled -eq $true) {
        $queue = Invoke-JsonWorkflowScript -Name '網站 NotebookLM 研究佇列' -ScriptPath (Join-Path $root 'scripts\workflow\sync_knowledge_hub.ps1') -Arguments @('-ProjectPath',$root,'-ProcessNotebookLM')
    } else {
        [void]$steps.Add([pscustomobject]@{ name='網站 NotebookLM 研究佇列'; exitCode=0; result=[pscustomobject]@{status='SKIPPED'} })
        [void]$warnings.Add('網站研究佇列尚未啟用；本次只同步專案白話摘要。')
    }

    $result = [pscustomobject]@{ status=$(if($warnings.Count){'PASS_WITH_NOTES'}else{'PASS'}); projectPath=$root; steps=@($steps); warnings=@($warnings) }
    if ($Json) { $result | ConvertTo-Json -Depth 20 }
    else {
        Write-Output "NotebookLM 立即同步：$($result.status)"
        foreach ($step in $steps) { Write-Output "- $($step.name)：$(if($step.result){$step.result.status}else{'UNKNOWN'})" }
        Write-Output "注意事項：$(if($warnings.Count){$warnings -join '；'}else{'無。'})"
    }
    exit 0
}
catch {
    $result = [pscustomobject]@{ status='BLOCKED'; error=$_.Exception.Message; steps=@($steps); warnings=@($warnings) }
    if ($Json) { $result | ConvertTo-Json -Depth 20 }
    else { Write-Output 'NotebookLM 立即同步：BLOCKED'; Write-Output "目前限制：$($_.Exception.Message)" }
    exit 1
}

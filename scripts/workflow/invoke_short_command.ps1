[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('開','收','換','整','全整')]
    [string]$Command,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$CommitMessage = 'chore: 收工同步',
    [switch]$Preview,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
$steps = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList
if($Command-eq'全整'){
    $config=Get-WorkflowConfig -ProjectRoot $root
    $profile=Get-WorkflowKnowledgeProfile -ProjectRoot $root -Config $config
    if($profile.status-ne'READY'){
        $blocked=[pscustomobject]@{status='BLOCKED';command=$Command;projectPath=$root;projectType=[string]$profile.projectType;steps=@();warnings=@([string]$profile.message)}
        if($Json){$blocked|ConvertTo-Json -Depth 10}else{Write-Output '工作流口令「全整」：BLOCKED';Write-Output "⚠ 目前限制：$($profile.message)"}
        exit 1
    }
}

function Invoke-WorkflowStep {
    param([string]$Name,[string]$Script,[string[]]$Arguments)
    $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments -Json 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $value = $null
    try { $value = (($raw -join [Environment]::NewLine) | ConvertFrom-Json) }
    catch { [void]$warnings.Add("$Name 輸出無法解析：$($raw -join ' ')") }
    [void]$steps.Add([pscustomobject]@{name=$Name;exitCode=$exitCode;result=$value})
    if ($exitCode -ne 0) { [void]$warnings.Add("$Name 執行未完全成功（exit code：$exitCode）。") }
}

switch ($Command) {
    '開' {
        Invoke-WorkflowStep '安全開工' (Join-Path $PSScriptRoot 'startup.ps1') @('-ProjectPath',$root,'-ApplySafePull')
    }
    '全整' {
        if ($Preview) {
            Invoke-WorkflowStep '白話內容預覽' (Join-Path $PSScriptRoot 'preview_project_overview.ps1') @('-ProjectPath',$root)
        }
        else {
            Invoke-WorkflowStep '建立全專案內部分類' (Join-Path $PSScriptRoot 'build_project_catalog.ps1') @('-ProjectPath',$root)
            Invoke-WorkflowStep '發布全專案整理並同步' (Join-Path $PSScriptRoot 'invoke_knowledge_cycle.ps1') @('-ProjectPath',$root)
        }
    }
    '整' {
        $args = @('-ProjectPath',$root)
        if ($Preview) { $args += '-Preview' }
        Invoke-WorkflowStep '強制統整、發布安全摘要與同步' (Join-Path $PSScriptRoot 'invoke_knowledge_cycle.ps1') $args
    }
    '收' {
        $cycleArgs = @('-ProjectPath',$root)
        if ($Preview) { $cycleArgs += '-Preview' }
        Invoke-WorkflowStep '自動統整、發布安全摘要與同步' (Join-Path $PSScriptRoot 'invoke_knowledge_cycle.ps1') $cycleArgs
        $shutdownArgs = @('-ProjectPath',$root,'-CommitMessage',$CommitMessage)
        if ($Preview) { $shutdownArgs += @('-DryRun','-NoPush','-NoPackage') }
        Invoke-WorkflowStep '正式收工' (Join-Path $PSScriptRoot 'shutdown.ps1') $shutdownArgs
    }
    '換' {
        $cycleArgs = @('-ProjectPath',$root)
        if ($Preview) { $cycleArgs += '-Preview' }
        Invoke-WorkflowStep '換裝置前統整與同步' (Join-Path $PSScriptRoot 'invoke_knowledge_cycle.ps1') $cycleArgs
        $shutdownArgs = @('-ProjectPath',$root,'-CommitMessage',$CommitMessage)
        if ($Preview) { $shutdownArgs += @('-DryRun','-NoPush','-NoPackage') }
        Invoke-WorkflowStep '正式交接收工' (Join-Path $PSScriptRoot 'shutdown.ps1') $shutdownArgs
    }
}

$failed = @($steps | Where-Object { $_.exitCode -ne 0 }).Count
$status = $(if ($failed) { 'PARTIAL' } elseif ($Preview) { 'PREVIEW' } else { 'PASS' })
$result = [pscustomobject]@{status=$status;command=$Command;projectPath=$root;steps=@($steps);warnings=@($warnings)}
if ($Json) { $result | ConvertTo-Json -Depth 30 }
else {
    if($Command-eq'全整'-and$Preview-and$steps.Count-and$steps[0].result){
        $previewResult=$steps[0].result
        Write-Output "全整內容預覽：$($previewResult.projectName)"
        Write-Output "專案類型：$($previewResult.projectType)"
        Write-Output "正式執行會更新：$($previewResult.targetNote)"
        Write-Output ''
        foreach($section in @($previewResult.sections)){
            Write-Output "【$($section.name)】"
            Write-Output ([string]$section.summary)
            if(@($section.sourceExamples).Count){Write-Output "參考來源：$(@($section.sourceExamples)-join'、')"}
            Write-Output ''
        }
        Write-Output '同步提醒：預覽不寫入 Obsidian、Google Drive、NotebookLM 或網站。'
        Write-Output "注意事項：$(if(@($previewResult.warnings).Count){@($previewResult.warnings)-join'；'}else{'無。'})"
    }else{
        Write-Output "工作流口令「$Command」：$status"
        foreach ($step in $steps) { Write-Output "- $($step.name)：$(if($step.result){$step.result.status}else{'UNKNOWN'})" }
        Write-Output "⚠ 注意事項：$(if($warnings.Count){$warnings -join '；'}else{'無。'})"
    }
}
if ($failed) { exit 1 } else { exit 0 }
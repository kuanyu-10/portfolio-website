[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$Preview,
    [switch]$PublishReviewed,
    [switch]$NoAutoPublish,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')
$steps = New-Object System.Collections.ArrayList
$uncertainties = New-Object System.Collections.ArrayList

function Invoke-CycleStep {
    param([string]$Name,[string]$Script,[string[]]$Arguments)
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments -Json 2>&1|Out-String
    $exitCode=$LASTEXITCODE;$parsed=$null
    try{$parsed=$output|ConvertFrom-Json}catch{[void]$uncertainties.Add("$Name 輸出無法解析：$($output.Trim())")}
    [void]$steps.Add([pscustomobject]@{name=$Name;exitCode=$exitCode;result=$parsed})
    if($exitCode-ne0){[void]$uncertainties.Add("$Name 執行失敗，exit code：$exitCode")}
    if($parsed-and$parsed.PSObject.Properties['uncertainties']){foreach($item in @($parsed.uncertainties)){if($item){[void]$uncertainties.Add("$Name：$item")}}}
    if($parsed-and$parsed.PSObject.Properties['warnings']){foreach($item in @($parsed.warnings)){if($item){[void]$uncertainties.Add("$Name：$item")}}}
    return $parsed
}
function Add-SkippedStep([string]$Name,[string]$Reason){
    [void]$steps.Add([pscustomobject]@{name=$Name;exitCode=0;result=[pscustomobject]@{status='SKIPPED';uncertainties=@($Reason)}})
    [void]$uncertainties.Add("$Name：$Reason")
}

$root=Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
$scriptRoot=$PSScriptRoot
$config=Get-WorkflowConfig -ProjectRoot $root
$profile=Get-WorkflowKnowledgeProfile -ProjectRoot $root -Config $config
if($profile.status-ne'READY'){
    $blocked=[pscustomobject]@{status='BLOCKED';preview=[bool]$Preview;projectType=[string]$profile.projectType;steps=@();uncertainties=@([string]$profile.message)}
    if($Json){$blocked|ConvertTo-Json -Depth 10}else{Write-Host '知識循環：BLOCKED（受阻）';Write-Host "⚠ 目前限制：$($profile.message)"}
    exit 1
}
$commonArgs=@('-ProjectPath',$root);if($Preview){$commonArgs+='-Preview'}

$primaryArchives=Invoke-CycleStep -Name '主要封存知識來源' -Script (Join-Path $scriptRoot 'collect_primary_knowledge_sources.ps1') -Arguments $commonArgs
$collection=Invoke-CycleStep -Name '真實專案來源自動蒐集' -Script (Join-Path $scriptRoot 'collect_project_knowledge.ps1') -Arguments $commonArgs
$health=Invoke-CycleStep -Name '健康檢查' -Script (Join-Path $scriptRoot 'check_knowledge_tools.ps1') -Arguments @('-ProjectPath',$root,'-ActiveHealthCheck')
$digest=Invoke-CycleStep -Name '重點歸納' -Script (Join-Path $scriptRoot 'prepare_knowledge_digest.ps1') -Arguments $commonArgs

$notebookEnabled=$config-and$config.PSObject.Properties['knowledgeIntegration']-and$config.knowledgeIntegration.notebookLM.enabled-eq$true
$automaticNotebookResearch=$notebookEnabled-and$config.knowledgeIntegration.notebookLM.PSObject.Properties['automaticResearch']-and$config.knowledgeIntegration.notebookLM.automaticResearch-eq$true
if($automaticNotebookResearch-and-not$Preview-and$digest-and$digest.status-in@('AUTO_REVIEWED','REVIEW_REQUIRED')){
    $research=Invoke-CycleStep -Name 'NotebookLM 研究' -Script (Join-Path $scriptRoot 'research_with_notebooklm.ps1') -Arguments @('-ProjectPath',$root,'-DraftPath',[string]$digest.draftRelativePath)
}elseif($notebookEnabled-and$Preview){
    $research=Invoke-CycleStep -Name 'NotebookLM 研究預覽' -Script (Join-Path $scriptRoot 'research_with_notebooklm.ps1') -Arguments @('-ProjectPath',$root,'-Preview')
}else{Add-SkippedStep -Name 'NotebookLM 研究' -Reason '未啟用自動研究；安全摘要仍會在 Obsidian 與 Drive 更新。'}

if($PublishReviewed-or-not$NoAutoPublish){
    $publishArgs=@('-ProjectPath',$root);if($Preview){$publishArgs+='-Preview'}
    $publish=Invoke-CycleStep -Name '安全知識自動發布' -Script (Join-Path $scriptRoot 'publish_reviewed_knowledge.ps1') -Arguments $publishArgs
}else{Add-SkippedStep -Name '安全知識自動發布' -Reason '本次已明確停用自動發布；高風險草稿仍維持隔離。'}

$driveSyncEnabled=$config-and$config.PSObject.Properties['knowledgeDriveSync']-and$config.knowledgeDriveSync.enabled-eq$true
if($driveSyncEnabled){
    $driveArgs=@('-ProjectPath',$root);if($Preview){$driveArgs+='-Preview'}
    $driveSync=Invoke-CycleStep -Name 'Google Drive 單向中繼' -Script (Join-Path $scriptRoot 'sync_knowledge_drive.ps1') -Arguments $driveArgs
}else{Add-SkippedStep -Name 'Google Drive 單向中繼' -Reason '尚未設定 Drive 中繼目錄。'}

$notebookSourceSyncEnabled=$notebookEnabled-and$config.knowledgeIntegration.notebookLM.PSObject.Properties['automaticSourceSync']-and$config.knowledgeIntegration.notebookLM.automaticSourceSync-eq$true
if($notebookSourceSyncEnabled){
    $notebookSyncArgs=@('-ProjectPath',$root);if($Preview){$notebookSyncArgs+='-Preview'}
    $notebookSourceSync=Invoke-CycleStep -Name 'NotebookLM 管理來源同步' -Script (Join-Path $scriptRoot 'sync_knowledge_notebooklm.ps1') -Arguments $notebookSyncArgs
}else{Add-SkippedStep -Name 'NotebookLM 管理來源同步' -Reason '尚未啟用 NotebookLM 自動來源同步。'}

$hubSyncEnabled=$config-and$config.PSObject.Properties['knowledgeHubSync']-and$config.knowledgeHubSync.enabled-eq$true
if($hubSyncEnabled-and-not$Preview){
    $hubSync=Invoke-CycleStep -Name '知序網站同步' -Script (Join-Path $scriptRoot 'sync_knowledge_hub.ps1') -Arguments @('-ProjectPath',$root)
}

$hardFailures=@($steps|Where-Object{$_.exitCode-ne0}).Count
$notConfigured=@($steps|Where-Object{$_.result-and$_.result.status-in@('NOT_CONFIGURED','BLOCKED')}).Count
$status=$(if($hardFailures-gt0){'PARTIAL'}elseif($notConfigured-gt0){'PARTIAL'}else{'PASS'})
$result=[pscustomobject]@{status=$status;preview=[bool]$Preview;projectType=[string]$profile.projectType;recommendedSections=@($profile.sections);autoPublish=(-not[bool]$NoAutoPublish);steps=@($steps);uncertainties=@($uncertainties)}
if($Json){$result|ConvertTo-Json -Depth 20}else{
    Write-Host "知識循環：$status（$(ConvertTo-WorkflowStatusZhTw $status)）"
    foreach($step in $steps){Write-Host "- $($step.name)：$(if($step.result){$step.result.status}else{'UNKNOWN'})"}
    Write-Host "⚠ 注意事項：$(if($uncertainties.Count){$uncertainties-join'；'}else{'無。'})"
}
if($hardFailures-gt0){exit 1}else{exit 0}

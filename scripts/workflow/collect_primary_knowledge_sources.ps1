[CmdletBinding()]
param(
    [string]$ProjectPath=(Get-Location).Path,
    [switch]$Preview,
    [switch]$Json
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'knowledge_archive_reader.ps1')
try{
    $root=Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config=Get-WorkflowConfig -ProjectRoot $root
    $profile=Get-WorkflowKnowledgeProfile -ProjectRoot $root -Config $config
    if($profile.status-ne'READY'){throw $profile.message}
    $records=@(Get-PrimaryKnowledgeArchiveRecords -ProjectRoot $root -Config $config)
    if(-not$records.Count){
        $result=[pscustomobject]@{status='NO_SOURCES';projectType=$profile.projectType;recordCount=0;preview=[bool]$Preview}
        if($Json){$result|ConvertTo-Json -Depth 5}else{Write-Output '主要封存來源：NO_SOURCES（沒有設定）'}
        exit 0
    }
    $vault=[string]$config.knowledgeIntegration.obsidian.vaultPath
    $sourceRelative=[string]$config.knowledgeIntegration.digest.sourceDirectoryPath
    if([string]::IsNullOrWhiteSpace($vault)-or[string]::IsNullOrWhiteSpace($sourceRelative)){throw 'Obsidian 來源目錄尚未設定。'}
    $destination=Join-Path (Join-Path $vault $sourceRelative) '主要知識來源.md'
    if(-not$Preview){
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
        $builder=New-Object Text.StringBuilder
        [void]$builder.AppendLine('---')
        [void]$builder.AppendLine('status: source')
        [void]$builder.AppendLine("project: $([string]$config.projectName)")
        [void]$builder.AppendLine("projectType: $([string]$profile.projectType)")
        [void]$builder.AppendLine('internalOnly: true')
        [void]$builder.AppendLine('---')
        [void]$builder.AppendLine('')
        [void]$builder.AppendLine('# 主要知識來源')
        [void]$builder.AppendLine('')
        [void]$builder.AppendLine('此檔只供整理流程使用，不是正式筆記，也不會同步到網站。')
        foreach($record in $records){
            if($builder.Length-ge120000){break}
            [void]$builder.AppendLine('')
            [void]$builder.AppendLine("## $($record.path)")
            if(@($record.topics).Count){[void]$builder.AppendLine("可辨識主題：$(@($record.topics)-join'、')")}
            if($record.excerpt){[void]$builder.AppendLine(([string]$record.excerpt))}
        }
        $body=$builder.ToString()
        if($body.Length-gt120000){$body=$body.Substring(0,120000)+[Environment]::NewLine+'內容已達安全上限。'}
        [IO.File]::WriteAllText($destination,$body,[Text.UTF8Encoding]::new($false))
    }
    $result=[pscustomobject]@{status=$(if($Preview){'PREVIEW'}else{'SOURCE_UPDATED'});projectType=$profile.projectType;recordCount=$records.Count;destination=$destination;preview=[bool]$Preview}
    if($Json){$result|ConvertTo-Json -Depth 6}else{Write-Output "主要封存來源：$($result.status)";Write-Output "辨識資料區段：$($records.Count)"}
    exit 0
}catch{
    $result=[pscustomobject]@{status='BLOCKED';error=$_.Exception.Message;preview=[bool]$Preview}
    if($Json){$result|ConvertTo-Json -Depth 5}else{Write-Output '主要封存來源：BLOCKED（受阻）';Write-Output "目前限制：$($_.Exception.Message)"}
    exit 1
}

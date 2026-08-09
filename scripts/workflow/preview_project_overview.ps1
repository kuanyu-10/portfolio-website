[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [int]$MaximumFilesToInspect = 800,
    [int]$MaximumCharactersPerFile = 12000,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'knowledge_archive_reader.ps1')

function Get-SectionPattern([string]$Section) {
    $patterns=@{
        '專案介紹'='readme|about|overview|intro|description|首頁|介紹|目標'
        '故事與世界觀'='story|lore|world|narrative|plot|scenario|quest|dialogue|劇情|世界觀|故事|任務|對話'
        '角色與 NPC'='character|characters|npc|actor|avatar|角色|人物|夥伴'
        '魔物'='monster|enemy|enemies|mob|creature|boss|魔物|敵人|首領'
        '招式與戰鬥'='combat|battle|skill|ability|attack|damage|weapon|招式|技能|戰鬥|傷害'
        '城鎮與場景'='town|city|village|map|scene|level|location|城鎮|城市|村莊|地圖|場景|地點'
        '系統與玩法'='system|gameplay|mechanic|state|manager|save|inventory|玩法|系統|存檔|背包'
        '物品裝備'='item|equipment|inventory|armor|weapon|loot|物品|裝備|武器|防具'
        '網站目標'='readme|about|home|landing|hero|purpose|goal|首頁|介紹|目標'
        '頁面與內容'='page|pages|route|content|article|post|html|tsx|jsx|頁面|內容|文章'
        '使用流程'='flow|journey|login|auth|form|submit|search|booking|checkout|登入|表單|搜尋|流程'
        '介面與導覽'='component|layout|navigation|navbar|sidebar|menu|css|style|responsive|介面|導覽|選單'
        '部署與維護'='deploy|deployment|cloudflare|vercel|wrangler|build|release|migration|部署|維護|建置'
        '產品功能'='feature|function|api|dashboard|note|portfolio|knowledge|功能|產品|筆記|投資'
        '帳號與權限'='auth|login|user|account|role|permission|rbac|session|登入|帳號|權限'
        '資料流程'='database|schema|migration|sync|import|export|api|data|資料|同步|匯入|匯出'
        '外部整合'='google|obsidian|notebooklm|yahoo|github|cloudflare|integration|整合|串接'
        '操作方式'='usage|guide|操作|使用|按鈕|流程'
        '工具用途'='readme|overview|purpose|workflow|工具|用途|目標'
        '安裝與設定'='install|setup|configure|config|onboard|安裝|設定|導入'
        '指令與流程'='command|workflow|startup|shutdown|script|指令|流程|開工|收工'
        '安全界線'='security|safe|secret|credential|git|安全|權限|憑證'
        '維護與疑難排解'='troubleshoot|debug|diagnos|maintain|error|failure|疑難|錯誤|維護'
        '主要內容'='readme|docs|src|app|content|主要|功能|內容'
        '目前進度'='handoff|changelog|project_state|roadmap|milestone|status|progress|todo|進度|完成|待辦'
        '優化與建議'='todo|fixme|issue|roadmap|improve|optimization|refactor|known.?issue|建議|改善|優化|問題'
        '待處理事項'='todo|fixme|issue|roadmap|next|pending|待辦|下一步|未完成'
    }
    if($patterns.ContainsKey($Section)){return $patterns[$Section]}
    return [regex]::Escape($Section)
}

function Get-ReadableTopics([string]$Text,[string]$RelativePath) {
    $topics=New-Object System.Collections.ArrayList
    foreach($match in [regex]::Matches($Text,'(?m)^#{1,4}\s+(.+?)\s*$')){
        $value=($match.Groups[1].Value-replace'[*_#]','').Trim()
        if($value.Length-ge2-and$value.Length-le80-and-not$topics.Contains($value)){[void]$topics.Add($value)}
        if($topics.Count-ge6){break}
    }
    if($topics.Count-lt6){
        foreach($match in [regex]::Matches($Text,'(?is)<(?:title|h1|h2|h3)[^>]*>(.*?)</(?:title|h1|h2|h3)>')){
            $value=([regex]::Replace($match.Groups[1].Value,'<[^>]+>','')-replace'\s+',' ').Trim()
            if($value.Length-ge2-and$value.Length-le80-and-not$topics.Contains($value)){[void]$topics.Add($value)}
            if($topics.Count-ge6){break}
        }
    }
    if($topics.Count-eq0){
        $name=[IO.Path]::GetFileNameWithoutExtension($RelativePath)-replace'[-_]',' '
        if($name){[void]$topics.Add($name)}
    }
    return @($topics)
}

function Get-ArchiveSectionHints([string]$Path) {
    if($Path-match'Combat_Techniques'){return @('招式與戰鬥')}
    if($Path-match'NPC_Runtime'){return @('角色與 NPC')}
    if($Path-match'Avatar'){return @('角色與 NPC','系統與玩法')}
    if($Path-match'Items_Rewards'){return @('物品裝備')}
    if($Path-match'World_Source'){return @('故事與世界觀','城鎮與場景')}
    if($Path-match'Settings?_Core|設定_Core'){return @('系統與玩法')}
    if($Path-match'Settings?_Tests|設定_Tests'){return @('目前進度','優化與建議')}
    if($Path-match'v53A_audit_core'){return @('系統與玩法','目前進度','優化與建議')}
    return @()
}

try {
    $root=Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config=Get-WorkflowConfig -ProjectRoot $root
    $profile=Get-WorkflowKnowledgeProfile -ProjectRoot $root -Config $config
    if($profile.status-ne'READY'){throw $profile.message}

    $git=Invoke-WorkflowGit -ProjectRoot $root -Arguments @('-c','core.quotePath=false','ls-files') -AllowFailure
    if($git.ExitCode-ne0){throw '無法取得 Git 已追蹤來源。'}
    $allowed=@('.md','.txt','.html','.htm','.json','.jsonc','.yml','.yaml','.toml','.tsx','.jsx','.ts','.js','.css','.scss','.py','.cs','.gd')
    $excluded='(^|/)(AGENTS\.md|VALIDATION_REPORT\.md)$|(^|/)(node_modules|dist|build|bin|obj|coverage|\.git|\.next|\.workflow|\.workflow-update|scripts/workflow|docs/workflow)(/|$)|(^|/)(workflow\.config\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$|\.env|secret|credential|private.?key|token'
    $relativePaths=@($git.Output-split'\r?\n'|Where-Object{$_-and$allowed-contains[IO.Path]::GetExtension($_).ToLowerInvariant()-and($_-replace'\\','/')-notmatch$excluded})
    $warnings=New-Object System.Collections.ArrayList
    if($relativePaths.Count-gt$MaximumFilesToInspect){[void]$warnings.Add("共有 $($relativePaths.Count) 個一般安全來源；預覽最多分析前 $MaximumFilesToInspect 個。")}

    $records=New-Object System.Collections.ArrayList
    $archiveRaw=@(Get-PrimaryKnowledgeArchiveRecords -ProjectRoot $root -Config $config -MaximumCharactersPerTextEntry $MaximumCharactersPerFile)
    foreach($group in @($archiveRaw|Group-Object{($_.path-split'#')[0]})){
        $items=@($group.Group)
        $path=[string]$group.Name
        $topics=@($items|ForEach-Object{$_.topics}|Select-Object -Unique -First 12)
        $search=($items|ForEach-Object{$_.search})-join' '
        $excerpt=($items|ForEach-Object{$_.excerpt}|Where-Object{$_}|Select-Object -First 5)-join[Environment]::NewLine
        [void]$records.Add([pscustomobject]@{
            path=$path
            search=$search
            topics=@($topics)
            truncated=(@($items|Where-Object{$_.truncated}).Count-gt0)
            operational=$false
            primary=$true
            sectionHints=@(Get-ArchiveSectionHints $path)
            excerpt=$excerpt
        })
    }

    foreach($relative in @($relativePaths|Select-Object -First $MaximumFilesToInspect)){
        $full=Join-Path $root $relative
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){continue}
        try{
            $raw=[IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)
            $truncated=$raw.Length-gt$MaximumCharactersPerFile
            $sourceText=$(if($truncated){$raw.Substring(0,$MaximumCharactersPerFile)}else{$raw})
            [void]$records.Add([pscustomobject]@{
                path=($relative-replace'\\','/')
                search=(($relative+' '+$sourceText).ToLowerInvariant())
                topics=@(Get-ReadableTopics $sourceText $relative)
                truncated=$truncated
                operational=($relative-match'^(HANDOFF\.md|CHANGELOG_AGENT\.md|PROJECT_STATE\.json)$')
                primary=$false
                sectionHints=@()
                excerpt=''
            })
        }catch{}
    }

    $gameContentSections=@('故事與世界觀','角色與 NPC','魔物','招式與戰鬥','城鎮與場景','系統與玩法','物品裝備')
    $hasGameArchives=@($records|Where-Object{$_.primary-and$_.sectionHints.Count}).Count-gt0
    $sections=New-Object System.Collections.ArrayList
    foreach($sectionName in @($profile.sections)){
        $pattern=Get-SectionPattern $sectionName
        if($profile.projectType-eq'game'-and$hasGameArchives-and$gameContentSections-contains$sectionName){
            $matched=@($records|Where-Object{$_.primary-and$_.sectionHints-contains$sectionName})
        }else{
            $eligible=$(if($sectionName-in@('目前進度','優化與建議','待處理事項')){@($records)}else{@($records|Where-Object{-not$_.operational})})
            $matched=@($eligible|Where-Object{
                ($_.primary-and$_.sectionHints-contains$sectionName)-or
                (-not$_.primary-and$_.search-match$pattern)
            })
        }
        $topics=@($matched|ForEach-Object{$_.topics}|Select-Object -Unique -First 6)
        $sources=@($matched|Select-Object -ExpandProperty path -Unique -First 5)
        $summary=$(if($matched.Count){
            $topicText=$(if($topics.Count){$topics-join'、'}else{'已找到相關來源'})
            "預計根據 $($matched.Count) 份相關來源整理：$topicText。"
        }else{'目前沒有找到明確來源；正式整理時會標示待補充，不會自行猜測內容。'})
        [void]$sections.Add([pscustomobject]@{name=$sectionName;summary=$summary;matchedSourceCount=$matched.Count;topics=@($topics);sourceExamples=@($sources)})
    }

    $truncatedCount=@($records|Where-Object{$_.truncated}).Count
    if($truncatedCount){[void]$warnings.Add("$truncatedCount 份來源達到預覽上限；正式總覽必須標示資料限制。")}
    if($archiveRaw.Count){[void]$warnings.Add("已將 $($archiveRaw.Count) 個封存內部區段彙整為 $(@($records|Where-Object{$_.primary}).Count) 份封存來源，避免重複計算工作表。")}
    if($profile.forbiddenSections.Count){[void]$warnings.Add("已依 $($profile.projectType) 類型排除：$($profile.forbiddenSections-join'、')。")}

    $published=''
    if($config-and$config.PSObject.Properties['knowledgeIntegration']-and$config.knowledgeIntegration.PSObject.Properties['digest']){$published=[string]$config.knowledgeIntegration.digest.publishedDirectoryPath}
    $target=$(if($published){$published.TrimEnd('\','/')+'\專案總覽.md'}else{'專案總覽.md'})
    $result=[pscustomobject]@{
        status='PREVIEW'
        projectName=$(if($config.projectName){[string]$config.projectName}else{Split-Path $root -Leaf})
        projectType=[string]$profile.projectType
        targetNote=$target
        inspectedSourceCount=$records.Count
        totalSafeSourceCount=$relativePaths.Count
        archiveInternalRecordCount=$archiveRaw.Count
        archiveSourceCount=@($records|Where-Object{$_.primary}).Count
        sections=@($sections)
        warnings=@($warnings)
        writesPerformed=$false
        externalSyncPerformed=$false
    }
    if($Json){$result|ConvertTo-Json -Depth 15}
    else{
        Write-Output "全整內容預覽：$($result.projectName)"
        Write-Output "專案類型：$($result.projectType)"
        Write-Output "正式執行會更新：$($result.targetNote)"
        Write-Output ''
        foreach($section in $sections){
            Write-Output "【$($section.name)】"
            Write-Output $section.summary
            if($section.sourceExamples.Count){Write-Output "參考來源：$($section.sourceExamples-join'、')"}
            Write-Output ''
        }
        Write-Output '同步提醒：預覽未寫入 Obsidian、Google Drive、NotebookLM 或網站。'
        Write-Output "注意事項：$(if($warnings.Count){$warnings-join'；'}else{'無。'})"
    }
    exit 0
}catch{
    $result=[pscustomobject]@{status='BLOCKED';error=$_.Exception.Message;writesPerformed=$false;externalSyncPerformed=$false}
    if($Json){$result|ConvertTo-Json -Depth 5}else{Write-Output '全整內容預覽：BLOCKED（受阻）';Write-Output "目前限制：$($_.Exception.Message)"}
    exit 1
}

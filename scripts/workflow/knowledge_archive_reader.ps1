Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ArchiveEntryText {
    param($Entry,[int]$MaximumCharacters=12000)
    $stream=$Entry.Open()
    try{
        $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
        try{
            $buffer=New-Object char[] $MaximumCharacters
            $count=$reader.ReadBlock($buffer,0,$MaximumCharacters)
            if($count-le0){return ''}
            return (-join $buffer[0..($count-1)])
        }finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}

function Get-XlsxArchiveRecords {
    param($Entry,[string]$DisplayPath,[int]$MaximumCellsPerSheet=3000)
    $memory=New-Object IO.MemoryStream
    $source=$Entry.Open()
    try{$source.CopyTo($memory)}finally{$source.Dispose()}
    $memory.Position=0
    $xlsx=New-Object IO.Compression.ZipArchive($memory,[IO.Compression.ZipArchiveMode]::Read,$false)
    try{
        $shared=New-Object System.Collections.ArrayList
        $sharedEntry=$xlsx.GetEntry('xl/sharedStrings.xml')
        if($sharedEntry){
            $stream=$sharedEntry.Open()
            try{
                $reader=[Xml.XmlReader]::Create($stream)
                try{
                    while($reader.Read()-and$shared.Count-lt50000){
                        if($reader.NodeType-eq[Xml.XmlNodeType]::Element-and$reader.LocalName-eq'si'){
                            $sub=$reader.ReadSubtree()
                            $parts=New-Object System.Collections.ArrayList
                            try{
                                while($sub.Read()){
                                    if($sub.NodeType-eq[Xml.XmlNodeType]::Element-and$sub.LocalName-eq't'){
                                        [void]$parts.Add($sub.ReadElementContentAsString())
                                    }
                                }
                            }finally{$sub.Dispose()}
                            [void]$shared.Add(($parts-join''))
                        }
                    }
                }finally{$reader.Dispose()}
            }finally{$stream.Dispose()}
        }
        $results=New-Object System.Collections.ArrayList
        foreach($sheet in @($xlsx.Entries|Where-Object{$_.FullName-match'^xl/worksheets/[^/]+\.xml$'})){
            $values=New-Object System.Collections.ArrayList
            $stream=$sheet.Open()
            try{
                $reader=[Xml.XmlReader]::Create($stream)
                try{
                    while($reader.Read()-and$values.Count-lt$MaximumCellsPerSheet){
                        if($reader.NodeType-ne[Xml.XmlNodeType]::Element-or$reader.LocalName-ne'c'){continue}
                        $type=$reader.GetAttribute('t')
                        $sub=$reader.ReadSubtree()
                        $raw=''
                        try{
                            while($sub.Read()){
                                if($sub.NodeType-eq[Xml.XmlNodeType]::Element-and$sub.LocalName-in@('v','t')){
                                    $raw=$sub.ReadElementContentAsString()
                                    if($raw){break}
                                }
                            }
                        }finally{$sub.Dispose()}
                        if($type-eq's'-and$raw-match'^\d+$'){
                            $index=[int]$raw
                            if($index-ge0-and$index-lt$shared.Count){$raw=[string]$shared[$index]}
                        }
                        $raw=($raw-replace'\s+',' ').Trim()
                        if($raw.Length-ge2-and$raw.Length-le500){[void]$values.Add($raw)}
                    }
                }finally{$reader.Dispose()}
            }finally{$stream.Dispose()}
            $topics=@($values|Where-Object{$_.Length-le80}|Select-Object -Unique -First 12)
            [void]$results.Add([pscustomobject]@{
                path="$DisplayPath#$([IO.Path]::GetFileNameWithoutExtension($sheet.Name))"
                search=(("$DisplayPath "+($values-join' ')).ToLowerInvariant())
                topics=@($topics)
                truncated=$values.Count-ge$MaximumCellsPerSheet
                operational=$false
                primary=$true
                excerpt=(@($values|Select-Object -First 200)-join' | ')
            })
        }
        return @($results)
    }finally{$xlsx.Dispose();$memory.Dispose()}
}

function Get-PrimaryKnowledgeArchiveRecords {
    param([string]$ProjectRoot,$Config,[int]$MaximumCharactersPerTextEntry=12000)
    $records=New-Object System.Collections.ArrayList
    if(-not$Config-or-not$Config.PSObject.Properties['knowledgeProfile']-or-not$Config.knowledgeProfile.PSObject.Properties['primaryArchives']){return @()}
    foreach($source in @($Config.knowledgeProfile.primaryArchives)){
        $relative=[string]$source.path
        if([string]::IsNullOrWhiteSpace($relative)){continue}
        $full=[IO.Path]::GetFullPath((Join-Path $ProjectRoot $relative))
        if(-not$full.StartsWith(($ProjectRoot.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){continue}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){continue}
        if([IO.Path]::GetExtension($full).ToLowerInvariant()-ne'.zip'){continue}
        $zip=[IO.Compression.ZipFile]::OpenRead($full)
        try{
            foreach($entry in @($zip.Entries|Where-Object{-not[string]::IsNullOrWhiteSpace($_.Name)}|Select-Object -First 1000)){
                $extension=[IO.Path]::GetExtension($entry.Name).ToLowerInvariant()
                $display=($relative-replace'\\','/')+'!/'+$entry.FullName
                if($extension-eq'.xlsx'-and$entry.Length-le50MB){
                    foreach($record in @(Get-XlsxArchiveRecords -Entry $entry -DisplayPath $display)){[void]$records.Add($record)}
                }
                elseif($extension-in@('.md','.txt','.json','.jsonc','.yml','.yaml','.toml','.gd','.py','.cfg')-and$entry.Length-le10MB){
                    $text=Read-ArchiveEntryText -Entry $entry -MaximumCharacters $MaximumCharactersPerTextEntry
                    $topics=@()
                    if(Get-Command Get-ReadableTopics -ErrorAction SilentlyContinue){$topics=@(Get-ReadableTopics $text $display)}
                    if(-not$topics.Count){$topics=@([IO.Path]::GetFileNameWithoutExtension($entry.Name))}
                    [void]$records.Add([pscustomobject]@{
                        path=$display
                        search=(("$display "+$text).ToLowerInvariant())
                        topics=@($topics)
                        truncated=$entry.Length-gt$MaximumCharactersPerTextEntry
                        operational=$false
                        primary=$true
                        excerpt=$(if($text.Length-gt4000){$text.Substring(0,4000)}else{$text})
                    })
                }
            }
        }finally{$zip.Dispose()}
    }
    return @($records)
}

[CmdletBinding()]
param(
    [ValidateSet('整','全整','全部同步')]
    [string]$Command = '整',
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$Preview,
    [switch]$SyncAfterPublish,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($ProjectPath)
$candidates = New-Object System.Collections.ArrayList
if (-not [string]::IsNullOrWhiteSpace($env:CODEX_KNOWLEDGE_PUBLISHER_HOME)) {
    [void]$candidates.Add([string]$env:CODEX_KNOWLEDGE_PUBLISHER_HOME)
}
[void]$candidates.Add((Join-Path (Split-Path $projectRoot -Parent) 'codex-knowledge-publisher'))
[void]$candidates.Add((Join-Path $env:USERPROFILE 'Desktop\work\工具\codex-knowledge-publisher'))
[void]$candidates.Add((Join-Path $env:USERPROFILE 'OneDrive\Desktop\work\工具\codex-knowledge-publisher'))
$publisherRoot = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'bin\knowledge-publisher.mjs') -PathType Leaf) } | Select-Object -First 1)
if (-not $publisherRoot.Count) { throw '找不到 codex-knowledge-publisher；舊知識流程仍可作為回退。' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw '找不到 Node.js，無法啟動知識發布器。' }

$mapped = switch ($Command) {
    '整' { if ($Preview) { 'preview' } else { 'daily' } }
    '全整' { if ($Preview) { 'preview' } else { 'full' } }
    '全部同步' { 'sync' }
}
$entry = Join-Path $publisherRoot[0] 'bin\knowledge-publisher.mjs'
$steps = New-Object System.Collections.ArrayList
function Invoke-PublisherStep([string]$Name, [string]$PublisherCommand) {
    $raw = @(& node $entry $PublisherCommand --json 2>&1 | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $exitCode = $LASTEXITCODE
    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json } catch { $parsed = [pscustomobject]@{ status='FAILED'; error='知識發布器輸出無法解析。' } }
    [void]$steps.Add([pscustomobject]@{ name=$Name; exitCode=$exitCode; result=$parsed })
}
Push-Location $projectRoot
try {
    Invoke-PublisherStep -Name $Command -PublisherCommand $mapped
    if ($SyncAfterPublish -and -not $Preview -and @($steps | Where-Object { $_.exitCode -ne 0 }).Count -eq 0) {
        Invoke-PublisherStep -Name '全部同步' -PublisherCommand 'sync'
    }
}
finally { Pop-Location }
$failed = @($steps | Where-Object { $_.exitCode -ne 0 }).Count
$result = [pscustomobject]@{ status=$(if($failed){'PARTIAL'}else{'PASS'}); command=$Command; projectPath=$projectRoot; steps=@($steps); publisher='codex-knowledge-publisher' }
if ($Json) { $result | ConvertTo-Json -Depth 30 }
else {
    Write-Output "知識發布器「$Command」：$($result.status)"
    foreach ($step in $steps) { Write-Output "- $($step.name)：$(if($step.result.status){$step.result.status}else{'UNKNOWN'})" }
}
if ($failed) { exit 1 } else { exit 0 }

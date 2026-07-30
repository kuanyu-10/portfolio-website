. .\scripts\workflow\common.ps1
$git = Invoke-WorkflowGit -ProjectRoot 'c:\Users\andre\Desktop\work\個人網頁\portfolio-website' -Arguments @('status', '--porcelain')
$git.Output > dump.txt
foreach ($line in ($git.Output -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $relative = $line.Substring(3).Trim()
    if ($relative.Contains(' -> ')) { $relative = $relative.Split(@(' -> '), [StringSplitOptions]::None)[-1] }
    $relative = $relative.Trim('"').Replace('\', '/')
    Write-Host "Relative: $relative"
    try {
        $fullPath = Join-Path 'c:\Users\andre\Desktop\work\個人網頁\portfolio-website' ($relative.Replace('/', '\'))
        Write-Host "FullPath: $fullPath"
        $pathFull = [IO.Path]::GetFullPath($fullPath)
    } catch {
        Write-Host "ERROR on line: $line"
        Write-Host $_.Exception.Message
    }
}

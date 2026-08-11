[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$OutputDirectory,
    [string]$BackupDirectory,
    [switch]$NoZip,
    [switch]$NoBackupCopy,
    [switch]$IncludeIgnored,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $root = Resolve-WorkflowProjectRoot -ProjectPath $ProjectPath
    $config = Get-WorkflowConfig -ProjectRoot $root
    $state = Read-WorkflowJson -Path (Join-Path $root 'PROJECT_STATE.json')
    $workflowVersion = Get-WorkflowVersion -ProjectRoot $root

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        if ($config -and -not [string]::IsNullOrWhiteSpace([string]$config.handoffOutputDirectory)) {
            $OutputDirectory = [string]$config.handoffOutputDirectory
        }
        else {
            $OutputDirectory = Join-Path $root 'handoff_packages'
        }
    }
    if (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory = Join-Path $root $OutputDirectory
    }
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)

    if ([string]::IsNullOrWhiteSpace($BackupDirectory) -and $config -and
        $config.copyPackageToGoogleDrive -eq $true -and
        -not [string]::IsNullOrWhiteSpace([string]$config.googleDriveBackupDirectory)) {
        $BackupDirectory = [string]$config.googleDriveBackupDirectory
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupDirectory) -and -not [IO.Path]::IsPathRooted($BackupDirectory)) {
        $BackupDirectory = Join-Path $root $BackupDirectory
    }

    $useIgnoredFiles = [bool]$IncludeIgnored
    if (-not $IncludeIgnored -and $config -and $config.includeGitIgnoredFilesInPackage -eq $true) {
        $useIgnoredFiles = $true
    }

    $candidateRelativePaths = New-Object System.Collections.ArrayList
    if ((Test-WorkflowGitRepository -ProjectRoot $root) -and -not $useIgnoredFiles) {
        $trackedResult = Invoke-WorkflowGit -ProjectRoot $root -Arguments @('ls-files', '-co', '--exclude-standard')
        foreach ($line in ($trackedResult.Output -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$candidateRelativePaths.Add($line.Replace('\', '/')) }
        }
    }
    else {
        Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
            [void]$candidateRelativePaths.Add((ConvertTo-WorkflowRelativePath -Root $root -Path $_.FullName))
        }
    }

    $defaultExcludedSegments = @(
        '.git', '.godot', 'cache', 'caches', 'temp', 'tmp', 'logs', 'build',
        'dist', 'export', 'exports', 'node_modules', '.venv', 'venv',
        'handoff_packages', '.workflow/runtime'
    )
    $customExclusions = @()
    if ($config -and $config.packageExclusions) { $customExclusions = @($config.packageExclusions) }
    $portableToolsAllowed = ($config -and $config.includePortableTools -eq $true)
    $included = New-Object System.Collections.ArrayList
    $excluded = New-Object System.Collections.ArrayList
    $outputPrefix = ''
    $rootPrefix = $root.TrimEnd('\') + '\'
    if ($outputRoot.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $outputPrefix = (ConvertTo-WorkflowRelativePath -Root $root -Path $outputRoot).TrimEnd('/') + '/'
    }

    foreach ($relativePath in @($candidateRelativePaths | Sort-Object -Unique)) {
        $normalized = $relativePath.Replace('\', '/').TrimStart('/')
        $segments = @($normalized.Split('/'))
        $reason = ''
        if ($outputPrefix -and ($normalized + '/').StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $reason = 'package output recursion'
        }
        elseif (Test-WorkflowSensitivePath -RelativePath $normalized) {
            $reason = 'sensitive or conflict file'
        }
        elseif ($normalized -ieq 'workflow.config.json') {
            $reason = 'local workflow configuration'
        }
        elseif ([IO.Path]::GetExtension($normalized) -ieq '.zip') {
            $reason = 'existing ZIP'
        }
        elseif (-not $portableToolsAllowed -and ($segments -contains '_portable_tools')) {
            $reason = 'portable tools disabled'
        }
        else {
            foreach ($segment in $segments) {
                if ($defaultExcludedSegments -contains $segment.ToLowerInvariant()) {
                    $reason = "excluded directory: $segment"
                    break
                }
            }
        }
        if (-not $reason) {
            foreach ($pattern in $customExclusions) {
                if ($normalized -like [string]$pattern) {
                    $reason = "configured exclusion: $pattern"
                    break
                }
            }
        }
        $fullSource = Join-Path $root ($normalized.Replace('/', '\'))
        if (-not $reason -and -not (Test-Path -LiteralPath $fullSource -PathType Leaf)) {
            $reason = 'missing at packaging time'
        }
        if ($reason) {
            [void]$excluded.Add([pscustomobject]@{ path = $normalized; reason = $reason })
        }
        else {
            [void]$included.Add($normalized)
        }
    }

    Ensure-WorkflowDirectory -Path $outputRoot | Out-Null
    $safeProjectName = [regex]::Replace($(if ($state.project) { [string]$state.project } else { Split-Path $root -Leaf }), '[^\p{L}\p{Nd}._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeProjectName)) { $safeProjectName = 'project' }
    $packageBaseName = "${safeProjectName}_handoff_$(Get-WorkflowFileTimestamp)"
    $stagingPath = Join-Path $outputRoot $packageBaseName
    $suffix = 0
    while (Test-Path -LiteralPath $stagingPath) {
        $suffix++
        $stagingPath = Join-Path $outputRoot ("{0}_{1}" -f $packageBaseName, $suffix)
    }
    Ensure-WorkflowDirectory -Path $stagingPath | Out-Null

    [long]$totalSize = 0
    foreach ($relative in $included) {
        $source = Join-Path $root ($relative.Replace('/', '\'))
        $destination = Join-Path $stagingPath ($relative.Replace('/', '\'))
        Ensure-WorkflowDirectory -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        $totalSize += (Get-Item -LiteralPath $source).Length
    }

    $git = Get-WorkflowGitStatus -ProjectRoot $root
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAt = Get-WorkflowUtcTimestamp
        project = $(if ($state.project) { [string]$state.project } else { Split-Path $root -Leaf })
        branch = $git.Branch
        commit = $git.Commit
        computer = Get-WorkflowComputerName
        agent = 'Codex'
        workflowVersion = $workflowVersion
        fileCount = $included.Count
        totalSizeBytes = $totalSize
        excludedCount = $excluded.Count
        validationStatus = [string]$state.validationStatus
        files = @($included)
        exclusions = @($excluded)
    }
    $manifestPath = Join-Path $stagingPath 'manifest.json'
    Write-WorkflowJson -Path $manifestPath -Value $manifest

    $sumLines = New-Object System.Collections.ArrayList
    Get-ChildItem -LiteralPath $stagingPath -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS' } | Sort-Object FullName | ForEach-Object {
        $relative = ConvertTo-WorkflowRelativePath -Root $stagingPath -Path $_.FullName
        [void]$sumLines.Add(("{0}  {1}" -f (Get-WorkflowSha256 -Path $_.FullName), $relative))
    }
    Write-WorkflowAtomicText -Path (Join-Path $stagingPath 'SHA256SUMS') -Content (($sumLines -join [Environment]::NewLine) + [Environment]::NewLine)

    $zipPath = ''
    $zipSha256 = ''
    if (-not $NoZip) {
        $zipPath = $stagingPath + '.zip'
        Compress-Archive -LiteralPath $stagingPath -DestinationPath $zipPath -CompressionLevel Optimal
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            if ($archive.Entries.Count -lt 2) { throw 'ZIP verification failed: archive has too few entries.' }
        }
        finally {
            $archive.Dispose()
        }
        $zipSha256 = Get-WorkflowSha256 -Path $zipPath
    }

    $backupStatus = 'NOT_REQUIRED'
    $backupPath = ''
    $backupError = ''
    if (-not $NoBackupCopy -and -not [string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $backupRoot = [IO.Path]::GetFullPath($BackupDirectory)
        if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
            $backupStatus = 'FAILED'
            $backupError = "Backup directory does not exist: $backupRoot"
        }
        elseif ($NoZip) {
            $backupStatus = 'FAILED'
            $backupError = 'Backup copy requires a completed ZIP; -NoZip was specified.'
        }
        else {
            try {
                $backupPath = Join-Path $backupRoot ([IO.Path]::GetFileName($zipPath))
                Copy-Item -LiteralPath $zipPath -Destination $backupPath
                $sourceItem = Get-Item -LiteralPath $zipPath
                $backupItem = Get-Item -LiteralPath $backupPath
                if ($sourceItem.Length -ne $backupItem.Length) { throw 'Backup size differs from local ZIP.' }
                if ((Get-WorkflowSha256 -Path $backupPath) -ne $zipSha256) { throw 'Backup SHA256 differs from local ZIP.' }
                $backupStatus = 'COPIED_TO_BACKUP'
            }
            catch {
                $backupStatus = 'FAILED'
                $backupError = $_.Exception.Message
            }
        }
    }

    $packageStatus = $(if ($NoZip) { 'CREATED' } else { 'CREATED' })
    $result = [pscustomobject]@{
        status = $packageStatus
        packageDirectory = $stagingPath
        zipPath = $zipPath
        zipSha256 = $zipSha256
        fileCount = $included.Count
        totalSizeBytes = $totalSize
        excludedCount = $excluded.Count
        manifestPath = $manifestPath
        backupStatus = $backupStatus
        backupPath = $backupPath
        backupError = $backupError
    }
    Write-WorkflowOutput -Value $result -Json:$Json -TextLines @(
        "交接包狀態：$packageStatus（$(ConvertTo-WorkflowStatusZhTw $packageStatus)）",
        "暫存目錄：$stagingPath",
        "ZIP: $zipPath",
        "ZIP SHA256: $zipSha256",
        "包含檔案：$($included.Count)",
        "排除檔案：$($excluded.Count)",
        "備份狀態：$backupStatus（$(ConvertTo-WorkflowStatusZhTw $backupStatus)）",
        $(if ($backupError) { "⚠ 注意事項：備份錯誤：$backupError" } else { '⚠ 注意事項：無。' })
    )
    if ($backupStatus -eq 'FAILED') { exit 4 }
    exit 0
}
catch {
    $failure = [pscustomobject]@{
        status = 'FAILED'
        error = $_.Exception.Message
        zipPath = ''
        backupStatus = 'NOT_REQUIRED'
    }
    Write-WorkflowOutput -Value $failure -Json:$Json -TextLines @('交接包狀態：FAILED（失敗）', "⚠ 目前限制：$($_.Exception.Message)")
    exit 1
}

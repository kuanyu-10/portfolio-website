[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$testsRoot = Join-Path $repositoryRoot 'tests'
if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
    $result = [pscustomobject]@{
        status = 'NOT_AVAILABLE'
        summary = '完整測試套件只存在於工作流來源 repository。'
        passed = 0
        failed = 0
    }
    if ($Json) { $result | ConvertTo-Json -Compress } else { $result | Format-List }
    exit 3
}

$testScripts = @(
    'test-clean-project.ps1',
    'test-dirty-working-tree.ps1',
    'test-behind-remote.ps1',
    'test-diverged-branch.ps1',
    'test-package-recursion.ps1',
    'test-knowledge-integration.ps1',
    'test-knowledge-collection.ps1',
    'test-knowledge-digest.ps1',
    'test-knowledge-automation.ps1',
    'test-knowledge-drive-sync.ps1',
    'test-vault-git-sync.ps1',
    'test-one-click-setup.ps1',
    'test-json-validation.ps1'
)
$suiteResults = New-Object System.Collections.ArrayList
$failedSuites = 0
foreach ($testName in $testScripts) {
    $path = Join-Path $testsRoot $testName
    $raw = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $text = $raw -join [Environment]::NewLine
    try { $suite = $text | ConvertFrom-Json }
    catch {
        $suite = [pscustomobject]@{ suite = $testName; passed = 0; failed = 1; error = "Invalid test output: $text"; cases = @() }
        $exitCode = 1
    }
    if ($exitCode -ne 0 -or $suite.failed -gt 0) { $failedSuites++ }
    [void]$suiteResults.Add($suite)
    if (-not $Json) {
        $mark = $(if ($exitCode -eq 0 -and $suite.failed -eq 0) { 'PASS' } else { 'FAIL' })
        Write-Output "[$mark] $($suite.suite)：$($suite.passed) 通過，$($suite.failed) 失敗"
        if ($suite.PSObject.Properties['error'] -and $suite.error) { Write-Output "  $($suite.error)" }
    }
}
$passedCases = 0
$failedCases = 0
foreach ($suite in $suiteResults) {
    $passedCases += [int]$suite.passed
    $failedCases += [int]$suite.failed
}
$result = [pscustomobject]@{
    status = $(if ($failedSuites -eq 0) { 'PASS' } else { 'FAIL' })
    passed = $passedCases
    failed = $failedCases
    failedSuites = $failedSuites
    suites = @($suiteResults)
}
if ($Json) {
    $result | ConvertTo-Json -Depth 20 -Compress
}
else {
    Write-Output "總結：$($result.status)（$(ConvertTo-WorkflowStatusZhTw $result.status)）— $passedCases 通過，$failedCases 失敗"
}
if ($failedSuites -gt 0) { exit 1 }
exit 0

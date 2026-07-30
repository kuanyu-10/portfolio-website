[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$testsRoot = Join-Path $repositoryRoot 'tests'
if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
    $result = [pscustomobject]@{
        status = 'NOT_AVAILABLE'
        summary = 'The full test suite is available only in the workflow source repository.'
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
        Write-Output "[$mark] $($suite.suite): $($suite.passed) passed, $($suite.failed) failed"
        if ($suite.error) { Write-Output "  $($suite.error)" }
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
    Write-Output "Summary: $($result.status) — $passedCases passed, $failedCases failed"
}
if ($failedSuites -gt 0) { exit 1 }
exit 0

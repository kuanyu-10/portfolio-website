[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetProject,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [string]$DefaultBranch = 'main',
    [switch]$Overwrite,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repositoryInstaller = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\installer\install-to-project.ps1'))
if (-not (Test-Path -LiteralPath $repositoryInstaller -PathType Leaf)) {
    Write-Error 'This entry point must be run from the workflow source repository. Use installer/install-to-project.ps1.'
    exit 1
}
$arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $repositoryInstaller,
    '-TargetProject', $TargetProject, '-ProjectName', $ProjectName,
    '-DefaultBranch', $DefaultBranch
)
if ($Overwrite) { $arguments += '-Overwrite' }
if ($DryRun) { $arguments += '-DryRun' }
if ($Json) { $arguments += '-Json' }
& powershell.exe @arguments
exit $LASTEXITCODE

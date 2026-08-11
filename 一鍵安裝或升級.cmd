@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Codex 跨裝置工作流－一鍵安裝或升級

set "CODEX_WORKFLOW_TARGET=%~dp0"
echo.
echo ============================================
echo   Codex 跨裝置工作流－一鍵安裝或升級
echo ============================================
echo.
echo [1] 完整安裝或升級（推薦）
echo [2] ProjectOnly - update this project
echo [3] 只執行健康檢查
echo.
choice /C 123 /N /M "請選擇 1、2 或 3："
if errorlevel 3 set "CODEX_WORKFLOW_MODE=HealthCheck"
if errorlevel 2 if not errorlevel 3 set "CODEX_WORKFLOW_MODE=ProjectOnly"
if errorlevel 1 if not errorlevel 2 set "CODEX_WORKFLOW_MODE=Full"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; function Run([string]$file,[string[]]$arguments){$process=Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru -NoNewWindow; return ($process.ExitCode-eq0)}; $target=[IO.Path]::GetFullPath($env:CODEX_WORKFLOW_TARGET).TrimEnd([IO.Path]::DirectorySeparatorChar); $mode=$env:CODEX_WORKFLOW_MODE; $temp=Join-Path ([IO.Path]::GetTempPath()) ('codex_workflow_bootstrap_'+[Guid]::NewGuid().ToString('N')); try { $gh=Get-Command gh.exe -ErrorAction SilentlyContinue; if(-not $gh){ $winget=Get-Command winget.exe -ErrorAction Stop; if(-not(Run $winget.Source @('install','--id','GitHub.cli','-e','--accept-package-agreements','--accept-source-agreements','--silent'))){throw 'GitHub CLI 安裝失敗。'}; $gh=Get-Command gh.exe -ErrorAction SilentlyContinue; if(-not $gh){$candidate=Join-Path (Join-Path $env:ProgramFiles 'GitHub CLI') 'gh.exe'; if(Test-Path $candidate){$gh=[pscustomobject]@{Source=$candidate}}} }; if(-not $gh){throw '找不到 GitHub CLI。'}; if(-not(Run $gh.Source @('auth','status'))){ if(-not(Run $gh.Source @('auth','login'))){throw 'GitHub 登入失敗。'} }; if(-not(Run $gh.Source @('repo','clone','kuanyu-10/codex-cross-device-workflow',$temp,'--','--depth','1','--branch','main'))){throw '下載工作流失敗。'}; $remote=(git -C $temp remote get-url origin).Trim(); if($remote.TrimEnd('/')-notin @('https://github.com/kuanyu-10/codex-cross-device-workflow.git','git@github.com:kuanyu-10/codex-cross-device-workflow.git')){throw ('工作流來源驗證失敗：'+$remote)}; $setup=Join-Path (Join-Path $temp 'installer') 'one-click-setup.ps1'; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup -TargetProject $target -Mode $mode; $code=$LASTEXITCODE } catch { Write-Host ('安裝狀態：BLOCKED（受阻）') -ForegroundColor Red; Write-Host ('⚠ 注意事項：'+$_.Exception.Message) -ForegroundColor Yellow; $code=1 } finally { if((Test-Path $temp)-and([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase))){Remove-Item -LiteralPath $temp -Recurse -Force} };; if($code-eq0){Write-Host '安裝程序已完成。'}else{Write-Host '安裝未完成，請查看上方的 BLOCKED 或注意事項。'}; Write-Host '按 Enter 關閉視窗。'; $null=[Console]::ReadLine(); exit $code"

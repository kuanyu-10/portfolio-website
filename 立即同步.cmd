@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "PROJECT_ROOT=%~dp0."
set "SYNC_SCRIPT=%~dp0scripts\workflow\invoke_short_command.ps1"

echo ============================================================
echo 立即同步：%~dp0
echo 目標：Obsidian / Google Drive / NotebookLM / 知識網站
echo ============================================================
echo.

if not exist "%SYNC_SCRIPT%" (
  echo 同步失敗：找不到 %SYNC_SCRIPT%
  echo 請先執行「導入專案.cmd」安裝或升級工作流。
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%" -Command "整" -ProjectPath "%PROJECT_ROOT%"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo 同步流程已完成。請查看上方各服務狀態。
) else (
  echo 同步未完全成功，exit code：%RESULT%
  echo 請查看上方的 PARTIAL、NOT_CONFIGURED 或錯誤訊息。
)
echo.
pause
exit /b %RESULT%

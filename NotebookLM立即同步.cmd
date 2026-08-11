@echo off
setlocal EnableExtensions
chcp 65001 >nul
set "PROJECT_ROOT=%~dp0."
set "SYNC_SCRIPT=%~dp0scripts\workflow\invoke_notebooklm_now.ps1"

echo ============================================================
echo NotebookLM 立即同步
echo ============================================================
echo.
if not exist "%SYNC_SCRIPT%" (
  echo 找不到 NotebookLM 同步腳本，請先執行「導入專案.cmd」升級工作流。
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SYNC_SCRIPT%" -ProjectPath "%PROJECT_ROOT%"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo NotebookLM 同步流程已完成。
) else (
  echo NotebookLM 同步未完成，請查看上方訊息。
)
echo.
pause
exit /b %RESULT%

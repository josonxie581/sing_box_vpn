@echo off
setlocal
set "TASK_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%TASK_PWSH%" (
  echo PowerShell 7 is required.
  pause
  exit /b 1
)
"%TASK_PWSH%" -NoProfile -File "%~dp0inspect_vps_exits.ps1"
set "TASK_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %TASK_EXIT%

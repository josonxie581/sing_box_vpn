@echo off
setlocal
set "TASK_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%TASK_PWSH%" (
  echo PowerShell 7 is required. Run tools\restore_dmit.ps1 with pwsh.
  pause
  exit /b 1
)
"%TASK_PWSH%" -NoProfile -File "%~dp0tools\restore_dmit.ps1" -ReleaseDirectory "%~dp0."
set "TASK_EXIT=%ERRORLEVEL%"
echo.
if not "%TASK_EXIT%"=="0" echo Recovery did not finish. Check the error above.
pause
exit /b %TASK_EXIT%

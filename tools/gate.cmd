@echo off
rem Unified local gate. Default: 1000 seeds on floor 1.
rem Full: tools\gate.cmd --full (3000 seeds x 3 floors + perf probe).
setlocal
set PS=powershell
if "%~1"=="--full" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0gate.ps1" -Seeds 3000 -Floors 1,2,3 -Full
) else (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0gate.ps1" %*
)
exit /b %ERRORLEVEL%

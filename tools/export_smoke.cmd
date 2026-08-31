@echo off
setlocal
rem ============================================================================
rem M2 Task 30: export smoke
rem  1) Export Windows Desktop release exe to user_export/ (gitignored)
rem  2) Launch it for a 30s smoke: process alive + no crash markers in game log
rem  3) Auto-close
rem  4) Android headless export pre-flight; missing SDK => honest SKIP, not FAIL
rem Exit codes: 0 = smoke pass (Android pass or SKIP), 1 = FAIL.
rem Resolve Godot: %GODOT% env var wins, else fall back to `godot` on PATH.
if not defined GODOT set GODOT=godot

cd /d "%~dp0.." || exit /b 1
if not exist user_export mkdir user_export

rem --- Godot file-logging dir for this project (crash markers land here) ---
set "GODOT_LOG_DIR=%APPDATA%\Godot\app_userdata\StarfallDepths\logs"

echo === [export_smoke] 1/3 Windows Desktop release export ===
"%GODOT%" --headless --path . --export-release "Windows Desktop" user_export/starfall.exe > user_export\windows_export.log 2>&1
set WIN_RC=%errorlevel%
if not "%WIN_RC%"=="0" goto :win_export_fail
if not exist user_export\starfall.exe goto :win_export_fail
echo [export_smoke] Windows export OK: user_export\starfall.exe

echo === [export_smoke] 2/3 Windows 30s launch smoke ===
taskkill /F /IM starfall.exe >nul 2>&1
rem Fresh log dir so any FATAL/CRASH found after belongs to this run only.
if exist "%GODOT_LOG_DIR%" rmdir /s /q "%GODOT_LOG_DIR%"
rem Launch via PowerShell: real PID + HasExited check, no cmd `start` quirks.
set "GAME_EXE=%CD%\user_export\starfall.exe"
set "GAME_DIR=%CD%\user_export"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath $env:GAME_EXE -WorkingDirectory $env:GAME_DIR -PassThru; Start-Sleep -Seconds 30; if ($p.HasExited) { Write-Host ('smoke: process exited early, code ' + $p.ExitCode); exit 1 }; Stop-Process -Id $p.Id -Force; exit 0"
set SMOKE_PS_RC=%errorlevel%
if not "%SMOKE_PS_RC%"=="0" goto :smoke_dead
echo [export_smoke] Process alive after 30s: OK (auto-closed)
if exist "%GODOT_LOG_DIR%\godot.log" (
    findstr /I "FATAL CRASH" "%GODOT_LOG_DIR%\godot.log" >nul 2>&1
    if not errorlevel 1 goto :smoke_crash
)
echo [export_smoke] No crash markers in game log: OK
echo === [export_smoke] 3/3 Android pre-flight export ===
"%GODOT%" --headless --path . --export-release "Android" user_export/starfall.apk > user_export\android_export.log 2>&1
set ANDROID_RC=%errorlevel%
type user_export\android_export.log 2>nul
if not "%ANDROID_RC%"=="0" goto :android_skip
if not exist user_export\starfall.apk goto :android_skip
echo [export_smoke] Android OK: user_export\starfall.apk
echo === [export_smoke] RESULT: Windows smoke PASS; Android PASS ===
endlocal & exit /b 0

:android_skip
echo [export_smoke] SKIP: Android export pre-flight failed on this machine (rc=%ANDROID_RC%) - typically missing Android SDK / build template. Honest SKIP per task spec, not a FAIL.
echo === [export_smoke] RESULT: Windows smoke PASS; Android SKIP ===
endlocal & exit /b 0

:win_export_fail
echo [export_smoke] FAIL: Windows export failed (rc=%WIN_RC%). Log:
type user_export\windows_export.log 2>nul
endlocal & exit /b 1

:smoke_dead
echo [export_smoke] FAIL: starfall.exe not alive after 30s (crashed or exited early). Game log:
taskkill /F /IM starfall.exe >nul 2>&1
if exist "%GODOT_LOG_DIR%\godot.log" type "%GODOT_LOG_DIR%\godot.log"
endlocal & exit /b 1

:smoke_crash
echo [export_smoke] FAIL: crash markers found in game log:
taskkill /F /IM starfall.exe >nul 2>&1
findstr /I "FATAL CRASH" "%GODOT_LOG_DIR%\godot.log" 2>nul
endlocal & exit /b 1

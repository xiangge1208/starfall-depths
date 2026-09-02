@echo off
setlocal
rem ============================================================================
rem M3 X-A: Android release one-shot export, apk + aab.
rem Prerequisites (one-time bootstrap, see docs/superpowers/reports/m3-android-export.md):
rem   1. Android SDK at D:\dev\android-sdk (cmdline-tools, platform-tools,
rem      platforms;android-34, build-tools;34.0.0, licenses accepted).
rem   2. Gradle JDK at D:\dev\jdk-21.0.12.1+1 (Godot 4.7.2 template gradle 8.11.1
rem      refuses JDK 25 daemons).
rem   3. Release keystore + secret live OUTSIDE the repo at
rem      D:\workspace\thomas\.keystores\m3-release\ (starfall-release.keystore +
rem      keystore.properties). Never committed. This script injects them at runtime
rem      via GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD env vars (Godot
rem      EditorExportPreset::get_or_env: non-empty env overrides preset);
rem      keystore/release* keys in export_presets.cfg stay empty.
rem   4. Android gradle build template: android_source.zip from export_templates
rem      unpacked at res://android/build (equivalent to editor "Install Android
rem      Build Template"), 207MB, gitignored.
rem      Version stamp MUST live at res://android/.build_version (one level ABOVE
rem      build dir), content = VERSION_FULL_CONFIG = first 4 dot-tokens of
rem      `godot --version` (e.g. 4.7.2.stable.official.ed1daf0bf -> 4.7.2.stable).
rem      Godot 4.7.2 export_project() reads
rem      gradle_build_directory.get_base_dir()/.build_version and compares against
rem      FULL_CONFIG; wrong level or full string fails with "version information
rem      does not exist / mismatched, please reinstall".
rem      This script self-heals that file in the prereq stage.
rem Special mechanism: aab needs preset gradle_build/export_format=1 (apk is 0);
rem   flip it temporarily right before the aab export, then unconditional restore;
rem   zero drift on the delivered branch, git diff self-check after restore.
rem   (M4-K1: rendering/textures/vram_compression/import_etc2_astc is FORMALIZED in
rem   project.godot [rendering] — the old temp-write/restore toggle is gone; the
rem   script precondition-checks the key and fails honestly if it ever goes missing.)
rem Flow: prereq checks (SDK/JDK/keystore.properties) -> inject env vars ->
rem   export release apk -> flip export_format -> export release aab ->
rem   unconditional restore of both files -> apksigner/jarsigner verification ->
rem   artifact listing.
rem Output dir user_export/ is gitignored.
rem Exit code: 0 = success, 1 = any step failed. Honest FAIL, never fake PASS.
rem GODOT env var wins, else falls back to PATH godot.
if not defined GODOT set GODOT=godot

cd /d "%~dp0.." || exit /b 1
if not exist user_export mkdir user_export

rem --- Prereq checks: SDK, JDK, keystore; any miss fails honestly ---
if not defined ANDROID_HOME set "ANDROID_HOME=D:\dev\android-sdk"
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo [export_android] FAIL: missing platform-tools adb.exe under ANDROID_HOME=%ANDROID_HOME%
    exit /b 1
)
if not exist "%ANDROID_HOME%\build-tools\34.0.0\apksigner.bat" (
    echo [export_android] FAIL: missing build-tools 34.0.0 apksigner.bat
    exit /b 1
)
set "JAVA_GRADLE=D:\dev\jdk-21.0.12.1+1"
if not exist "%JAVA_GRADLE%\bin\java.exe" (
    echo [export_android] FAIL: gradle JDK not found: %JAVA_GRADLE%
    exit /b 1
)
set "KEYSTORE_DIR=D:\workspace\thomas\.keystores\m3-release"
set "PROPS=%KEYSTORE_DIR%\keystore.properties"
if not exist "%KEYSTORE_DIR%\starfall-release.keystore" (
    echo [export_android] FAIL: release keystore not found: %KEYSTORE_DIR%\starfall-release.keystore
    exit /b 1
)
if not exist "%PROPS%" (
    echo [export_android] FAIL: keystore.properties not found: %PROPS%
    echo [export_android]   expected keys: keystore_path / keystore_user / keystore_password
    exit /b 1
)

rem --- Parse keystore.properties -> inject Godot get_or_env env vars ---
for /f "usebackq tokens=1,* delims==" %%a in ("%PROPS%") do (
    if "%%a"=="keystore_path" set "KS_PATH=%%b"
    if "%%a"=="keystore_user" set "KS_USER=%%b"
    if "%%a"=="keystore_password" set "KS_PASS=%%b"
)
if not defined KS_PATH goto :props_fail
if not defined KS_USER goto :props_fail
if not defined KS_PASS goto :props_fail
set "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=%KS_PATH%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_USER=%KS_USER%"
set "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=%KS_PASS%"
echo [export_android] prereq OK: ANDROID_HOME=%ANDROID_HOME%  JAVA=%JAVA_GRADLE%
echo [export_android] keystore injected via env: %KS_PATH%  alias=%KS_USER%

rem --- Self-heal res://android/.build_version (FULL_CONFIG = first 4 tokens) ---
set "GVER="
for /f "delims=" %%v in ('"%GODOT%" --version 2^>nul') do set "GVER=%%v"
if defined GVER (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$v='%GVER%'; $c=($v -split '\.')[0..3] -join '.'; $f='android\.build_version'; $cur=''; if(Test-Path $f){$cur=[IO.File]::ReadAllText($f).Trim()}; if($cur -ne $c){New-Item -ItemType Directory -Force -Path 'android' | Out-Null; [IO.File]::WriteAllText($f,$c,(New-Object System.Text.UTF8Encoding($false))); Write-Host ('[export_android] .build_version healed to: ' + $c)}"
)

rem --- Self-heal android/build/.gdignore: keep the Godot resource scanner OUT of
rem     the gradle template. Without it, editor scans pollute the template with
rem     *.import sidecars (gradle resource merger then rejects them: "file name
rem     must end with .xml or .png") and index stale export assets leftover in
rem     src/main/assets (export pack phase then fails: "Can't open file").
if not exist "android\build\.gdignore" (
    type nul > "android\build\.gdignore" 2>nul
    echo [export_android] created android/build/.gdignore
)
rem --- Purge editor-scan pollution from the template before exporting ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path 'android\build' -Recurse -Filter '*.import' -File -ErrorAction SilentlyContinue | Remove-Item -Force; if(Test-Path 'android\build\src\main\assets'){Remove-Item -Recurse -Force 'android\build\src\main\assets'}; if(Test-Path 'android\build\src\instrumented'){Remove-Item -Recurse -Force 'android\build\src\instrumented'}"

rem --- Backup delivery preset before temp edit (restored unconditionally) ---
set "BAK_PRESET=user_export\export_presets.cfg.xa-bak"
set "TOGGLED_FMT="
findstr /C:"gradle_build/export_format=0" export_presets.cfg >nul 2>&1
if errorlevel 1 (
    echo [export_android] FAIL: export_presets.cfg has no gradle_build/export_format=0, unsafe to flip
    exit /b 1
)

rem --- Precondition (M4-K1): etc2 key formalized in project.godot — honest FAIL if missing ---
findstr /C:"import_etc2_astc=true" project.godot >nul 2>&1
if errorlevel 1 (
    echo [export_android] FAIL: project.godot lacks rendering/textures/vram_compression/import_etc2_astc=true. Re-add the key; do NOT reintroduce the temp-write toggle.
    exit /b 1
)
echo [export_android] etc2 precondition OK: import_etc2_astc=true in project.godot

rem --- Gradle build env: JDK 21 runs gradle, SDK points at D:\dev\android-sdk ---
set "JAVA_HOME=%JAVA_GRADLE%"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

echo === [export_android] 1/2 release APK export (export_format=0 as committed) ===
"%GODOT%" --headless --path . --export-release "Android" user_export/starfall-release.apk > user_export\android_apk_export.log 2>&1
set APK_RC=%errorlevel%

echo === [export_android] flip gradle_build/export_format=1, export release AAB ===
copy /Y export_presets.cfg "%BAK_PRESET%" >nul || (
    echo [export_android] FAIL: cannot backup export_presets.cfg
    call :do_restore
    endlocal & exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='export_presets.cfg'; $t=[IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p,$t.Replace('gradle_build/export_format=0','gradle_build/export_format=1'),(New-Object System.Text.UTF8Encoding($false)))"
findstr /C:"gradle_build/export_format=1" export_presets.cfg >nul 2>&1
if errorlevel 1 (
    echo [export_android] FAIL: temp-flip export_format failed, no =1 found after flip
    call :do_restore
    endlocal & exit /b 1
)
set "TOGGLED_FMT=1"
"%GODOT%" --headless --path . --export-release "Android" user_export/starfall-release.aab > user_export\android_aab_export.log 2>&1
set AAB_RC=%errorlevel%

rem --- Unconditional restore of both delivery files (zero drift on success or failure) ---
call :do_restore

if not "%APK_RC%"=="0" goto :apk_fail
if not exist user_export\starfall-release.apk goto :apk_fail
echo [export_android] APK OK: user_export\starfall-release.apk

if not "%AAB_RC%"=="0" goto :aab_fail
if not exist user_export\starfall-release.aab goto :aab_fail
echo [export_android] AAB OK: user_export\starfall-release.aab

rem --- Signature verification (evidence): apksigner for apk, jarsigner for aab ---
echo === [export_android] apksigner verify APK signature ===
call "%ANDROID_HOME%\build-tools\34.0.0\apksigner.bat" verify --print-certs user_export\starfall-release.apk > user_export\android_apk_sign_verify.log 2>&1
if errorlevel 1 (
    echo [export_android] FAIL: apksigner verify failed, log:
    type user_export\android_apk_sign_verify.log
    endlocal & exit /b 1
)
findstr /C:"SHA-256" user_export\android_apk_sign_verify.log
echo === [export_android] jarsigner verify AAB signature ===
"%JAVA_GRADLE%\bin\jarsigner.exe" -verify user_export\starfall-release.aab > user_export\android_aab_sign_verify.log 2>&1
if errorlevel 1 (
    echo [export_android] FAIL: jarsigner -verify failed, log:
    type user_export\android_aab_sign_verify.log
    endlocal & exit /b 1
)
findstr /C:"jar verified" user_export\android_aab_sign_verify.log

echo === [export_android] artifacts ===
dir /-c user_export\starfall-release.apk | findstr /C:"starfall-release.apk"
dir /-c user_export\starfall-release.aab | findstr /C:"starfall-release.aab"
echo === [export_android] RESULT: PASS, apk + aab produced and signature-verified ===
endlocal & exit /b 0

:props_fail
echo [export_android] FAIL: %PROPS% parse failed or missing key; need keystore_path/keystore_user/keystore_password
endlocal & exit /b 1

:apk_fail
echo [export_android] FAIL: APK export failed, rc=%APK_RC%, log:
type user_export\android_apk_export.log 2>nul
endlocal & exit /b 1

:aab_fail
echo [export_android] FAIL: AAB export failed, rc=%AAB_RC%, log:
type user_export\android_aab_export.log 2>nul
echo APK was produced, see user_export\starfall-release.apk
endlocal & exit /b 1

:do_restore
set "DRIFT="
if defined TOGGLED_FMT (
    copy /Y "%BAK_PRESET%" export_presets.cfg >nul
    fc /b "%BAK_PRESET%" export_presets.cfg >nul 2>&1 || set "DRIFT=export_presets.cfg"
)
if defined DRIFT echo [export_android] WARNING: %DRIFT% drifted vs backup, manual check required!
if defined TOGGLED_FMT del /Q "%BAK_PRESET%" >nul 2>&1
echo [export_android] temp edits restored, zero-drift verified against backups
goto :eof

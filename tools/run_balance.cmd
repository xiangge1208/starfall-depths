@echo off
rem M2 Task 27 (H-1)：Balance Bot 全层回归一键挂载。
rem 用法：tools\run_balance.cmd [runs] [seed-base]
rem   默认 10 局，种子 2001..2010；报告与 JSON 落 docs/superpowers/reports/。
rem   注意：引擎 time_scale 对本作逐拍定步长逻辑无加速效用——bot 以墙钟真实速率
rem   游玩（GDD 口径即玩家体验时长），单局约 1~15 min，整批约 1~2.5 h。
setlocal
if not defined GODOT set GODOT=godot
set RUNS=%1
if "%RUNS%"=="" set RUNS=10
set SEEDBASE=%2
if "%SEEDBASE%"=="" set SEEDBASE=2001

"%GODOT%" --headless --path . --import
if errorlevel 1 (
  echo [run_balance] import failed
  exit /b 1
)

"%GODOT%" --headless --path . res://tools/balance_bot.tscn -- ^
  --runs=%RUNS% --seed-base=%SEEDBASE% ^
  --out-md=docs/superpowers/reports/m2-balance-2026-08-31.md ^
  --out-json=docs/superpowers/reports/m2-balance-2026-08-31.json
if errorlevel 1 (
  echo [run_balance] balance bot FAILED ^(crashes/timeout^)
  exit /b 1
)
echo [run_balance] OK: report at docs/superpowers/reports/m2-balance-2026-08-31.md
endlocal

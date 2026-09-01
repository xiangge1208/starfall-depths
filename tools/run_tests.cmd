@echo off
rem Resolve Godot: %GODOT% env var wins, else fall back to `godot` on PATH.
if not defined GODOT set GODOT=godot
rem Rebuild the global class cache first: merges introducing new class_name
rem scripts otherwise fail every suite with "Could not find type" parse errors
rem until a manual import pass (same bootstrap run_balance.cmd already does).
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode %*

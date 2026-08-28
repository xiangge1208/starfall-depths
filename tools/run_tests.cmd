@echo off
rem Resolve Godot: %GODOT% env var wins, else fall back to `godot` on PATH.
if not defined GODOT set GODOT=godot
"%GODOT%" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode %*

@echo off
REM Launches the game directly, no editor. Fastest way to test.
cd /d "%~dp0"
start "" "%~dp0..\pronto-expo\Godot_v4.7.1-stable_win64.exe" --path "%~dp0."

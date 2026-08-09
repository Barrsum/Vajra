@echo off
REM Opens the project in the Godot editor, for tweaking values in the Inspector.
cd /d "%~dp0"
start "" "%~dp0..\pronto-expo\Godot_v4.7.1-stable_win64.exe" --editor --path "%~dp0."

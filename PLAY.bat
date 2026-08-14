@echo off
REM Launches VAJRA directly, no editor. Fastest way to play.
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1
start "" "%GODOT_EXE%" --path "%~dp0."

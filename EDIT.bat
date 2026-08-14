@echo off
REM Opens the project in the Godot editor, for tweaking values in the Inspector.
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1
start "" "%GODOT_EXE%" --editor --path "%~dp0."

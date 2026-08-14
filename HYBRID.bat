@echo off
REM The hybrid: GDQuest movement+camera, our blade, combo, dodge and Mutants.
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1
start "" "%GODOT_EXE%" --path "%~dp0." res://scenes/main_hybrid.tscn

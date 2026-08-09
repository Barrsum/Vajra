@echo off
REM The hybrid: GDQuest movement+camera, our blade, combo, dodge and Mutants.
cd /d "%~dp0"
start "" "%~dp0..\pronto-expo\Godot_v4.7.1-stable_win64.exe" --path "%~dp0." res://scenes/main_hybrid.tscn

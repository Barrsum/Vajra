@echo off
REM Runs GDQuest's complete third-person controller in our street, unmodified.
REM Compare directly against PLAY.bat (ours).
REM Their controls: WASD move, SPACE jump, LMB melee, RMB aim, Q swap weapon.
cd /d "%~dp0"
start "" "%~dp0..\pronto-expo\Godot_v4.7.1-stable_win64.exe" --path "%~dp0." res://scenes/compare_gdquest.tscn

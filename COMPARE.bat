@echo off
REM Runs GDQuest's complete third-person controller in our street, unmodified.
REM Compare directly against PLAY.bat (ours).
REM Their controls: WASD move, SPACE jump, LMB melee, RMB aim, Q swap weapon.
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1
start "" "%GODOT_EXE%" --path "%~dp0." res://scenes/compare_gdquest.tscn

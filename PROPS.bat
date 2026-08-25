@echo off
REM The prop lab: every generated asset on a floor, with a 1.8m reference
REM figure, a free camera and a resize control. No enemies, no combat.
REM
REM   WASD + mouse  fly            SHIFT  faster        Q/E  down/up
REM   TAB           next prop      [ ]    resize        R    respin
REM   P             print the line to paste into world.gd
REM   ALT           free the cursor        ESC  quit
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1
start "" "%GODOT_EXE%" --path "%~dp0." res://scenes/prop_lab.tscn

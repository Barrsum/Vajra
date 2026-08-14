@echo off
REM Runs the whole automated suite headless. Every suite asserts and exits
REM non-zero on failure, so this is the one command to run before committing.
setlocal
cd /d "%~dp0"
call "%~dp0find_godot.bat" || exit /b 1

REM find_godot prefers the windowed build, which on Windows writes nothing to
REM the terminal. For tests we want the opposite, so switch to the _console
REM twin if it is there. If it is not, the substitution names a file that does
REM not exist and we keep what we had.
set "GODOT_RUN=%GODOT_EXE%"
if exist "%GODOT_EXE:.exe=_console.exe%" set "GODOT_RUN=%GODOT_EXE:.exe=_console.exe%"

set FAILED=0
for %%T in (anim_pool_test level1_test level2_test level3_test level4_test flow_test) do (
	echo.
	echo ===== %%T =====
	"%GODOT_RUN%" --headless --path "%~dp0." res://tests/%%T.tscn
	if errorlevel 1 set FAILED=1
)

echo.
if "%FAILED%"=="1" (
	echo ***** SUITE FAILED *****
	exit /b 1
)
echo ***** ALL SUITES PASS *****
exit /b 0

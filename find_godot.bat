@echo off
REM Sets GODOT_EXE for the caller, or prints instructions and returns 1.
REM Shared by PLAY / EDIT / TEST / COMPARE / HYBRID so the search lives in one
REM place.
REM
REM Deliberately no setlocal: the whole point is to set a variable the calling
REM script can still see.

set "GODOT_EXE="

REM 1. A copy inside the repo, in godot\ (gitignored, so it never gets pushed).
call :scan "%~dp0godot\Godot_v*.exe"

REM 2. Sitting beside the project folder.
if not defined GODOT_EXE call :scan "%~dp0..\Godot_v*.exe"
if not defined GODOT_EXE call :scan "%~dp0..\pronto-expo\Godot_v*.exe"

REM 3. A GODOT environment variable pointing straight at the exe.
if not defined GODOT_EXE if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

REM 4. On PATH.
if not defined GODOT_EXE for %%F in (godot.exe) do if not "%%~$PATH:F"=="" set "GODOT_EXE=%%~$PATH:F"

if defined GODOT_EXE exit /b 0

echo.
echo   Could not find Godot.
echo.
echo   VAJRA needs Godot 4.7.1 ^(Standard, not .NET^). It is one portable
echo   .exe - there is nothing to install.
echo.
echo     1. Download it:  https://godotengine.org/download/archive/
echo     2. Make a folder called  godot  next to this file.
echo     3. Put Godot_v4.7.1-stable_win64.exe inside it.
echo     4. Run PLAY.bat again.
echo.
pause
exit /b 1

:scan
REM Two passes over the same pattern. The first takes anything; the second lets
REM a non-console build overwrite it. Godot ships both, and the _console build
REM opens a second terminal window alongside the game — fine for tests, wrong
REM for playing. Preference by overwrite avoids needing delayed expansion.
for %%F in (%~1) do if exist "%%~fF" set "GODOT_EXE=%%~fF"
for %%F in (%~1) do if exist "%%~fF" call :prefer "%%~fF"
exit /b 0

:prefer
REM Sets GODOT_EXE only if this filename does not contain _console. Done with
REM string substitution rather than piping to find.exe, because anyone with
REM Git Bash or GnuWin on PATH has a completely different `find` that would
REM shadow the Windows one and break the check.
set "N=%~nx1"
set "S=%N:_console=%"
if "%S%"=="%N%" set "GODOT_EXE=%~f1"
exit /b 0

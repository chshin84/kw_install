@echo off
rem Double-click entry point for the workstation setup.
rem
rem PowerShell 7 is a hard prerequisite and is installed before this ever runs,
rem so there is no fallback here. If pwsh is missing this stops loudly rather
rem than handing the script to Windows PowerShell 5.1 - 5.1 refuses a
rem #Requires -Version 7.0 script with an error and still exits 0, which would
rem read as success to anything checking the exit code.
rem
rem ASCII only. A .cmd with non-ASCII text is read in the system code page and
rem the parser breaks on machines whose code page differs.

setlocal EnableExtensions
chcp 65001 >nul

echo (Any "UNC paths are not supported" notice above is expected and harmless.)
echo.

rem Explorer starts cmd in the Windows directory when a script is launched from
rem a UNC share, so nothing here may depend on the current directory. %~dp0
rem still expands to the share path, and that is what gets passed on.
set "SETUP=%~dp0setup.ps1"

if not exist "%SETUP%" (
    echo Cannot find setup.ps1 next to this file:
    echo   %SETUP%
    echo Copy the whole folder, not just this one file.
    set "RC=9"
    goto :finish
)

rem The MSI build lands in Program Files and the Store build in WindowsApps.
rem Both are probed as well as PATH, since a PATH change made by an installer
rem does not reach a shell that is already running.
set "PWSH="
for %%P in (pwsh.exe) do if not defined PWSH set "PWSH=%%~$PATH:P"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LocalAppData%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LocalAppData%\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH (
    echo PowerShell 7 is not on this machine.
    echo Install "PowerShell" from the Microsoft Store, then run this again.
    echo Nothing was changed.
    set "RC=9"
    goto :finish
)

echo Using: %PWSH%
echo.
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SETUP%" %*
set "RC=%ERRORLEVEL%"

:finish
echo.
echo Exit code: %RC%

rem This file exists so a person can double-click it, and a window that closes
rem on its own shows nothing. The pause is therefore unconditional. Anything
rem unattended should call setup.ps1 directly and skip this wrapper.
pause

exit /b %RC%

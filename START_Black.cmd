@echo off
setlocal
title Black Pet launcher
cd /d "%~dp0"
set "PET_DIR=%~dp0"
set "MODE=%~1"

if not exist "%~dp0BlackPet.ps1" goto missing

rem Safety check only reads settings. It never changes them.
rem 2 = this PC requires signed scripts, 3 = file came from the internet, 4 = PowerShell is locked down.
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='SilentlyContinue'; $f=Join-Path $env:PET_DIR 'BlackPet.ps1'; $set=@(Get-ExecutionPolicy -List | Where-Object { $_.Scope -ne 'Process' -and [string]$_.ExecutionPolicy -ne 'Undefined' }); if ($set.Count -gt 0 -and @('Restricted','AllSigned') -contains [string](Get-ExecutionPolicy)) { exit 2 }; if (Get-Item -LiteralPath $f -Stream 'Zone.Identifier') { exit 3 }; if ([string]$ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 4 }; exit 0"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto blocked
if /i "%MODE%"=="diag" goto diag

start "Black Pet" /min powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -STA -File "%~dp0BlackPet.ps1"
exit /b 0

:diag
echo Black Pet diagnostic mode: this window stays open and shows any error.
echo Close Xiaohei with right-click, then read the result here.
echo.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -STA -File "%~dp0BlackPet.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo Black Pet has closed. Exit code: %RC%
echo If an error is shown above, please take a screenshot. Error files: BlackPet_Error_*.txt
pause
exit /b %RC%

:missing
echo [Cannot start] BlackPet.ps1 was not found. Keep all files of this folder together.
pause
exit /b 1

:blocked
echo.
if "%RC%"=="2" goto why_policy
if "%RC%"=="3" goto why_internet
if "%RC%"=="4" goto why_locked
if "%RC%"=="9009" goto why_nops
echo [Cannot start] Unexpected result from the safety check, code %RC%.
goto stop_here

:why_internet
echo [Cannot start] Windows marks BlackPet.ps1 as "downloaded from the internet", so it will not run.
echo This happens with a ZIP from GitHub, e-mail, Teams or a web browser.
echo.
echo To allow it - only needed once:
echo   1. Close this window.
echo   2. In this folder, right-click BlackPet.ps1 and choose Properties.
echo   3. At the bottom of the General tab, tick "Unblock", then click OK.
echo   4. Double-click START_Black.cmd again.
echo.
echo No "Unblock" box? Then this PC does not allow it, and this program will not work around that.
echo Use the folder that OneDrive synced to this PC, or ask IT.
goto show_help

:why_policy
echo [Cannot start] PowerShell on this PC is set to block unsigned scripts. This program will not override that setting. On a company-managed PC, please contact IT.
goto show_help

:why_locked
echo [Cannot start] PowerShell is locked down on this PC by device management. This program will not work around it. Please contact IT.
goto show_help

:why_nops
echo [Cannot start] Windows PowerShell was not found on this PC.
goto stop_here

:show_help
rem The same steps in Chinese, opened in Notepad.
if exist "%~dp0docs\start_help.txt" (
    echo.
    echo The steps in Chinese are shown in Notepad: docs\start_help.txt
    start "" notepad.exe "%~dp0docs\start_help.txt"
)

:stop_here
echo.
pause
exit /b %RC%

@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  release.bat
REM
REM  Packs the BUILT behavior pack and resource pack (the "output"
REM  profile that output.bat produces) into one .mcaddon and files it
REM  under assets\version\ :
REM
REM    assets\version\v<BP version>__<RP version>__<index>\<same>.mcaddon
REM
REM  Every run makes a new folder. The index counts up (0, 1, 2, ...) for
REM  as long as the BP and RP versions in their manifest.json stay the
REM  same, and restarts at 0 when either version changes. Nothing that is
REM  already in assets\version is overwritten.
REM
REM  Run output.bat first: this script packs whatever is currently in the
REM  output folders, it does not rebuild anything.
REM
REM  Must sit in the SAME FOLDER as build.bat. The two folders below must
REM  match the "output" profile (profile 3) in build.bat, and NAMESPACE
REM  must match the /NS: value in output.bat. To use another namespace
REM  for one run:  release.bat /NS:other_ns
REM =====================================================================
set "PROJECT_NAME=My Addon Project Source"
set "NAMESPACE=rl_yn"

for %%A in (%*) do (
    set "ARG=%%~A"
    if /I "!ARG:~0,4!"=="/NS:" set "NAMESPACE=!ARG:~4!"
)

set "OUTPUT_ROOT=C:\%PROJECT_NAME%\Content"
set "BP_DIR=%OUTPUT_ROOT%\behavior_packs\%NAMESPACE%_b"
set "RP_DIR=%OUTPUT_ROOT%\resource_packs\%NAMESPACE%_r"

node "%~dp0..\scripts\release.js" --bp "%BP_DIR%" --rp "%RP_DIR%"
if errorlevel 1 (
    echo.
    pause
    exit /b 1
)
echo.
pause

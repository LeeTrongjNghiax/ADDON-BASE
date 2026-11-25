@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  release.bat
REM
REM  One step from sources to a shippable .mcaddon, no other .bat needed:
REM
REM    1) Bundles the TypeScript (sources\behavior_packs\bp\build.js), so
REM       scripts\index.js is never stale.
REM    2) Runs build.bat into a scratch folder (its "release" profile, #4):
REM       namespace renamed, JSON obfuscated, dev files and folders left
REM       out -- the same pipeline as every other build.
REM    3) Packs that copy into one .mcaddon with scripts\release.js and
REM       files it under assets\version\ :
REM
REM         assets\version\v<BP version>__<RP version>__<index>\<same>.mcaddon
REM
REM       Every run makes a new folder. The index counts up (0, 1, 2, ...)
REM       while the BP and RP versions in their manifest.json stay the
REM       same, and restarts at 0 when either version changes. Nothing
REM       already in assets\version is overwritten.
REM    4) Deletes the scratch folder.
REM
REM  Must sit in the SAME FOLDER as build.bat. Your real source folders and
REM  every other profile folder (dev, live, ...) are left untouched.
REM
REM  NAMESPACE is what "your_namespace" becomes in the released packs. For
REM  one run with another namespace:  release.bat /NS:other_ns
REM =====================================================================
set "NAMESPACE=rl_yn"

for %%A in (%*) do (
    set "ARG=%%~A"
    if /I "!ARG:~0,4!"=="/NS:" set "NAMESPACE=!ARG:~4!"
)

if not defined TEMP (
    echo TEMP is not set, so there is nowhere to build the release copy.
    pause
    exit /b 1
)

REM Scratch location. build.bat's "release" profile reads this variable.
set "RELEASE_STAGE_DIR=%TEMP%\addon-release"
set "BP_DIR=%RELEASE_STAGE_DIR%\behavior_packs\%NAMESPACE%_b"
set "RP_DIR=%RELEASE_STAGE_DIR%\resource_packs\%NAMESPACE%_r"

echo ============================================================
echo  Release 1/3: bundling TypeScript
echo ============================================================
node "%~dp0..\sources\behavior_packs\bp\build.js"
if errorlevel 1 (
    echo.
    echo Bundling failed -- nothing was released.
    pause
    exit /b 1
)
echo.

REM Start from an empty scratch folder so nothing old can slip in.
if exist "%RELEASE_STAGE_DIR%" rmdir /s /q "%RELEASE_STAGE_DIR%"

echo ============================================================
echo  Release 2/3: building the packs ^(namespace %NAMESPACE%, JSON obfuscated^)
echo ============================================================
REM "< nul" keeps build.bat's closing "pause" from waiting for a key.
call "%~dp0build.bat" /BP:4 /RP:4 /NS:%NAMESPACE% /OBF:1 < nul
if errorlevel 1 (
    echo.
    echo The build failed -- nothing was released.
    echo Scratch folder left for inspection: %RELEASE_STAGE_DIR%
    pause
    exit /b 1
)
echo.

echo ============================================================
echo  Release 3/3: packing the .mcaddon
echo ============================================================
node "%~dp0..\scripts\release.js" --bp "%BP_DIR%" --rp "%RP_DIR%"
if errorlevel 1 (
    echo.
    echo Packing failed -- scratch folder left for inspection: %RELEASE_STAGE_DIR%
    pause
    exit /b 1
)

rmdir /s /q "%RELEASE_STAGE_DIR%" 2>nul
echo.
pause

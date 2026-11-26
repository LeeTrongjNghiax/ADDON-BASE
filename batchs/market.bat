@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  market.bat
REM
REM  Builds the packs the same way release.bat does, then packs them into
REM  a Marketplace-style .zip whose only root folder is "Content":
REM
REM    Content\behavior_packs\<namespace>_b\...
REM    Content\resource_packs\<namespace>_r\...
REM
REM    1) Bundles the TypeScript (sources\behavior_packs\bp\build.js).
REM    2) Runs build.bat into a scratch folder (its "release" profile, #4):
REM       namespace renamed, dev files and folders left out. JSON is
REM       obfuscated when OBFUSCATE below is 1.
REM    3) Packs that copy with scripts\market.js and files it under
REM       assets\version\ with the SAME folder rule as release.bat:
REM
REM         assets\version\v<BP>__<RP>__<index>\<ProjectName>_<version>.zip
REM
REM       A new folder every run; the index counts up (0, 1, 2, ...) while
REM       the BP and RP versions in their manifest.json stay the same and
REM       restarts at 0 when either changes. release.bat and market.bat
REM       share that counter, so they never write into the same folder.
REM       <ProjectName> is PROJECT_NAME_DEFAULT in build.bat with spaces
REM       and underscores removed. <version> is what you type when asked
REM       (or pass /VER:1.2.0 to skip the question): letters, digits and
REM       . _ + - only.
REM    4) Deletes the scratch folder.
REM
REM  Must sit in the SAME FOLDER as build.bat. Your real source folders and
REM  every other profile folder are left untouched.
REM
REM  NAMESPACE is what "your_namespace" becomes in the packed packs. For
REM  one run with another namespace:  market.bat /NS:other_ns
REM =====================================================================
set "NAMESPACE=rl_yn"

REM 1 = minify + obfuscate the JSON in the packs, 0 = leave it readable.
set "OBFUSCATE=1"

set "VERSION="
for %%A in (%*) do (
    set "ARG=%%~A"
    if /I "!ARG:~0,4!"=="/NS:" set "NAMESPACE=!ARG:~4!"
    if /I "!ARG:~0,5!"=="/VER:" set "VERSION=!ARG:~5!"
)

if not defined VERSION set /p "VERSION=Version for the zip file name, e.g. 1.0.0: "
if not defined VERSION (
    echo.
    echo No version entered -- nothing was packed.
    pause
    exit /b 1
)

REM Reject a bad version now, before the build takes any time.
node "%~dp0..\scripts\market.js" --check-version "!VERSION!"
if errorlevel 1 (
    echo.
    pause
    exit /b 1
)

if not defined TEMP (
    echo TEMP is not set, so there is nowhere to build the copy.
    pause
    exit /b 1
)

REM Scratch location. build.bat's "release" profile reads this variable.
set "RELEASE_STAGE_DIR=%TEMP%\addon-market"
set "BP_DIR=%RELEASE_STAGE_DIR%\behavior_packs\%NAMESPACE%_b"
set "RP_DIR=%RELEASE_STAGE_DIR%\resource_packs\%NAMESPACE%_r"

echo.
echo ============================================================
echo  Market 1/3: bundling TypeScript
echo ============================================================
node "%~dp0..\sources\behavior_packs\bp\build.js"
if errorlevel 1 (
    echo.
    echo Bundling failed -- nothing was packed.
    pause
    exit /b 1
)
echo.

REM Start from an empty scratch folder so nothing old can slip in.
if exist "%RELEASE_STAGE_DIR%" rmdir /s /q "%RELEASE_STAGE_DIR%"

echo ============================================================
echo  Market 2/3: building the packs ^(namespace %NAMESPACE%, obfuscate JSON: %OBFUSCATE%^)
echo ============================================================
REM "< nul" keeps build.bat's closing "pause" from waiting for a key.
call "%~dp0build.bat" /BP:4 /RP:4 /NS:%NAMESPACE% /OBF:%OBFUSCATE% < nul
if errorlevel 1 (
    echo.
    echo The build failed -- nothing was packed.
    echo Scratch folder left for inspection: %RELEASE_STAGE_DIR%
    pause
    exit /b 1
)
echo.

echo ============================================================
echo  Market 3/3: packing the .zip
echo ============================================================
node "%~dp0..\scripts\market.js" --bp "%BP_DIR%" --rp "%RP_DIR%" --version "!VERSION!"
if errorlevel 1 (
    echo.
    echo Packing failed -- scratch folder left for inspection: %RELEASE_STAGE_DIR%
    pause
    exit /b 1
)

rmdir /s /q "%RELEASE_STAGE_DIR%" 2>nul
echo.
pause

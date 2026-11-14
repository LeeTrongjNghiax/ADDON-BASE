@echo off
setlocal enabledelayedexpansion

REM =====================================================================
REM  zip-parent-folder.bat
REM
REM  Sits at the SAME LEVEL as FolderA and FolderB (same layout as
REM  copy-parent-folder.bat). For each one, it zips the CONTENTS of the
REM  named child folder (bp / rp) -- not the child folder itself, so the
REM  zip has no wrapping "bp"/"rp" folder at its root. It then bundles
REM  those two zip files together into ONE final zip and places it in a
REM  destination folder you choose (or a default fallback if you just
REM  press Enter).
REM
REM  Requires PowerShell 5+ (Compress-Archive), which ships with
REM  Windows 10/11 by default -- nothing extra to install.
REM
REM  Example layout:
REM    project\
REM      zip-parent-folder.bat   <- this file lives here
REM      behavior_packs\
REM        bp\                    <- CONTENTS of this get zipped
REM      resource_packs\
REM        rp\                    <- CONTENTS of this get zipped
REM
REM  Result: addon.zip containing bp.zip and rp.zip, placed in your
REM  chosen destination folder (created if it doesn't exist).
REM =====================================================================

REM ======================= DEFAULTS =======================
REM Same exclude lists as copy-parent-folder.bat, so the zip matches
REM what you'd copy. Wildcards (*.zip, *.md) are supported.
set "EXCLUDE_DIRS=.git node_modules src"
set "EXCLUDE_FILES=compile.bat .gitignore .mcignore .prettierignore .prettierrc build.js eslint.config.ts package-lock.json package.json tsconfig.json *.zip *.md"

set "FOLDER_A_NAME_DEFAULT=behavior_packs"
set "CHILD_A_NAME_DEFAULT=bp"
set "FOLDER_B_NAME_DEFAULT=resource_packs"
set "CHILD_B_NAME_DEFAULT=rp"

REM Used to build the default destination folder if you leave the
REM destination prompt blank: C:\%DEFAULT_DEST_NAME_FALLBACK%
set "DEFAULT_DEST_NAME_FALLBACK=My Addon Project"

REM If you leave the "final zip filename" prompt blank, it falls back to
REM "%DEFAULT_DEST_NAME_FALLBACK%.zip" (built further down, once
REM DEFAULT_DEST_NAME_FALLBACK is known). Whatever you type is always
REM forced to end in .zip, even if you forget to type the extension.
REM ==========================================================

echo ============================================================
echo  Zip Configuration
echo ============================================================
echo.

set "AUTO_MODE=N"
set /p "AUTO_MODE=Run with ALL default settings, no further prompts, and auto-overwrite an existing output zip? (Y/N) [N]: "

if /I "%AUTO_MODE%"=="Y" (
    echo.
    echo Running in ONE-CLICK mode: every setting below uses its default,
    echo and an existing output zip at the destination will be overwritten
    echo automatically without asking.
) else (
    echo.
    echo Running in MANUAL mode: press Enter at any prompt to keep the
    echo default shown in [ ], or type a new value.
)
echo.

if /I not "%AUTO_MODE%"=="Y" set /p "EXCLUDE_DIRS=Folders to exclude, space-separated [%EXCLUDE_DIRS%]: "
if /I not "%AUTO_MODE%"=="Y" set /p "EXCLUDE_FILES=Files to exclude, space-separated (wildcards like *.zip *.md are OK) [%EXCLUDE_FILES%]: "
echo.

set "FOLDER_A_NAME=%FOLDER_A_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "FOLDER_A_NAME=Folder A name [%FOLDER_A_NAME%]: "
set "CHILD_A_NAME=%CHILD_A_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "CHILD_A_NAME=  Child folder inside Folder A to zip [%CHILD_A_NAME%]: "
echo.
set "FOLDER_B_NAME=%FOLDER_B_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "FOLDER_B_NAME=Folder B name [%FOLDER_B_NAME%]: "
set "CHILD_B_NAME=%CHILD_B_NAME_DEFAULT%"
if /I not "%AUTO_MODE%"=="Y" set /p "CHILD_B_NAME=  Child folder inside Folder B to zip [%CHILD_B_NAME%]: "
echo.

set "OUTPUT_ZIP_NAME="
if /I not "%AUTO_MODE%"=="Y" set /p "OUTPUT_ZIP_NAME=Final combined zip filename [leave blank for %DEFAULT_DEST_NAME_FALLBACK%.zip]: "
if "%OUTPUT_ZIP_NAME%"=="" set "OUTPUT_ZIP_NAME=%DEFAULT_DEST_NAME_FALLBACK%.zip"
REM Force a .zip extension regardless of what was typed (case-insensitive check).
if /I not "%OUTPUT_ZIP_NAME:~-4%"==".zip" set "OUTPUT_ZIP_NAME=%OUTPUT_ZIP_NAME%.zip"
echo   Using final zip filename: %OUTPUT_ZIP_NAME%
echo.

set "DEST_DIR="
if /I not "%AUTO_MODE%"=="Y" set /p "DEST_DIR=Destination folder for the final zip [leave blank for C:\%DEFAULT_DEST_NAME_FALLBACK%]: "
if "%DEST_DIR%"=="" set "DEST_DIR=C:\%DEFAULT_DEST_NAME_FALLBACK%"
echo   Using destination: %DEST_DIR%
echo.

REM BASE_DIR = this script's own folder.
for %%I in ("%~dp0") do set "BASE_DIR=%%~fI"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"

set "SOURCE1_PATH=%BASE_DIR%\%FOLDER_A_NAME%\%CHILD_A_NAME%"
set "SOURCE2_PATH=%BASE_DIR%\%FOLDER_B_NAME%\%CHILD_B_NAME%"

if not exist "%SOURCE1_PATH%" (
    echo Child folder for Folder A does not exist: %SOURCE1_PATH%
    pause
    exit /b 1
)
if not exist "%SOURCE2_PATH%" (
    echo Child folder for Folder B does not exist: %SOURCE2_PATH%
    pause
    exit /b 1
)

REM ------------------------------------------------------------------
REM  Staging area: robocopy each source into a temp folder using the
REM  same exclude lists, so the zip matches what copy-parent-folder.bat
REM  would have copied. Cleaned up at the end regardless of outcome.
REM ------------------------------------------------------------------
set "WORK_DIR=%TEMP%\zip-parent-folder-%RANDOM%%RANDOM%"
mkdir "%WORK_DIR%\%CHILD_A_NAME%" >nul 2>&1
mkdir "%WORK_DIR%\%CHILD_B_NAME%" >nul 2>&1

echo ============================================================
echo  Staging %CHILD_A_NAME%
echo ============================================================
robocopy "%SOURCE1_PATH%" "%WORK_DIR%\%CHILD_A_NAME%" /E /XD %EXCLUDE_DIRS% /XF %EXCLUDE_FILES% /R:2 /W:2 /NFL /NDL
if %ERRORLEVEL% GEQ 8 (
    echo Staging FAILED for %CHILD_A_NAME% with error code %ERRORLEVEL%.
    rmdir /s /q "%WORK_DIR%" >nul 2>&1
    pause
    exit /b 1
)
echo.

echo ============================================================
echo  Staging %CHILD_B_NAME%
echo ============================================================
robocopy "%SOURCE2_PATH%" "%WORK_DIR%\%CHILD_B_NAME%" /E /XD %EXCLUDE_DIRS% /XF %EXCLUDE_FILES% /R:2 /W:2 /NFL /NDL
if %ERRORLEVEL% GEQ 8 (
    echo Staging FAILED for %CHILD_B_NAME% with error code %ERRORLEVEL%.
    rmdir /s /q "%WORK_DIR%" >nul 2>&1
    pause
    exit /b 1
)
echo.

REM ------------------------------------------------------------------
REM  Zip the CONTENTS of each staged folder (the trailing \* means the
REM  zip has no wrapping bp/rp folder at its root).
REM ------------------------------------------------------------------
echo ============================================================
echo  Zipping %CHILD_A_NAME% and %CHILD_B_NAME%
echo ============================================================
powershell -NoProfile -Command "Compress-Archive -Path '%WORK_DIR%\%CHILD_A_NAME%\*' -DestinationPath '%WORK_DIR%\%CHILD_A_NAME%.zip' -Force"
if errorlevel 1 (
    echo Failed to zip %CHILD_A_NAME%.
    rmdir /s /q "%WORK_DIR%" >nul 2>&1
    pause
    exit /b 1
)
echo   Created %WORK_DIR%\%CHILD_A_NAME%.zip

powershell -NoProfile -Command "Compress-Archive -Path '%WORK_DIR%\%CHILD_B_NAME%\*' -DestinationPath '%WORK_DIR%\%CHILD_B_NAME%.zip' -Force"
if errorlevel 1 (
    echo Failed to zip %CHILD_B_NAME%.
    rmdir /s /q "%WORK_DIR%" >nul 2>&1
    pause
    exit /b 1
)
echo   Created %WORK_DIR%\%CHILD_B_NAME%.zip
echo.

REM ------------------------------------------------------------------
REM  Make sure the destination folder exists.
REM ------------------------------------------------------------------
if not exist "%DEST_DIR%" (
    echo Destination folder does not exist, creating it:
    echo   %DEST_DIR%
    mkdir "%DEST_DIR%" >nul 2>&1
    if not exist "%DEST_DIR%" (
        echo Failed to create destination folder. Check the path and permissions.
        rmdir /s /q "%WORK_DIR%" >nul 2>&1
        pause
        exit /b 1
    )
)

set "FINAL_ZIP=%DEST_DIR%\%OUTPUT_ZIP_NAME%"

if exist "%FINAL_ZIP%" (
    echo Output zip already exists:
    echo   %FINAL_ZIP%
    if /I "%AUTO_MODE%"=="Y" (
        echo Auto mode: overwriting without asking.
        set "CONFIRM=Y"
    ) else (
        set "CONFIRM="
        set /p "CONFIRM=Overwrite it? (Y/N): "
    )
    if /I not "!CONFIRM!"=="Y" (
        echo Aborted -- output zip not overwritten.
        rmdir /s /q "%WORK_DIR%" >nul 2>&1
        pause
        exit /b 1
    )
)

echo.
echo ============================================================
echo  Bundling %CHILD_A_NAME%.zip and %CHILD_B_NAME%.zip into final zip
echo ============================================================
powershell -NoProfile -Command "Compress-Archive -Path '%WORK_DIR%\%CHILD_A_NAME%.zip','%WORK_DIR%\%CHILD_B_NAME%.zip' -DestinationPath '%FINAL_ZIP%' -Force"
if errorlevel 1 (
    echo Failed to create the final combined zip.
    rmdir /s /q "%WORK_DIR%" >nul 2>&1
    pause
    exit /b 1
)

echo   Created: %FINAL_ZIP%
echo.

REM Cleanup staging area.
rmdir /s /q "%WORK_DIR%" >nul 2>&1

echo ------------------------------------------
echo Done. You can close this window now.
echo ------------------------------------------
pause
exit /b 0
